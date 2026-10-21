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
    /// Screen rect of the caret or selection in the focused element, in Cocoa coordinates.
    ///
    /// Falls back to the focused element frame, and returns nil when Accessibility exposes neither.
    func focusedTextCaretRect() -> CGRect? {
        guard let element = try? frontmostAppElement?.focusedUIElement() else {
            return nil
        }

        if let range: CFRange = try? element.selectedTextRange(),
           let rect: CGRect = try? element.parameterizedAttribute(
               .boundsForRangeParameterized,
               param: range
           ),
           let caretRect = cocoaRect(fromAXRect: rect) {
            return caretRect
        }

        if let frame: CGRect = try? element.attribute(.frame) {
            return cocoaRect(fromAXRect: frame)
        }
        return nil
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

    // MARK: Private

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
