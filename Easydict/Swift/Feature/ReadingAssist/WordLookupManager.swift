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
        startDismissMonitoring()

        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        let locator = WordLocator(
            coordinateSpace: AXCoordinateSpace(primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0),
            maximumParagraphHeight: (screen?.frame.height ?? 0) * 0.75
        )
        locate(at: mouseLocation, using: locator, generation: generation, deadline: .now() + Self.geometryWait)
    }

    /// Cancels both pending geometry lookup and visible dictionary requests.
    func dismiss() {
        lookupGeneration += 1
        contextWorkItem?.cancel()
        contextWorkItem = nil
        loadingTasks.forEach { $0.cancel() }
        loadingTasks.removeAll()
        audioPlayer?.stop()
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
    /// Longest wait for an app building text geometry; see `WebTextGeometry`.
    private static let geometryWait: TimeInterval = 3.5
    private static let geometryRetryInterval: TimeInterval = 0.25

    private let eventMonitor = EventMonitorEngine()
    /// Created on the first pronunciation, so lookups without audio do not set up a player.
    private var audioPlayer: EZAudioPlayer?
    private let locatorQueue = DispatchQueue(label: "com.izual.Easydict.WordLookup", qos: .userInitiated)
    private let contextQueue = DispatchQueue(label: "com.izual.Easydict.WordContext", qos: .userInitiated)

    private var presentedModel: WordLookupModel?
    private var lookupGeneration = 0
    private var wordFrame = CGRect.zero
    private var loadingTasks: [Task<(), Never>] = []
    private var contextWorkItem: DispatchWorkItem?
    private var activationObservation: NSObjectProtocol?

    /// The phonetic in the accent chosen in Settings, otherwise the first one.
    private static func preferredPhonetic(in phonetics: [WordLookupModel.Phonetic]) -> WordLookupModel.Phonetic? {
        let accent = Defaults[.pronunciation] == .uk ? "uk" : "us"
        return phonetics.first { $0.source?.accent == accent } ?? phonetics.first
    }

    private func locate(
        at mouseLocation: CGPoint,
        using locator: WordLocator,
        generation: Int,
        deadline: DispatchTime
    ) {
        locatorQueue.async { [weak self] in
            let location = locator.locate(at: mouseLocation)
            DispatchQueue.main.async {
                guard let self, self.lookupGeneration == generation else {
                    return
                }
                switch location {
                case let .word(located):
                    self.show(located, at: mouseLocation, using: locator)
                case .loadingGeometry where DispatchTime.now() < deadline && self.isStill(at: mouseLocation):
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.geometryRetryInterval) { [weak self] in
                        guard let self, lookupGeneration == generation else {
                            return
                        }
                        locate(at: mouseLocation, using: locator, generation: generation, deadline: deadline)
                    }
                case .loadingGeometry:
                    let reason = DispatchTime.now() < deadline ? "pointer moved" : "deadline passed"
                    logInfo("Reading assist: stopped waiting for web text geometry, \(reason)")
                    self.dismiss()
                case .unavailable:
                    logInfo("Reading assist: no supported word at pointer")
                    self.dismiss()
                }
            }
        }
    }

    private func show(_ located: LocatedWord, at mouseLocation: CGPoint, using locator: WordLocator) {
        guard Self.accepts(located.word) else {
            logInfo("Reading assist: no supported word at pointer")
            dismiss()
            return
        }
        guard located.frame.insetBy(dx: -Self.readingMargin, dy: -Self.readingMargin)
            .contains(NSEvent.mouseLocation) else {
            logInfo("Reading assist: pointer left the located word before presentation")
            dismiss()
            return
        }
        logInfo("Reading assist: presenting word card before context lookup")
        let model = WordLookupModel(word: located.word)
        presentedModel = model
        present(model, located: located)
        loadContext(for: model, located: located, at: mouseLocation, using: locator)
    }

    /// Whether the pointer is still where the lookup started, so a retry reads the same word.
    private func isStill(at mouseLocation: CGPoint) -> Bool {
        CGRect(origin: mouseLocation, size: .zero)
            .insetBy(dx: -Self.readingMargin, dy: -Self.readingMargin)
            .contains(NSEvent.mouseLocation)
    }

    private func present(_ model: WordLookupModel, located: LocatedWord) {
        guard presentedModel === model else {
            return
        }

        wordFrame = located.frame
        model.pronounce = { [weak self, weak model] phonetic in
            guard let self, let model, presentedModel === model else {
                return
            }
            pronounce(model.word, phonetic: phonetic)
        }
        WordLookupPanel.shared.present(model, wordFrame: wordFrame)

        loadingTasks.append(Task {
            let entry = await WordLookupLoader.dictionaryEntry(for: model.word)
            guard !Task.isCancelled else {
                return
            }
            model.phonetics = entry.phonetics
            model.senses = entry.senses
            model.isLoadingDictionary = false
            if Defaults[.autoPlayAudio] {
                pronounce(model.word, phonetic: Self.preferredPhonetic(in: entry.phonetics))
            }
        })
    }

    /// Plays the dictionary's recording for `phonetic`, or speaks the word with the default voice.
    private func pronounce(_ word: String, phonetic: WordLookupModel.Phonetic?) {
        let player = audioPlayer ?? EZAudioPlayer()
        audioPlayer = player
        player.stop()
        guard let source = phonetic?.source else {
            player.playTextAudio(word, textLanguage: .english)
            return
        }
        if source.word.isEmpty {
            source.word = word
        }
        if source.language == .auto {
            source.language = .english
        }
        player.play(source, designatedService: nil)
    }

    private func loadContext(
        for model: WordLookupModel,
        located: LocatedWord,
        at point: CGPoint,
        using locator: WordLocator
    ) {
        let workItem = DispatchWorkItem { [weak self] in
            let sentence = locator.context(for: located, at: point)
            DispatchQueue.main.async {
                guard let self, self.presentedModel === model else {
                    return
                }
                self.contextWorkItem = nil
                logInfo("Reading assist: word context available: \(sentence != nil)")
                guard let sentence else {
                    model.hasContext = false
                    model.isLoadingContext = false
                    return
                }
                self.loadContextualMeaning(for: model, sentence: sentence)
            }
        }
        contextWorkItem = workItem
        contextQueue.async(execute: workItem)
    }

    private func loadContextualMeaning(for model: WordLookupModel, sentence: String) {
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
        let generation = lookupGeneration
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel,
        ]
        eventMonitor.monitor(type: .global, mask: mask) { [weak self] event in
            guard let self, lookupGeneration == generation else {
                return
            }
            // While locating, validate movement against the real word bounds when they arrive.
            if event.type == .mouseMoved, presentedModel == nil {
                return
            }
            if event.type == .mouseMoved {
                WordLookupPanel.shared.updatePointerInteraction(at: NSEvent.mouseLocation)
            }
            if event.type != .mouseMoved || !isReading(at: NSEvent.mouseLocation) {
                logInfo("Reading assist: word lookup dismissed by event \(event.type.rawValue)")
                dismiss()
            }
        }
        activationObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lookupGeneration == generation else {
                    return
                }
                logInfo("Reading assist: word lookup dismissed by app activation")
                self.dismiss()
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
