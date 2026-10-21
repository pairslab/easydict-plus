//
//  WordLookupManager.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Defaults

// MARK: - WordLookupManager

/// Shows a dictionary card for a foreign word the user double-clicks in read-only text.
///
/// `EventMonitor` hands over double-clicked selections that `accepts(_:)` allows, in place of
/// the query icon. The card loads dictionary senses and the meaning in context side by side,
/// and fades out when the mouse leaves the word, or on a click, key press, scroll, or app switch.
@MainActor
final class WordLookupManager {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = WordLookupManager()

    /// Whether a double-clicked selection should open the dictionary card instead of the query icon.
    ///
    /// Only single words in a Latin script qualify, so text in the user's own language, phrases,
    /// and code keep the regular behavior.
    nonisolated static func accepts(_ text: String) -> Bool {
        guard Defaults[.enableWordLookup], text.count <= maximumWordLength else {
            return false
        }
        return text.range(of: #"^\p{Latin}[\p{Latin}'’-]*$"#, options: .regularExpression) != nil
    }

    /// Looks up `word`, which was just double-clicked at `mouseLocation` (Cocoa screen coordinates).
    func lookUp(_ word: String, near mouseLocation: CGPoint) {
        dismiss()
        let model = WordLookupModel(word: word)
        presentedModel = model

        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        let locator = WordLocator(
            coordinateSpace: AXCoordinateSpace(primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0),
            maximumParagraphHeight: (screen?.frame.height ?? 0) * 0.75
        )
        locatorQueue.async { [weak self] in
            let located = locator.locate(word, near: mouseLocation)
            DispatchQueue.main.async {
                self?.present(model, located: located, mouseLocation: mouseLocation)
            }
        }
    }

    // MARK: Private

    private nonisolated static let maximumWordLength = 40
    /// Margin around the word and its card that still counts as reading them.
    private static let readingMargin: CGFloat = 30

    private let eventMonitor = EventMonitorEngine()
    private let locatorQueue = DispatchQueue(label: "com.izual.Easydict.WordLookup", qos: .userInitiated)

    private var presentedModel: WordLookupModel?
    private var wordFrame = CGRect.zero
    private var loadingTasks: [Task<(), Never>] = []
    private var activationObservation: NSObjectProtocol?

    private func present(_ model: WordLookupModel, located: LocatedWord, mouseLocation: CGPoint) {
        guard presentedModel === model else {
            return
        }

        // Without selection bounds, point at a word-sized area under the mouse.
        wordFrame = located.frame ?? CGRect(x: mouseLocation.x - 20, y: mouseLocation.y - 9, width: 40, height: 18)
        model.hasContext = located.sentence != nil
        WordLookupPanel.shared.present(model, wordFrame: wordFrame)
        startDismissMonitoring()

        loadingTasks.append(Task {
            let entry = await WordLookupLoader.dictionaryEntry(for: model.word)
            guard !Task.isCancelled else {
                return
            }
            model.phonetics = entry.phonetics
            model.senses = entry.senses
            model.isLoadingDictionary = false
        })

        guard let sentence = located.sentence else {
            return
        }
        loadingTasks.append(Task {
            do {
                model.contextualMeaning = try await WordLookupLoader.contextualMeaning(of: model.word, in: sentence) {
                    model.contextualMeaning = $0
                }
            } catch is CancellationError {
                return
            } catch {
                logError("Contextual meaning failed: \(error)")
            }
            model.isLoadingContext = false
        })
    }

    private func dismiss() {
        loadingTasks.forEach { $0.cancel() }
        loadingTasks.removeAll()
        stopDismissMonitoring()
        guard presentedModel != nil else {
            return
        }
        presentedModel = nil
        WordLookupPanel.shared.dismiss()
    }

    // MARK: Dismissal

    private func startDismissMonitoring() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel,
        ]
        eventMonitor.monitor(type: .global, mask: mask) { [weak self] event in
            guard let self else {
                return
            }
            if event.type != .mouseMoved || !isReading(at: NSEvent.mouseLocation) {
                dismiss()
            }
        }
        activationObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func stopDismissMonitoring() {
        eventMonitor.stop()
        if let activationObservation {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObservation)
            self.activationObservation = nil
        }
    }

    /// Whether the mouse is still over the word or its card.
    private func isReading(at location: CGPoint) -> Bool {
        var area = wordFrame
        if let cardFrame = WordLookupPanel.shared.cardFrame {
            area = area.union(cardFrame)
        }
        return area.insetBy(dx: -Self.readingMargin, dy: -Self.readingMargin).contains(location)
    }
}
