//
//  SystemUtility+Selection.swift
//  Easydict
//
//  Created by tisfeng on 2025/9/9.
//  Copyright © 2025 izual. All rights reserved.
//

import AppKit
import SelectedTextKit

// MARK: - ReadingSelection

/// A selection a reading gesture has already translated, remembered to recognize it when it lingers.
struct ReadingSelection: Equatable, Sendable {
    let processIdentifier: pid_t
    let text: String
}

// MARK: - SystemUtility + Selection

extension SystemUtility {
    /// Probes a selection without copy shortcuts or pasteboard writes during a reading gesture.
    /// Returns promptly for an empty selection; the deadline only bounds an unresponsive AX client.
    ///
    /// An explicit selection wins wherever the pointer is, so a drag or keyboard selection followed by
    /// pointer movement is still translated exactly. Only the selection `alreadyTranslated` names, still
    /// highlighted after an earlier gesture, gives way to the pointer when the pointer is clearly not on it.
    @MainActor
    func readingSelection(at cocoaPoint: CGPoint, alreadyTranslated: ReadingSelection?) async -> String? {
        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              processID != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        let text = try? await Task.withTimeout(seconds: 0.35) {
            try await self.getSelectedText(strategy: .accessibility)
        }
        guard !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard alreadyTranslated == ReadingSelection(processIdentifier: processID, text: text) else {
            return text
        }
        // The same selection as last time: geometry decides, and an unanswered probe keeps the selection.
        let axPoint = AXCoordinateSpace(primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0)
            .axPoint(fromCocoa: cocoaPoint)
        let relation = try? await Task.withTimeout(seconds: 0.2) {
            await Task.detached(priority: .userInitiated) {
                SelectionGeometry.relation(to: axPoint, processIdentifier: processID)
            }.value
        }
        guard !Task.isCancelled else {
            return nil
        }
        if relation == .elsewhere {
            logInfo("Reading assist: translated selection left in place, reading the pointer instead")
            return nil
        }
        return text
    }

    @objc
    public func getSelectedText(strategy: TextStrategy) async throws -> String? {
        try await selectedTextManager.getSelectedText(strategy: strategy)
    }
}
