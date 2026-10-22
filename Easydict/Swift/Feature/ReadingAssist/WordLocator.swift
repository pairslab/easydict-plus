//
//  WordLocator.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import NaturalLanguage

// MARK: - LocatedWord

/// A word directly under the pointer, ready to display before reading its context.
struct LocatedWord: Sendable {
    let word: String
    /// Screen frame of the word in Cocoa coordinates.
    let frame: CGRect
    /// Where the word was read, so its own sentence is found rather than another occurrence.
    var anchor: TextAnchor?
}

// MARK: - TextAnchor

/// The text element a word was read from and the word's place in it.
struct TextAnchor: @unchecked Sendable {
    enum Kind: Sendable {
        /// A web or PDF text run; its sentence can continue into neighboring runs.
        case textRun
        /// A native text view whose value holds the surrounding text.
        case textView
    }

    let element: AXUIElement
    let kind: Kind
    /// The word's UTF-16 range in the element's value.
    let range: NSRange
    /// Height of the word's line in Accessibility points.
    let lineHeight: CGFloat
}

// MARK: - WordLocation

/// The outcome of reading the word under the pointer.
enum WordLocation: Sendable {
    case word(LocatedWord)
    /// The app was asked to build text geometry; a retry shortly may find the word.
    case loadingGeometry
    case unavailable
}

// MARK: - LocateTrace

/// What one lookup observed, used to decide whether waiting for the app can help.
private final class LocateTrace {
    var sawEmptyRangeBounds = false
    /// Any static text was reached; without it, a web area has not built its tree under the pointer.
    var sawStaticText = false
}

// MARK: - WordLocator

/// Reads a word through text range bounds, web markers, or native character positions.
/// All Accessibility calls wait on the target app, so run this off the main thread.
struct WordLocator: Sendable {
    // MARK: Internal

    let coordinateSpace: AXCoordinateSpace
    let maximumParagraphHeight: CGFloat

    func locate(at cocoaPoint: CGPoint) -> WordLocation {
        let point = coordinateSpace.axPoint(fromCocoa: cocoaPoint)
        guard let element = AXElementReader.element(at: point) else {
            return .unavailable
        }
        let processIdentifier = AXElementReader.processIdentifier(of: element)
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return .unavailable
        }
        let app = NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier ?? "unknown"
        let hitFrame = AXElementReader.frame(of: element).map { "\($0)" } ?? "nil"
        logInfo(
            "Reading assist: hit \(AXElementReader.role(of: element) ?? "unknown") in \(app), point: \(point), frame: \(hitFrame)"
        )
        return locate(from: element, at: point)
    }

    /// The sentence the located word was read in; read after the card shows, so it never delays it.
    ///
    /// The word's own text element is preferred: a paragraph read at the point can be a whole PDF page.
    func context(for located: LocatedWord, at cocoaPoint: CGPoint) -> String? {
        if let anchor = located.anchor {
            if let sentence = sentence(around: anchor) {
                return sentence
            }
            logInfo("Reading assist: sentence around the word unavailable, using the paragraph")
        }
        return ParagraphLocator(coordinateSpace: coordinateSpace, maximumHeight: maximumParagraphHeight)
            .paragraph(at: cocoaPoint)
            .flatMap { SentenceAssembler.sentence(
                containing: located.word,
                in: $0.text,
                maximumLength: Self.maximumSentenceLength
            ) }
    }

    // MARK: Private

    /// A located word, with where it was read when that is known.
    private typealias Hit = (text: String, frame: CGRect, anchor: TextAnchor?)

    private static let maximumSentenceLength = 400
    private static let maximumStaticTextLength = 16000
    private static let maximumBoundsQueries = 64
    private static let maximumAncestorDepth = 32
    private static let maximumDescendantVisits = 128
    private static let hitSlop: CGFloat = 2
    /// How far a pointer resting between words or on punctuation may be from the word it reads.
    private static let wordSnapDistance: CGFloat = 5
    /// Search fields are text fields with a search subrole; Safari exposes some web search boxes as combo boxes.
    private static let textInputRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

    /// Characters read on each side of the word when rebuilding its sentence.
    private static let contextWindow = 1500

    /// The sentence at the anchor, rebuilt from neighboring text runs or the native text around it.
    private func sentence(around anchor: TextAnchor) -> String? {
        switch anchor.kind {
        case .textView:
            guard let text = AXElementReader.string(anchor.element, kAXValueAttribute),
                  let excerpt = SentenceAssembler.excerpt(of: text, around: anchor.range, limit: Self.contextWindow)
            else {
                return nil
            }
            return SentenceAssembler.sentence(
                in: excerpt.text, around: excerpt.range, maximumLength: Self.maximumSentenceLength
            )
        case .textRun:
            guard let paragraph = TextRunReader.paragraph(
                around: anchor.element, lineHeight: anchor.lineHeight, limit: Self.contextWindow
            ) else {
                return nil
            }
            let joined = paragraph.joined
            logInfo("Reading assist: sentence rebuilt from \(joined.runCount) of \(paragraph.runsInBlock) text runs")
            let range = NSRange(location: joined.anchorOffset + anchor.range.location, length: anchor.range.length)
            return SentenceAssembler.sentence(in: joined.text, around: range, maximumLength: Self.maximumSentenceLength)
        }
    }

    /// Searches around an element for the word at `point` in Accessibility coordinates.
    private func locate(from element: AXUIElement, at point: CGPoint) -> WordLocation {
        let processIdentifier = AXElementReader.processIdentifier(of: element)
        let ancestors = textAncestors(of: element)
        if let editable = ancestors.first(where: isEditable) {
            logInfo("Reading assist: editable text ignored, role: \(AXElementReader.role(of: editable) ?? "unknown")")
            return .unavailable
        }
        let trace = LocateTrace()
        for node in ancestors {
            guard let found = staticTextWord(in: node, at: point, trace: trace)
                ?? webWord(in: node, at: point)
                ?? nativeWord(in: node, at: point)
                ?? labelWord(in: node, at: point) else {
                continue
            }
            return .word(located(found))
        }
        if let found = descendantWord(under: element, at: point, trace: trace) {
            return .word(located(found))
        }
        let roles = ancestors.compactMap { AXElementReader.role(of: $0) }
        logInfo("Reading assist: unsupported word geometry, roles: \(roles.joined(separator: "/"))")
        // Only web content builds geometry on request; native apps keep their accessibility mode.
        guard roles.contains("AXWebArea") else {
            return .unavailable
        }
        // Text without range bounds lacks inline text boxes; no text at all means a basic Electron tree.
        let need: WebTextGeometry.Need
        if trace.sawEmptyRangeBounds {
            need = .inlineTextBoxes
        } else if !trace.sawStaticText {
            need = .textTree
        } else {
            return .unavailable
        }
        if WebTextGeometry.shared.request(need, for: processIdentifier) {
            logInfo("Reading assist: waiting for web text geometry")
            return .loadingGeometry
        }
        logInfo("Reading assist: web text geometry unavailable or still empty after the settle time")
        return .unavailable
    }

    /// Deep web layouts need to reach their document without walking into browser chrome.
    private func textAncestors(of element: AXUIElement) -> [AXUIElement] {
        var ancestors = [element]
        var node = element
        while ancestors.count < Self.maximumAncestorDepth,
              AXElementReader.role(of: node) != "AXWebArea",
              let parent = AXElementReader.parent(of: node) {
            ancestors.append(parent)
            node = parent
        }
        return ancestors
    }

    /// Chromium can hit-test the text container instead of its static text,
    /// so search down through children whose frames contain the point.
    /// A wrapper can report a collapsed frame while its content overflows it, so pass through those.
    private func descendantWord(
        under element: AXUIElement,
        at point: CGPoint,
        trace: LocateTrace
    )
        -> Hit? {
        var queue = AXElementReader.children(of: element)
        var visits = 0
        var missed: [String] = []
        while !queue.isEmpty, visits < Self.maximumDescendantVisits {
            let node = queue.removeFirst()
            visits += 1
            guard let frame = AXElementReader.frame(of: node) else {
                continue
            }
            let isCollapsed = frame.width <= 1 || frame.height <= 1
            guard isCollapsed || frame.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(point) else {
                if missed.count < 4 {
                    missed.append("\(AXElementReader.role(of: node) ?? "unknown") \(frame)")
                }
                continue
            }
            if !isCollapsed, let found = staticTextWord(in: node, at: point, trace: trace) {
                logInfo("Reading assist: descendant static text word located after \(visits) visits")
                return found
            }
            queue.append(contentsOf: AXElementReader.children(of: node))
        }
        logInfo("Reading assist: no descendant word, visits: \(visits), missed: \(missed.joined(separator: "; "))")
        return nil
    }

    /// Lists, tables, and web groups can expose a settable value for their selection,
    /// so a settable value means typing only on a text input role.
    private func isEditable(_ element: AXUIElement) -> Bool {
        if AXElementReader.attribute(element, "AXEditable") as? Bool == true {
            return true
        }
        guard let role = AXElementReader.role(of: element), Self.textInputRoles.contains(role) else {
            return false
        }
        return AXElementReader.isSettable(element, kAXValueAttribute)
    }

    /// Chromium exposes bounds for static text ranges even when position-to-marker lookup is absent.
    /// Prune groups by their bounds so long text runs do not require a query for every word.
    private func staticTextWord(
        in element: AXUIElement,
        at point: CGPoint,
        trace: LocateTrace
    )
        -> Hit? {
        guard AXElementReader.role(of: element) == kAXStaticTextRole,
              let text = AXElementReader.string(element, kAXValueAttribute),
              !text.isEmpty, text.utf16.count <= Self.maximumStaticTextLength else {
            return nil
        }
        trace.sawStaticText = true
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            if WordLookupManager.accepts(String(text[range])) {
                words.append(NSRange(range, in: text))
            }
            return true
        }
        guard !words.isEmpty else {
            logInfo("Reading assist: static text has no supported Latin words")
            return nil
        }

        let nsText = text as NSString
        var groups = [words.indices]
        var queryCount = 0
        var boundsCount = 0
        var firstBounds: CGRect?
        var nearest: (text: String, range: NSRange, frame: CGRect, distance: CGFloat)?
        while let group = groups.popLast(), queryCount < Self.maximumBoundsQueries {
            let start = words[group.lowerBound].location
            let end = NSMaxRange(words[group.upperBound - 1])
            let range = CFRange(location: start, length: end - start)
            queryCount += 1
            guard let frame = AXElementReader.rect(from: AXElementReader.parameterizedAttribute(
                element, "AXBoundsForRange", AXElementReader.rangeValue(range)
            )) else {
                continue
            }
            boundsCount += 1
            firstBounds = firstBounds ?? frame
            // Without inline text boxes Chromium answers with an empty rect; see `WebTextGeometry`.
            if frame.width <= 0 || frame.height <= 0, AXElementReader.frame(of: element)?.isEmpty == false {
                trace.sawEmptyRangeBounds = true
                break
            }
            // Keep neighbors on the same line, so a pointer between words or on punctuation can snap.
            guard frame.insetBy(dx: -Self.wordSnapDistance, dy: -Self.hitSlop).contains(point) else {
                continue
            }
            if group.count == 1 {
                let wordRange = words[group.lowerBound]
                let text = nsText.substring(with: wordRange)
                if let word = validated(text, frame: frame, at: point, source: (element, .textRun, wordRange)) {
                    logInfo("Reading assist: static text word located with \(queryCount) bounds queries")
                    return word
                }
                let distance = max(frame.minX - point.x, 0, point.x - frame.maxX)
                if distance <= Self.wordSnapDistance, distance < nearest?.distance ?? .infinity {
                    nearest = (text, wordRange, frame, distance)
                }
                continue
            }
            let middle = group.lowerBound + group.count / 2
            groups.append(middle ..< group.upperBound)
            groups.append(group.lowerBound ..< middle)
        }
        if let nearest {
            let pointOnWord = CGPoint(x: min(max(point.x, nearest.frame.minX), nearest.frame.maxX), y: point.y)
            if let word = validated(
                nearest.text, frame: nearest.frame, at: pointOnWord, source: (element, .textRun, nearest.range)
            ) {
                logInfo("Reading assist: snapped \(Int(nearest.distance.rounded())) pt to the nearest word")
                return word
            }
        }
        let elementFrame = AXElementReader.frame(of: element).map { "\($0)" } ?? "nil"
        logInfo(
            "Reading assist: no static text hit, queries: \(queryCount), available bounds: \(boundsCount), "
                + "first bounds: \(firstBounds.map { "\($0)" } ?? "nil"), element frame: \(elementFrame), "
                + "UTF-16 length: \(nsText.length), words: \(words.count)"
        )
        return nil
    }

    /// Expand to both word boundaries; one-sided word ranges can contain only a word fragment.
    private func webWord(in element: AXUIElement, at point: CGPoint) -> Hit? {
        guard let marker = AXElementReader.parameterizedAttribute(
            element, "AXTextMarkerForPosition", AXElementReader.pointValue(point)
        ), let start = AXElementReader.parameterizedAttribute(
            element, "AXPreviousWordStartTextMarkerForTextMarker", marker
        ), let end = AXElementReader.parameterizedAttribute(
            element, "AXNextWordEndTextMarkerForTextMarker", marker
        ), let range = AXElementReader.parameterizedAttribute(
            element, "AXTextMarkerRangeForUnorderedTextMarkers", [start, end] as CFArray
        ), let text = AXElementReader.parameterizedAttribute(element, "AXStringForTextMarkerRange", range) as? String,
        let frame = AXElementReader.rect(from: AXElementReader.parameterizedAttribute(
            element, "AXBoundsForTextMarkerRange", range
        )) else {
            return nil
        }
        return validated(text, frame: frame, at: point)
    }

    /// Tokenize the native paragraph at the reported character, never an unrelated existing selection.
    private func nativeWord(in element: AXUIElement, at point: CGPoint) -> Hit? {
        guard let characterRange = AXElementReader.range(from: AXElementReader.parameterizedAttribute(
            element, "AXRangeForPosition", AXElementReader.pointValue(point)
        )), let text = AXElementReader.string(element, kAXValueAttribute) else {
            return nil
        }
        let nsText = text as NSString
        guard characterRange.location >= 0, characterRange.location < nsText.length else {
            return nil
        }
        let paragraphRange = nsText.paragraphRange(for: NSRange(location: characterRange.location, length: 0))
        let paragraph = nsText.substring(with: paragraphRange)
        let offset = characterRange.location - paragraphRange.location
        guard let position = Range(NSRange(location: offset, length: 0), in: paragraph)?.lowerBound else {
            return nil
        }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = paragraph
        let token = tokenizer.tokenRange(at: position)
        let tokenRange = NSRange(token, in: paragraph)
        let range = CFRange(location: paragraphRange.location + tokenRange.location, length: tokenRange.length)
        guard let frame = AXElementReader.rect(from: AXElementReader.parameterizedAttribute(
            element, "AXBoundsForRange", AXElementReader.rangeValue(range)
        )) else {
            return nil
        }
        return validated(
            String(paragraph[token]),
            frame: frame,
            at: point,
            source: (element, .textView, NSRange(location: range.location, length: range.length))
        )
    }

    /// A static label can be used only when the entire label is one word.
    private func labelWord(in element: AXUIElement, at point: CGPoint) -> Hit? {
        guard AXElementReader.role(of: element) == kAXStaticTextRole,
              let text = AXElementReader.string(element, kAXValueAttribute),
              let frame = AXElementReader.frame(of: element) else {
            return nil
        }
        let wordRange = (text as NSString).range(of: text.trimmingCharacters(in: .whitespacesAndNewlines))
        return validated(text, frame: frame, at: point, source: (element, .textRun, wordRange))
    }

    private func validated(
        _ text: String,
        frame: CGRect,
        at point: CGPoint,
        source: (element: AXUIElement, kind: TextAnchor.Kind, range: NSRange)? = nil
    )
        -> Hit? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordLookupManager.accepts(word), frame.width > 0, frame.height > 0,
              frame.height <= maximumParagraphHeight,
              frame.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(point) else {
            return nil
        }
        let anchor = source.map {
            TextAnchor(element: $0.element, kind: $0.kind, range: $0.range, lineHeight: frame.height)
        }
        return (word, frame, anchor)
    }

    private func located(_ hit: Hit) -> LocatedWord {
        LocatedWord(word: hit.text, frame: coordinateSpace.cocoaRect(fromAX: hit.frame), anchor: hit.anchor)
    }
}

// MARK: - TextRunReader

/// Reads the paragraph around a web or PDF text run from its laid-out neighbors.
///
/// Shared by the word card's sentence and the hold-to-translate paragraph, so neither joins a whole
/// PDF text layer. Every call waits on the target app, so run it off the main thread.
enum TextRunReader {
    // MARK: Internal

    /// The paragraph continuing around `element`, reading at most `limit` characters on each side.
    static func paragraph(
        around element: AXUIElement,
        lineHeight: CGFloat,
        limit: Int
    )
        -> (joined: SentenceAssembler.Joined, runsInBlock: Int)? {
        let runs = runs(around: element)
        guard let anchorIndex = runs.firstIndex(where: { CFEqual($0, element) }),
              let joined = SentenceAssembler.join(
                  count: runs.count,
                  anchorIndex: anchorIndex,
                  lineHeight: lineHeight,
                  limit: limit,
                  run: { index in
                      guard let text = AXElementReader.string(runs[index], kAXValueAttribute),
                            let frame = AXElementReader.frame(of: runs[index]) else {
                          return nil
                      }
                      return SentenceAssembler.Run(text: text, frame: frame)
                  }
              )
        else {
            return nil
        }
        return (joined, runs.count)
    }

    /// The height of the run's first line: its first character's bounds, or the run's own frame.
    static func lineHeight(of element: AXUIElement) -> CGFloat? {
        let firstCharacter = AXElementReader.rect(from: AXElementReader.parameterizedAttribute(
            element, "AXBoundsForRange", AXElementReader.rangeValue(CFRange(location: 0, length: 1))
        ))
        if let firstCharacter, firstCharacter.height > 0 {
            return firstCharacter.height
        }
        return AXElementReader.frame(of: element).map(\.height).flatMap { $0 > 0 ? $0 : nil }
    }

    // MARK: Private

    /// Enough runs for any page of a PDF text layer.
    private static let maximumRuns = 3000
    /// Inline wrappers, such as links or emphasis, climbed to reach the block holding the paragraph.
    private static let maximumClimb = 4
    private static let maximumDepth = 8

    /// The text runs of the block holding `element`, in reading order.
    /// Climbs out of wrappers that hold no other text, so a word inside a link still reads its paragraph.
    private static func runs(around element: AXUIElement) -> [AXUIElement] {
        var block = element
        var runs = [element]
        for _ in 0 ..< maximumClimb {
            guard let parent = AXElementReader.parent(of: block) else {
                break
            }
            block = parent
            runs = staticTexts(in: block)
            if runs.count > 1 || AXElementReader.role(of: block) == "AXWebArea" {
                break
            }
        }
        return runs
    }

    private static func staticTexts(in element: AXUIElement) -> [AXUIElement] {
        var runs: [AXUIElement] = []
        func collect(_ node: AXUIElement, depth: Int) {
            guard runs.count < maximumRuns else {
                return
            }
            if AXElementReader.role(of: node) == kAXStaticTextRole {
                runs.append(node)
                return
            }
            guard depth < maximumDepth else {
                return
            }
            AXElementReader.children(of: node).forEach { collect($0, depth: depth + 1) }
        }
        collect(element, depth: 0)
        return runs
    }
}

// MARK: - SentenceAssembler

/// Rebuilds the text around a word from laid-out text runs and cuts out the word's own sentence.
///
/// PDF text layers split a page into line or fragment runs, so joining a whole block reads a page.
/// Only runs that continue the word's paragraph are joined: on the same line within a word gap, or
/// on the next line in the same column without a paragraph gap.
enum SentenceAssembler {
    // MARK: Internal

    struct Run {
        let text: String
        /// Frame in Accessibility coordinates, with a top-left origin.
        let frame: CGRect
    }

    struct Joined {
        let text: String
        /// UTF-16 offset of the anchor run's text in `text`.
        let anchorOffset: Int
        let runCount: Int
        /// Union of the joined runs' frames, in Accessibility coordinates.
        let frame: CGRect
    }

    /// Joins the runs around `anchorIndex` that continue its paragraph, reading at most `limit`
    /// characters on each side. Runs are fetched lazily, since a block can hold a whole page.
    static func join(
        count: Int,
        anchorIndex: Int,
        lineHeight: CGFloat,
        limit: Int,
        run: (Int) -> Run?
    )
        -> Joined? {
        guard anchorIndex >= 0, anchorIndex < count, let anchor = run(anchorIndex) else {
            return nil
        }
        let lineHeight = max(lineHeight, 1)
        var column = anchor.frame

        var before: [Run] = []
        var edge = anchor
        var length = 0
        var index = anchorIndex - 1
        while index >= 0, length < limit, let previous = run(index) {
            index -= 1
            before.append(previous)
            length += previous.text.utf16.count
            // Whitespace runs separate words but carry no position worth following.
            guard !isBlank(previous) else {
                continue
            }
            guard continues(from: previous, to: edge, column: column, lineHeight: lineHeight) else {
                before.removeLast()
                break
            }
            column = column.union(previous.frame)
            edge = previous
        }

        var after: [Run] = []
        edge = anchor
        length = 0
        index = anchorIndex + 1
        while index < count, length < limit, let next = run(index) {
            index += 1
            after.append(next)
            length += next.text.utf16.count
            guard !isBlank(next) else {
                continue
            }
            guard continues(from: edge, to: next, column: column, lineHeight: lineHeight) else {
                after.removeLast()
                break
            }
            column = column.union(next.frame)
            edge = next
        }

        var text = ""
        var anchorOffset = 0
        var frame = anchor.frame
        var previous: Run?
        let runs = before.reversed() + [anchor] + after
        for (position, current) in runs.enumerated() {
            if let previous {
                appendSeparator(to: &text, between: previous, and: current, lineHeight: lineHeight)
            }
            if position == before.count {
                anchorOffset = (text as NSString).length
            }
            text += current.text
            if !isBlank(current) {
                frame = frame.union(current.frame)
                previous = current
            }
        }
        return Joined(text: text, anchorOffset: anchorOffset, runCount: runs.count, frame: frame)
    }

    /// The paragraph around `range` in a text view's value, reading line breaks inside it as spaces.
    /// Offsets are kept, so the returned range still marks the word.
    static func excerpt(of text: String, around range: NSRange, limit: Int) -> (text: String, range: NSRange)? {
        let nsText = text as NSString
        guard range.location >= 0, NSMaxRange(range) <= nsText.length else {
            return nil
        }
        var start = max(0, range.location - limit)
        var end = min(nsText.length, NSMaxRange(range) + limit)
        // Blank lines end paragraphs even where single line breaks only wrap lines, as in PDF text.
        for separator in ["\n\n", "\u{2029}"] {
            let before = nsText.range(
                of: separator, options: .backwards, range: NSRange(location: start, length: range.location - start)
            )
            if before.location != NSNotFound {
                start = NSMaxRange(before)
            }
            let after = nsText.range(
                of: separator, range: NSRange(location: NSMaxRange(range), length: end - NSMaxRange(range))
            )
            if after.location != NSNotFound {
                end = after.location
            }
        }
        let paragraph = NSMutableString(string: nsText.substring(with: NSRange(location: start, length: end - start)))
        for lineBreak in ["\r", "\n", "\u{2028}"] {
            paragraph.replaceOccurrences(
                of: lineBreak, with: " ", range: NSRange(location: 0, length: paragraph.length)
            )
        }
        return (paragraph as String, NSRange(location: range.location - start, length: range.length))
    }

    /// The sentence holding `range`, with whitespace collapsed. A long sentence becomes a window
    /// around the word, marked with ellipses where it was cut.
    static func sentence(in text: String, around range: NSRange, maximumLength: Int) -> String? {
        let nsText = text as NSString
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= nsText.length,
              let word = Range(range, in: text) else {
            return nil
        }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentence = NSUnionRange(NSRange(tokenizer.tokenRange(at: word.lowerBound), in: text), range)
        var prefix = ""
        var suffix = ""
        if sentence.length > maximumLength {
            let half = max((maximumLength - range.length) / 2, 0)
            var start = max(sentence.location, range.location - half)
            var end = min(NSMaxRange(sentence), NSMaxRange(range) + half)
            if start > sentence.location {
                let gap = nsText.rangeOfCharacter(
                    from: .whitespacesAndNewlines, range: NSRange(location: start, length: range.location - start)
                )
                start = gap.location == NSNotFound ? start : NSMaxRange(gap)
                prefix = "… "
            }
            if end < NSMaxRange(sentence) {
                let gap = nsText.rangeOfCharacter(
                    from: .whitespacesAndNewlines,
                    options: .backwards,
                    range: NSRange(location: NSMaxRange(range), length: end - NSMaxRange(range))
                )
                end = gap.location == NSNotFound ? end : gap.location
                suffix = " …"
            }
            sentence = NSRange(location: start, length: end - start)
        }
        let collapsed = nsText.substring(with: sentence).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : prefix + collapsed + suffix
    }

    /// The sentence holding the first whole-word `word` in text read without the word's position.
    /// Returns nil when the word is absent, rather than unrelated text such as the start of a page.
    static func sentence(containing word: String, in text: String, maximumLength: Int) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return sentence(in: text, around: NSRange(match, in: text), maximumLength: maximumLength)
    }

    // MARK: Private

    /// Wider than a word gap, narrower than a column gutter.
    private static let columnGapRatio: CGFloat = 1
    /// Line spacing stays below this; paragraph and section gaps exceed it.
    private static let paragraphGapRatio: CGFloat = 0.7
    /// Glyph runs closer than this belong to one word.
    private static let wordGapRatio: CGFloat = 0.12

    private static func isBlank(_ run: Run) -> Bool {
        run.text.allSatisfy(\.isWhitespace)
    }

    private static func isSameLine(_ first: CGRect, _ second: CGRect, lineHeight: CGFloat) -> Bool {
        min(first.maxY, second.maxY) - max(first.minY, second.minY) > lineHeight / 2
    }

    /// Whether `later` follows `earlier` in the same paragraph.
    private static func continues(from earlier: Run, to later: Run, column: CGRect, lineHeight: CGFloat) -> Bool {
        if isSameLine(earlier.frame, later.frame, lineHeight: lineHeight) {
            return later.frame.minX - earlier.frame.maxX <= lineHeight * columnGapRatio
        }
        let lineGap = later.frame.minY - earlier.frame.maxY
        guard lineGap > -lineHeight / 2, lineGap <= lineHeight * paragraphGapRatio,
              later.frame.minX < column.maxX, later.frame.maxX > column.minX else {
            return false
        }
        // Papers often start paragraphs without a gap: the new line is indented, or the last line
        // of the previous paragraph ends a sentence well short of the column edge. Requiring the
        // opposite edge to stay aligned keeps centered lines, short on both sides, in one paragraph.
        let isIndented = later.frame.minX - column.minX > lineHeight / 2
            && column.maxX - later.frame.maxX <= lineHeight
        let endsShort = column.maxX - earlier.frame.maxX > lineHeight * 2
            && earlier.frame.minX - column.minX <= lineHeight / 2
            && earlier.text.trimmingCharacters(in: .whitespaces).last.map { ".?!:".contains($0) } == true
        return !isIndented && !endsShort
    }

    /// Nothing inside a word split into glyph runs, a space between words or lines, and no hyphen
    /// where it only broke a word across lines.
    private static func appendSeparator(
        to text: inout String,
        between previous: Run,
        and next: Run,
        lineHeight: CGFloat
    ) {
        guard let last = previous.text.last, let first = next.text.first,
              !last.isWhitespace, !first.isWhitespace, text.last?.isWhitespace == false else {
            return
        }
        if isSameLine(previous.frame, next.frame, lineHeight: lineHeight) {
            let gap = next.frame.minX - previous.frame.maxX
            if gap > lineHeight * wordGapRatio || gap < -lineHeight / 2 {
                text += " "
            }
            return
        }
        if last == "-" || last == "\u{00AD}", first.isLowercase, previous.text.dropLast().last?.isLetter == true {
            text.removeLast()
            return
        }
        text += " "
    }
}
