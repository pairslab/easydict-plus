//
//  HoverTranslationManager.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Combine
import Defaults

// MARK: - HoverTranslationManager

/// Translates the paragraph under the mouse while the trigger modifier is held.
///
/// Holding the modifier alone for a moment starts tracking: the paragraph under the mouse is
/// outlined and the outline follows the pointer between paragraphs. Resting on a paragraph,
/// or releasing the modifier, translates it into a card right below. The card stays after the
/// release and fades out when the mouse leaves it, the page scrolls, a click or key press
/// happens, or another app becomes active.
@objc(EZHoverTranslationManager)
@MainActor
final class HoverTranslationManager: NSObject {
    // MARK: Internal

    @objc static let shared = HoverTranslationManager()

    /// Follows the trigger setting; event monitoring runs only while a trigger is chosen.
    @objc
    func start() {
        guard triggerObservation == nil else {
            return
        }
        triggerObservation = Defaults.publisher(.hoverTranslationTrigger, options: [.initial])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.apply(change.newValue)
            }
    }

    // MARK: Private

    private enum State {
        case idle
        /// The modifier is down; waiting to be sure it is not part of a shortcut.
        case arming
        /// The modifier is held and the paragraph under the mouse is outlined.
        case tracking
    }

    private enum Timing {
        /// How long the modifier must be held alone before tracking starts.
        static let arming: TimeInterval = 0.25
        /// How long the mouse rests on a paragraph before it is translated.
        static let dwell: TimeInterval = 0.35
    }

    private static let cacheLimit = 64
    /// Margin around the paragraph and its card that still counts as reading them.
    private static let readingMargin: CGFloat = 28
    /// Share of the screen height above which a "paragraph" is treated as a whole page.
    private static let maximumParagraphHeightRatio: CGFloat = 0.75

    private let eventMonitor = EventMonitorEngine()
    private let locatorQueue = DispatchQueue(label: "com.izual.Easydict.HoverTranslation", qos: .userInitiated)

    private var triggerObservation: AnyCancellable?
    private var activationObservation: NSObjectProtocol?
    private var modifierFlag: NSEvent.ModifierFlags?
    private var state = State.idle

    private var armingTask: Task<(), Never>?
    private var dwellTask: Task<(), Never>?
    private var translationTask: Task<(), Never>?

    private var isLocating = false
    private var pendingLocation: CGPoint?
    private var highlightedParagraph: HoveredParagraph?
    private var cardParagraph: HoveredParagraph?
    private var cardModel: TranslationPreviewModel?

    private var translationCache: [String: String] = [:]
    private var cacheOrder: [String] = []

    // MARK: Setup

    private func apply(_ trigger: HoverTranslationTrigger) {
        reset()
        eventMonitor.stop()
        if let activationObservation {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObservation)
            self.activationObservation = nil
        }

        modifierFlag = trigger.modifierFlag
        guard modifierFlag != nil else {
            logInfo("Hover translation is off")
            return
        }

        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .mouseMoved, .leftMouseDragged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
        ]
        eventMonitor.monitor(type: .global, mask: mask) { [weak self] event in
            self?.handle(event)
        }
        activationObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reset()
            }
        }
        logInfo("Hover translation is on, trigger: \(trigger.rawValue)")
    }

    /// Returns to idle, hiding the outline and the card.
    private func reset() {
        cancelArming()
        if state == .tracking {
            endTracking(translatesHighlighted: false)
        }
        state = .idle
        dismissCard()
    }

    // MARK: Events

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            handleModifiersChanged(event.modifierFlags)
        case .keyDown:
            // A key press means typing or a shortcut, never a hover lookup.
            reset()
        case .leftMouseDragged, .mouseMoved:
            handleMouseMoved()
        case .scrollWheel:
            handleScroll()
        default:
            reset()
        }
    }

    private func handleModifiersChanged(_ flags: NSEvent.ModifierFlags) {
        guard let modifierFlag else {
            return
        }

        let heldModifiers = flags.intersection([.command, .option, .control, .shift])
        if heldModifiers == modifierFlag {
            guard state == .idle else {
                return
            }
            state = .arming
            armingTask = Task { [weak self] in
                await Task.sleep(seconds: Timing.arming)
                guard let self, !Task.isCancelled, state == .arming else {
                    return
                }
                beginTracking()
            }
            return
        }

        // Released, or another modifier joined it for a shortcut.
        let wasTracking = state == .tracking
        cancelArming()
        if wasTracking {
            endTracking(translatesHighlighted: heldModifiers.isEmpty)
        }
    }

    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation
        switch state {
        case .tracking:
            locateParagraph(at: location)
        case .arming, .idle:
            if cardParagraph != nil, !isReading(at: location) {
                dismissCard()
            }
        }
    }

    private func handleScroll() {
        // Scrolling moves the text away from the outline and the card.
        dismissCard()
        guard state == .tracking else {
            return
        }
        highlightedParagraph = nil
        ParagraphHighlightPanel.shared.hide()
        locateParagraph(at: NSEvent.mouseLocation)
    }

    // MARK: Tracking

    private func cancelArming() {
        armingTask?.cancel()
        armingTask = nil
        if state == .arming {
            state = .idle
        }
    }

    private func beginTracking() {
        state = .tracking
        locateParagraph(at: NSEvent.mouseLocation)
    }

    /// Stops following the mouse; a release translates the outlined paragraph if it has no card yet.
    private func endTracking(translatesHighlighted: Bool) {
        state = .idle
        dwellTask?.cancel()
        pendingLocation = nil
        if translatesHighlighted, let highlightedParagraph, highlightedParagraph != cardParagraph {
            translate(highlightedParagraph)
        }
        highlightedParagraph = nil
        ParagraphHighlightPanel.shared.hide()
    }

    /// Looks up the paragraph off the main thread; while a lookup runs, only the latest point is kept.
    private func locateParagraph(at location: CGPoint) {
        guard !isLocating else {
            pendingLocation = location
            return
        }
        isLocating = true

        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        let locator = ParagraphLocator(
            primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0,
            maximumHeight: (screen?.frame.height ?? 0) * Self.maximumParagraphHeightRatio
        )
        locatorQueue.async { [weak self] in
            let paragraph = locator.paragraph(at: location)
            DispatchQueue.main.async {
                self?.didLocate(paragraph)
            }
        }
    }

    private func didLocate(_ paragraph: HoveredParagraph?) {
        isLocating = false
        if let pendingLocation {
            // The mouse moved on meanwhile; skip this stale result.
            self.pendingLocation = nil
            locateParagraph(at: pendingLocation)
            return
        }
        guard state == .tracking, paragraph != highlightedParagraph else {
            return
        }

        highlightedParagraph = paragraph
        dwellTask?.cancel()
        guard let paragraph else {
            ParagraphHighlightPanel.shared.hide()
            return
        }

        ParagraphHighlightPanel.shared.show(around: paragraph.frame)
        guard paragraph != cardParagraph else {
            return
        }
        dwellTask = Task { [weak self] in
            await Task.sleep(seconds: Timing.dwell)
            guard let self, !Task.isCancelled, state == .tracking, highlightedParagraph == paragraph else {
                return
            }
            translate(paragraph)
        }
    }

    // MARK: Card

    private func translate(_ paragraph: HoveredParagraph) {
        translationTask?.cancel()
        cardParagraph = paragraph

        let service = ActionManager.shared.translateService
        let model = TranslationPreviewModel(
            serviceName: service.name(),
            serviceIconName: service.iconName(),
            activity: .translating,
            layout: .reading(width: paragraph.frame.width + 2 * TranslationPreviewView.contentInset)
        )
        let cacheKey = "\(service.serviceTypeWithUniqueIdentifier())\n\(paragraph.text)"
        if let cachedTranslation = translationCache[cacheKey] {
            model.text = cachedTranslation
            model.phase = .finished
            present(model, below: paragraph)
            return
        }

        translationTask = Task { [weak self] in
            do {
                // Text already in the user's first language needs no card at all.
                guard let query = try await ActionManager.shared.readingQuery(for: paragraph.text) else {
                    self?.forgetCard(for: paragraph)
                    return
                }
                guard let self, !Task.isCancelled, cardParagraph == paragraph else {
                    return
                }

                present(model, below: paragraph)
                let translation = try await ActionManager.shared.translateForReading(query, service: service) { text in
                    model.text = text
                }
                try Task.checkCancellation()
                model.text = translation
                model.phase = .finished
                store(translation, forKey: cacheKey)
            } catch is CancellationError {
                return
            } catch {
                logError("Hover translation failed: \(error)")
                model.phase = .failed(ActionManager.shared.failureMessage(for: error))
            }
        }
    }

    private func present(_ model: TranslationPreviewModel, below paragraph: HoveredParagraph) {
        cardModel = model
        TranslationPreviewPanel.shared.present(model, anchorRect: paragraph.frame, alignsTextWithAnchor: true)
    }

    private func forgetCard(for paragraph: HoveredParagraph) {
        if cardParagraph == paragraph {
            cardParagraph = nil
        }
    }

    private func dismissCard() {
        translationTask?.cancel()
        translationTask = nil
        cardParagraph = nil
        if let cardModel, TranslationPreviewPanel.shared.isPresenting(cardModel) {
            TranslationPreviewPanel.shared.dismiss()
        }
        cardModel = nil
    }

    /// Whether the mouse is still over the translated paragraph or its card.
    private func isReading(at location: CGPoint) -> Bool {
        guard let cardParagraph else {
            return false
        }
        var area = cardParagraph.frame
        if let cardFrame = TranslationPreviewPanel.shared.cardFrame {
            area = area.union(cardFrame)
        }
        return area.insetBy(dx: -Self.readingMargin, dy: -Self.readingMargin).contains(location)
    }

    private func store(_ translation: String, forKey key: String) {
        if translationCache.updateValue(translation, forKey: key) == nil {
            cacheOrder.append(key)
        }
        if cacheOrder.count > Self.cacheLimit {
            translationCache[cacheOrder.removeFirst()] = nil
        }
    }
}
