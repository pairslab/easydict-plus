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
    /// Web documents such as Chromium's PDF viewer keep their selection as a text-marker range that the
    /// focused element does not report, so that range is read when the usual read finds nothing.
    @MainActor
    func readingSelection(at cocoaPoint: CGPoint) async -> String? {
        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              processID != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        var text = try? await Task.withTimeout(seconds: 0.35) {
            try await self.getSelectedText(strategy: .accessibility)
        }
        if text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true, !Task.isCancelled {
            let axPoint = AXCoordinateSpace(primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0)
                .axPoint(fromCocoa: cocoaPoint)
            text = try? await Task.withTimeout(seconds: 0.25) {
                await Task.detached(priority: .userInitiated) {
                    WebSelection.text(at: axPoint, processIdentifier: processID)
                }.value
            }
            if let text {
                logInfo("Reading assist: selection read from the web document (\(text.count) characters)")
            }
        }
        guard !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    @objc
    public func getSelectedText(strategy: TextStrategy) async throws -> String? {
        try await selectedTextManager.getSelectedText(strategy: strategy)
    }
}
