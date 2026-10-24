//
//  SystemUtility+Selection.swift
//  Easydict
//
//  Created by tisfeng on 2025/9/9.
//  Copyright © 2025 izual. All rights reserved.
//

import AppKit
import SelectedTextKit

extension SystemUtility {
    /// Probes a selection without copy shortcuts or pasteboard writes during a reading gesture.
    /// Returns promptly for an empty selection; the deadline only bounds an unresponsive AX client.
    ///
    /// The selection is used only when the gesture points at it: a selection left elsewhere in the
    /// app, or in an app other than the one under the pointer, yields nil so the pointer is read
    /// instead. The selected text itself is returned exactly as the app reports it.
    @MainActor
    func readingSelection(at cocoaPoint: CGPoint) async -> String? {
        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              processID != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        let axPoint = AXCoordinateSpace(primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0)
            .axPoint(fromCocoa: cocoaPoint)
        let text = try? await Task.withTimeout(seconds: 0.35) {
            try await self.getSelectedText(strategy: .accessibility)
        }
        guard !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let relation = try? await Task.withTimeout(seconds: 0.35) {
            await Task.detached(priority: .userInitiated) {
                SelectionGeometry.relation(to: axPoint, processIdentifier: processID)
            }.value
        }
        guard !Task.isCancelled else {
            return nil
        }
        if relation == .elsewhere {
            logInfo("Reading assist: selection ignored, the pointer is not on it")
            return nil
        }
        return text
    }

    @objc
    public func getSelectedText(strategy: TextStrategy) async throws -> String? {
        try await selectedTextManager.getSelectedText(strategy: strategy)
    }
}
