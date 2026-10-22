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

/// Shows a dictionary card for a foreign word under the pointer after a standalone modifier tap.
///
/// The reading-assist trigger coordinator requests a lookup without changing the selection.
/// The card loads dictionary senses and the meaning in context side by side,
/// and fades out when the mouse leaves the word, or on a click, key press, scroll, or app switch.
@MainActor
final class WordLookupManager {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = WordLookupManager()

    /// Whether text is a supported dictionary word.
    ///
    /// Only single words in a Latin script qualify; phrases and other scripts are ignored.
    nonisolated static func accepts(_ text: String) -> Bool {
        guard Defaults[.enableWordLookup], text.count <= maximumWordLength else {
            return false
        }
        return text.range(of: #"^\p{Latin}[\p{Latin}'’-]*$"#, options: .regularExpression) != nil
    }

    /// Reads the word at `mouseLocation` (Cocoa screen coordinates), without selecting or copying it.
    func lookUp(at mouseLocation: CGPoint) {
        dismiss()
        guard Defaults[.enableWordLookup] else {
            return
        }
        let generation = lookupGeneration
        wordFrame = CGRect(x: mouseLocation.x - 20, y: mouseLocation.y - 9, width: 40, height: 18)
        startDismissMonitoring()

        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        let locator = WordLocator(
            coordinateSpace: AXCoordinateSpace(primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0),
            maximumParagraphHeight: (screen?.frame.height ?? 0) * 0.75
        )
        locatorQueue.async { [weak self] in
            let located = locator.locate(at: mouseLocation)
            DispatchQueue.main.async {
                guard let self, self.lookupGeneration == generation else {
                    return
                }
                guard let located, Self.accepts(located.word) else {
                    logInfo("Reading assist: no supported word at pointer")
                    self.dismiss()
                    return
                }
                logInfo("Reading assist: presenting word card, context available: \(located.sentence != nil)")
                let model = WordLookupModel(word: located.word)
                self.presentedModel = model
                self.present(model, located: located)
            }
        }
    }

    /// Cancels both pending geometry lookup and visible dictionary requests.
    func dismiss() {
        lookupGeneration += 1
        loadingTasks.forEach { $0.cancel() }
        loadingTasks.removeAll()
        stopDismissMonitoring()
        guard presentedModel != nil else {
            return
        }
        presentedModel = nil
        WordLookupPanel.shared.dismiss()
    }

    // MARK: Private

    private nonisolated static let maximumWordLength = 40
    /// Margin around the word and its card that still counts as reading them.
    private static let readingMargin: CGFloat = 30

    private let eventMonitor = EventMonitorEngine()
    private let locatorQueue = DispatchQueue(label: "com.izual.Easydict.WordLookup", qos: .userInitiated)

    private var presentedModel: WordLookupModel?
    private var lookupGeneration = 0
    private var wordFrame = CGRect.zero
    private var loadingTasks: [Task<(), Never>] = []
    private var activationObservation: NSObjectProtocol?

    private func present(_ model: WordLookupModel, located: LocatedWord) {
        guard presentedModel === model else {
            return
        }

        wordFrame = located.frame
        model.hasContext = located.sentence != nil
        WordLookupPanel.shared.present(model, wordFrame: wordFrame)

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
