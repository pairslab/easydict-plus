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
    @MainActor
    func readingSelection() async -> String? {
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
        return text
    }

    @objc
    public func getSelectedText(strategy: TextStrategy) async throws -> String? {
        try await selectedTextManager.getSelectedText(strategy: strategy)
    }
}
