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

/// A word directly under the pointer and the sentence it was read in.
struct LocatedWord: Sendable {
    let word: String
    /// Screen frame of the word in Cocoa coordinates.
    let frame: CGRect
    /// The sentence around the word, used to explain its meaning in context.
    let sentence: String?
}

// MARK: - WordLocator

/// Reads a word through text range bounds, web markers, or native character positions.
/// All Accessibility calls wait on the target app, so run this off the main thread.
struct WordLocator: Sendable {
    // MARK: Internal

    let coordinateSpace: AXCoordinateSpace
    let maximumParagraphHeight: CGFloat

    func locate(at cocoaPoint: CGPoint) -> LocatedWord? {
        let point = coordinateSpace.axPoint(fromCocoa: cocoaPoint)
        guard let element = AXElementReader.element(at: point),
              AXElementReader.processIdentifier(of: element) != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        let ancestors = AXElementReader.ancestry(of: element)
        if let editable = ancestors.first(where: isEditable) {
            logInfo("Reading assist: editable text ignored, role: \(AXElementReader.role(of: editable) ?? "unknown")")
            return nil
        }
        for node in ancestors {
            guard let found = staticTextWord(in: node, at: point)
                ?? webWord(in: node, at: point)
                ?? nativeWord(in: node, at: point)
                ?? labelWord(in: node, at: point) else {
                continue
            }
            let paragraph = ParagraphLocator(coordinateSpace: coordinateSpace, maximumHeight: maximumParagraphHeight)
                .paragraph(at: cocoaPoint)
            return LocatedWord(
                word: found.text,
                frame: coordinateSpace.cocoaRect(fromAX: found.frame),
                sentence: paragraph.flatMap { Self.sentence(containing: found.text, in: $0.text) }
            )
        }
        let roles = ancestors.compactMap { AXElementReader.role(of: $0) }.joined(separator: "/")
        logInfo("Reading assist: unsupported word geometry, roles: \(roles)")
        return nil
    }

    // MARK: Private

    private static let maximumSentenceLength = 400
    private static let maximumStaticTextLength = 16000
    private static let maximumBoundsQueries = 64
    private static let hitSlop: CGFloat = 2

    private func isEditable(_ element: AXUIElement) -> Bool {
        AXElementReader.attribute(element, "AXEditable") as? Bool == true
            || AXElementReader.isSettable(element, kAXValueAttribute)
    }

    /// Chromium exposes bounds for static text ranges even when position-to-marker lookup is absent.
    /// Prune groups by their bounds so long text runs do not require a query for every word.
    private func staticTextWord(in element: AXUIElement, at point: CGPoint) -> (text: String, frame: CGRect)? {
        guard AXElementReader.role(of: element) == kAXStaticTextRole,
              let text = AXElementReader.string(element, kAXValueAttribute),
              !text.isEmpty, text.utf16.count <= Self.maximumStaticTextLength else {
            return nil
        }
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
            return nil
        }

        let nsText = text as NSString
        var groups = [words.indices]
        var queryCount = 0
        while let group = groups.popLast(), queryCount < Self.maximumBoundsQueries {
            let start = words[group.lowerBound].location
            let end = NSMaxRange(words[group.upperBound - 1])
            let range = CFRange(location: start, length: end - start)
            queryCount += 1
            guard let frame = AXElementReader.rect(from: AXElementReader.parameterizedAttribute(
                element, "AXBoundsForRange", AXElementReader.rangeValue(range)
            )), frame.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(point) else {
                continue
            }
            if group.count == 1 {
                if let word = validated(nsText.substring(with: words[group.lowerBound]), frame: frame, at: point) {
                    logInfo("Reading assist: static text word located with \(queryCount) bounds queries")
                    return word
                }
                continue
            }
            let middle = group.lowerBound + group.count / 2
            groups.append(middle ..< group.upperBound)
            groups.append(group.lowerBound ..< middle)
        }
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
}
