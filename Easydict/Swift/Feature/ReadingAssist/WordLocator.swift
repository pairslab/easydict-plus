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

/// Reads a word through web text markers or native character ranges, without changing selection.
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
        guard !ancestors.contains(where: isEditable) else {
            return nil
        }
        for node in ancestors {
            guard let found = webWord(in: node, at: point)
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
        return nil
    }

    // MARK: Private

    private static let maximumSentenceLength = 400
    private static let hitSlop: CGFloat = 2

    private func isEditable(_ element: AXUIElement) -> Bool {
        AXElementReader.attribute(element, "AXEditable") as? Bool == true
            || AXElementReader.isSettable(element, kAXValueAttribute)
    }

    /// Left and right ranges differ at word boundaries; accept only the range under the pointer.
    private func webWord(in element: AXUIElement, at point: CGPoint) -> (text: String, frame: CGRect)? {
        guard let marker = AXElementReader.parameterizedAttribute(
            element, "AXTextMarkerForPosition", AXElementReader.pointValue(point)
        ) else {
            return nil
        }
        for attribute in ["AXLeftWordTextMarkerRangeForTextMarker", "AXRightWordTextMarkerRangeForTextMarker"] {
            guard let range = AXElementReader.parameterizedAttribute(element, attribute, marker),
                  let text = AXElementReader.parameterizedAttribute(element, "AXStringForTextMarkerRange", range) as? String,
                  let frame = AXElementReader.rect(from: AXElementReader.parameterizedAttribute(
                      element, "AXBoundsForTextMarkerRange", range
                  )), let word = validated(text, frame: frame, at: point) else {
                continue
            }
            return word
        }
        return nil
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
