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

/// Where a double-clicked word sits and the sentence it was read in.
struct LocatedWord: Sendable {
    /// Screen frame of the word in Cocoa coordinates, when Accessibility exposes the selection bounds.
    let frame: CGRect?
    /// The sentence around the word, used to explain its meaning in context.
    let sentence: String?
}

// MARK: - WordLocator

/// Finds the frame and surrounding sentence of a word the user just double-clicked.
///
/// A double-click makes the app select exactly the word, so its bounds come from the current
/// selection; the sentence comes from the paragraph under the mouse. Run it off the main thread.
struct WordLocator: Sendable {
    // MARK: Internal

    let coordinateSpace: AXCoordinateSpace
    let maximumParagraphHeight: CGFloat

    func locate(_ word: String, near cocoaPoint: CGPoint) -> LocatedWord {
        let axPoint = coordinateSpace.axPoint(fromCocoa: cocoaPoint)
        let frame = AXElementReader.element(at: axPoint)
            .flatMap { selectionFrame(around: $0, near: axPoint) }
            .map(coordinateSpace.cocoaRect(fromAX:))

        let paragraph = ParagraphLocator(coordinateSpace: coordinateSpace, maximumHeight: maximumParagraphHeight)
            .paragraph(at: cocoaPoint)
        let sentence = paragraph.flatMap { Self.sentence(containing: word, in: $0.text) }
        return LocatedWord(frame: frame, sentence: sentence)
    }

    // MARK: Private

    private static let maximumSentenceLength = 400
    /// The selection must be this close to the click to belong to it.
    private static let hitSlop: CGFloat = 24

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

    /// Bounds of the selection in the element or its ancestors, from web text markers or a native range.
    private func selectionFrame(around element: AXUIElement, near point: CGPoint) -> CGRect? {
        for node in AXElementReader.ancestry(of: element) {
            let bounds: CGRect?
            if let markerRange = AXElementReader.attribute(node, "AXSelectedTextMarkerRange") {
                bounds = AXElementReader.rect(
                    from: AXElementReader.parameterizedAttribute(node, "AXBoundsForTextMarkerRange", markerRange)
                )
            } else if let range = AXElementReader.range(from: AXElementReader.attribute(
                node,
                kAXSelectedTextRangeAttribute
            )),
                range.length > 0 {
                bounds = AXElementReader.rect(
                    from: AXElementReader.parameterizedAttribute(
                        node,
                        "AXBoundsForRange",
                        AXElementReader.rangeValue(range)
                    )
                )
            } else {
                bounds = nil
            }

            if let bounds, bounds.width > 0, bounds.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(point) {
                return bounds
            }
        }
        return nil
    }
}
