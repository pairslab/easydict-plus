//
//  SystemUtility+Caret.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import AXSwift

// MARK: - SystemUtility + Caret

extension SystemUtility {
    /// Screen rect to anchor floating UI next to the caret, in Cocoa coordinates.
    ///
    /// Uses the caret or selection bounds, extended vertically to the whole element for compact
    /// inputs such as chat boxes so anchored UI sits outside them instead of covering their border.
    /// Falls back to the focused element frame, and returns nil when Accessibility exposes neither.
    func focusedTextCaretRect() -> CGRect? {
        guard let element = try? frontmostAppElement?.focusedUIElement() else {
            return nil
        }

        let elementFrame = (try? element.attribute(.frame) as CGRect?).flatMap(cocoaRect(fromAXRect:))

        guard let range: CFRange = try? element.selectedTextRange(),
              let rect: CGRect = try? element.parameterizedAttribute(
                  .boundsForRangeParameterized,
                  param: range
              ),
              let caretRect = cocoaRect(fromAXRect: rect)
        else {
            return elementFrame
        }

        if let elementFrame, elementFrame.height <= Self.compactInputMaxHeight {
            return CGRect(x: caretRect.minX, y: elementFrame.minY, width: caretRect.width, height: elementFrame.height)
        }
        return caretRect
    }

    /// Focused element info for writing text back, without reading the selection.
    ///
    /// Reading the selection may simulate a copy in the target app, which is unnecessary
    /// when the caller only needs to choose an insertion strategy.
    func focusedElementInfoForInsertion() -> FocusedElementInfo {
        guard let element = try? frontmostAppElement?.focusedUIElement() else {
            return .empty
        }
        return FocusedElementInfo(
            fullText: try? element.value(),
            selectedRange: try? element.selectedTextRange(),
            selectedText: nil,
            roleValue: try? element.roleValue()
        )
    }

    /// Current value of the focused element, used to confirm that a write took effect.
    func focusedElementValue() -> String? {
        try? frontmostAppElement?.focusedUIElement()?.value()
    }

    /// Selected range of the focused element, or nil when Accessibility cannot read it.
    func focusedSelectedRange() -> CFRange? {
        try? frontmostAppElement?.focusedUIElement()?.selectedTextRange()
    }

    // MARK: Private

    /// Inputs up to this height (a few lines) are treated as compact fields such as chat boxes.
    private static let compactInputMaxHeight: CGFloat = 160

    /// Converts a top-left based Accessibility rect into a bottom-left based Cocoa rect.
    ///
    /// Empty rects are rejected because many apps report `.zero` when bounds are unsupported.
    private func cocoaRect(fromAXRect rect: CGRect) -> CGRect? {
        guard rect.width > 0 || rect.height > 0,
              let primaryScreen = NSScreen.screens.first
        else {
            return nil
        }

        let flippedY = primaryScreen.frame.maxY - rect.maxY
        let cocoaRect = CGRect(x: rect.minX, y: flippedY, width: rect.width, height: rect.height)
        let isOnScreen = NSScreen.screens.contains { $0.frame.intersects(cocoaRect) }
        return isOnScreen ? cocoaRect : nil
    }
}
