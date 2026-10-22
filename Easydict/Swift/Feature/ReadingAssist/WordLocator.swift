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

    /// Optional paragraph context must not hold up presentation of an already located word.
    func context(for word: String, at cocoaPoint: CGPoint) -> String? {
        ParagraphLocator(coordinateSpace: coordinateSpace, maximumHeight: maximumParagraphHeight)
            .paragraph(at: cocoaPoint)
            .flatMap { Self.sentence(containing: word, in: $0.text) }
    }

    // MARK: Private

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

    /// The sentence in `text` that contains `word` as a whole word, or the start of the text.
    private static func sentence(containing word: String, in text: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var match: String?
        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            let sentence = String(text[range])
            guard sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
                return true
            }
            match = sentence
            return false
        }

        let sentence = (match ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? nil : String(sentence.prefix(maximumSentenceLength))
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
            return .word(LocatedWord(word: found.text, frame: coordinateSpace.cocoaRect(fromAX: found.frame)))
        }
        if let found = descendantWord(under: element, at: point, trace: trace) {
            return .word(LocatedWord(word: found.text, frame: coordinateSpace.cocoaRect(fromAX: found.frame)))
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
        -> (text: String, frame: CGRect)? {
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
        -> (text: String, frame: CGRect)? {
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
        var nearest: (text: String, frame: CGRect, distance: CGFloat)?
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
                let text = nsText.substring(with: words[group.lowerBound])
                if let word = validated(text, frame: frame, at: point) {
                    logInfo("Reading assist: static text word located with \(queryCount) bounds queries")
                    return word
                }
                let distance = max(frame.minX - point.x, 0, point.x - frame.maxX)
                if distance <= Self.wordSnapDistance, distance < nearest?.distance ?? .infinity {
                    nearest = (text, frame, distance)
                }
                continue
            }
            let middle = group.lowerBound + group.count / 2
            groups.append(middle ..< group.upperBound)
            groups.append(group.lowerBound ..< middle)
        }
        if let nearest {
            let pointOnWord = CGPoint(x: min(max(point.x, nearest.frame.minX), nearest.frame.maxX), y: point.y)
            if let word = validated(nearest.text, frame: nearest.frame, at: pointOnWord) {
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
    private func webWord(in element: AXUIElement, at point: CGPoint) -> (text: String, frame: CGRect)? {
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
    private func nativeWord(in element: AXUIElement, at point: CGPoint) -> (text: String, frame: CGRect)? {
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
        return validated(String(paragraph[token]), frame: frame, at: point)
    }

    /// A static label can be used only when the entire label is one word.
    private func labelWord(in element: AXUIElement, at point: CGPoint) -> (text: String, frame: CGRect)? {
        guard AXElementReader.role(of: element) == kAXStaticTextRole,
              let text = AXElementReader.string(element, kAXValueAttribute),
              let frame = AXElementReader.frame(of: element) else {
            return nil
        }
        return validated(text, frame: frame, at: point)
    }

    private func validated(_ text: String, frame: CGRect, at point: CGPoint) -> (text: String, frame: CGRect)? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordLookupManager.accepts(word), frame.width > 0, frame.height > 0,
              frame.height <= maximumParagraphHeight,
              frame.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(point) else {
            return nil
        }
        return (word, frame)
    }
}
