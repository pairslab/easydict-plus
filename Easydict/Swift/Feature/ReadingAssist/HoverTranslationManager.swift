//
//  HoverTranslationManager.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Carbon.HIToolbox
import Combine
import Defaults

// MARK: - HoverTranslationManager

/// Translates the paragraph under the mouse while the trigger modifier is held.
///
/// Holding the modifier alone starts tracking immediately, unless it also handles word taps.
/// That shared key must remain held before paragraph tracking starts. The paragraph is
/// outlined and the outline follows the pointer between paragraphs. Resting on a paragraph,
/// or releasing the modifier, translates it into a card right below. The card stays after the
/// release and fades out when the mouse leaves it, the page scrolls, a click or key press
/// happens, or another app becomes active.
@objc(EZHoverTranslationManager)
@MainActor
final class HoverTranslationManager: NSObject {
    // MARK: Internal

    @objc static let shared = HoverTranslationManager()

    /// Coordinates word taps and paragraph holds without installing competing event monitors.
    @objc
    func start() {
        guard triggerObservation == nil else {
            return
        }
        triggerObservation = Defaults.publisher(keys: .hoverTranslationTrigger, .enableWordLookup, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.apply(Defaults[.hoverTranslationTrigger], wordLookupEnabled: Defaults[.enableWordLookup])
            }
        // Keys still using their default value need not emit an initial KVO event.
        apply(Defaults[.hoverTranslationTrigger], wordLookupEnabled: Defaults[.enableWordLookup])
    }

    // MARK: Private

    private enum State {
        case idle
        /// The modifier is held and the paragraph under the mouse is outlined.
        case tracking
    }

    /// Show the outline immediately, but let shortcuts and movement cancel before a network request.
    private static let translationDelay: TimeInterval = 0.15
    /// Give a standalone tap priority before committing the shared key to paragraph mode.
    private static let paragraphHoldDelay: TimeInterval = 0.5
    private static let triggerModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    /// A key pressed this long after the trigger makes the hold a shortcut, not a tap.
    private static let chordKeyMargin: TimeInterval = 0.02
    /// Chat messages can change while hovered, so only reuse their geometry briefly.
    private static let paragraphReuseInterval: TimeInterval = 0.35
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
    private var wordLookupEnabled = false
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var wordTapStartedAt: TimeInterval?
    private var selectionProbe: Task<String?, Never>?
    /// The selection the last gesture translated, so it can be recognized if it is still highlighted.
    private var lastTranslatedSelection: ReadingSelection?
    private var selectionQueryTask: Task<(), Never>?
    private var state = State.idle

    private var paragraphHoldTask: Task<(), Never>?
    private var dwellTask: Task<(), Never>?
    private var translationTask: Task<(), Never>?

    private var isLocating = false
    private var lookupGeneration = 0
    private var pendingLocation: CGPoint?
    private var highlightedParagraph: HoveredParagraph?
    private var paragraphLocatedAt: TimeInterval = 0
    private var cardParagraph: HoveredParagraph?
    private var cardModel: TranslationPreviewModel?

    private var translationCache: [String: String] = [:]
    private var cacheOrder: [String] = []

    /// The trigger modifier toggled by a modifier key, for the left and right keys alike.
    private static func triggerModifier(forKeyCode keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch Int(keyCode) {
        case kVK_Option, kVK_RightOption:
            .option
        case kVK_Control, kVK_RightControl:
            .control
        case kVK_RightShift, kVK_Shift:
            .shift
        case kVK_Command, kVK_RightCommand:
            .command
        default:
            nil
        }
    }

    /// Whether a key went down at the hardware level after the trigger press at `uptime`.
    ///
    /// Shortcuts that hold the trigger, such as Easydict's ⌥A or another app's ⌥Space, are consumed
    /// before this global monitor sees their key, so without this check the hold would pass for a tap.
    /// The margin keeps the trigger press itself from ever counting, whatever the event source records.
    private static func keyWentDown(since uptime: TimeInterval) -> Bool {
        let secondsSinceKeyDown = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        return ProcessInfo.processInfo.systemUptime - secondsSinceKeyDown > uptime + chordKeyMargin
    }

    // MARK: Setup

    private func apply(_ trigger: HoverTranslationTrigger, wordLookupEnabled: Bool) {
        reset()
        WordLookupManager.shared.dismiss()
        eventMonitor.stop()
        if let activationObservation {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObservation)
            self.activationObservation = nil
        }

        modifierFlag = trigger.modifierFlag
        self.wordLookupEnabled = wordLookupEnabled
        heldModifiers = NSEvent.modifierFlags.intersection(Self.triggerModifiers)
        guard modifierFlag != nil || wordLookupEnabled else {
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
        cancelWordTap()
        selectionQueryTask?.cancel()
        selectionQueryTask = nil
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
            handleModifiersChanged(event)
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

    private func handleModifiersChanged(_ event: NSEvent) {
        let previousModifiers = heldModifiers
        heldModifiers = event.modifierFlags.intersection(Self.triggerModifiers)
        // The event names the key that changed, so a fresh standalone press is recognized even when an
        // earlier release went to an Easydict window, which this global monitor never sees.
        let pressedModifier = Self.triggerModifier(forKeyCode: event.keyCode)
        let isStandalonePress = pressedModifier != nil && heldModifiers == pressedModifier
        guard heldModifiers != previousModifiers || isStandalonePress else {
            return
        }

        if heldModifiers.isEmpty, let startedAt = wordTapStartedAt {
            // Detach the read before reset so the release can consume it without reading twice.
            let selection = selectionProbe
            selectionProbe = nil
            reset()
            let heldMilliseconds = Int((event.timestamp - startedAt) * 1000)
            guard !Self.keyWentDown(since: startedAt) else {
                selection?.cancel()
                logInfo("Reading assist: word tap ignored, a key was pressed during the \(heldMilliseconds) ms hold")
                return
            }
            logInfo("Reading assist: word tap released after \(heldMilliseconds) ms")
            translateSelectionOrLookUp(selection, at: NSEvent.mouseLocation)
            return
        }
        selectionQueryTask?.cancel()
        selectionQueryTask = nil
        cancelWordTap()

        // Only a fresh standalone press can start a gesture, never the tail of a shortcut.
        let startsGesture = isStandalonePress
        if startsGesture, heldModifiers == .option, wordLookupEnabled || modifierFlag == .option {
            reset()
            wordTapStartedAt = event.timestamp
            let pressLocation = NSEvent.mouseLocation
            let alreadyTranslated = lastTranslatedSelection
            selectionProbe = Task {
                await SystemUtility.shared.readingSelection(at: pressLocation, alreadyTranslated: alreadyTranslated)
            }
            WordLookupManager.shared.dismiss()
        }
        if startsGesture, let modifierFlag, heldModifiers == modifierFlag {
            WordLookupManager.shared.dismiss()
            if wordTapStartedAt != nil {
                beginParagraphTrackingAfterHold()
            } else {
                beginTracking()
            }
            return
        }

        // Released, or another modifier joined it for a shortcut.
        let wasTracking = state == .tracking
        if wasTracking {
            endTracking(translatesHighlighted: heldModifiers.isEmpty)
        }
    }

    /// Only a key that is still physically held can turn a pending word tap into paragraph mode.
    private func beginParagraphTrackingAfterHold() {
        paragraphHoldTask = Task { [weak self] in
            await Task.sleep(seconds: Self.paragraphHoldDelay)
            let selection = await self?.selectionProbe?.value
            guard let self, !Task.isCancelled, wordTapStartedAt != nil,
                  let modifierFlag, heldModifiers == modifierFlag,
                  NSEvent.modifierFlags.intersection(Self.triggerModifiers) == modifierFlag else {
                return
            }
            // A selection remains a selection even when the user holds the key longer.
            guard selection == nil, let startedAt = wordTapStartedAt,
                  !Self.keyWentDown(since: startedAt) else {
                return
            }
            wordTapStartedAt = nil
            paragraphHoldTask = nil
            logInfo("Reading assist: paragraph hold confirmed")
            beginTracking()
        }
    }

    private func cancelWordTap() {
        wordTapStartedAt = nil
        selectionProbe?.cancel()
        selectionProbe = nil
        paragraphHoldTask?.cancel()
        paragraphHoldTask = nil
    }

    /// Explicit selections win over pointer lookup, with the same cancellation rules as the gesture.
    private func translateSelectionOrLookUp(_ selection: Task<String?, Never>?, at location: CGPoint) {
        let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        selectionQueryTask = Task {
            let text = await selection?.value
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else {
                return
            }
            if let text {
                guard !Screenshot.shared.isTakingScreenshot else {
                    return
                }
                logInfo("Reading assist: translating explicit selection (\(text.count) characters)")
                if let processID {
                    lastTranslatedSelection = ReadingSelection(processIdentifier: processID, text: text)
                }
                // Selection APIs do not always expose bounds; anchor the shared reading card at the gesture.
                let source = HoveredParagraph(
                    text: text,
                    frame: CGRect(x: location.x, y: location.y - 10, width: 1, height: 20),
                    processIdentifier: processID ?? 0
                )
                translate(source, isSelection: true)
            } else {
                let current = NSEvent.mouseLocation
                if hypot(current.x - location.x, current.y - location.y) <= 4 {
                    WordLookupManager.shared.lookUp(at: location)
                }
            }
        }
    }

    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation
        switch state {
        case .tracking:
            locateParagraph(at: location)
        case .idle:
            if cardParagraph != nil, !isReading(at: location) {
                dismissCard()
            }
        }
    }

    private func handleScroll() {
        cancelWordTap()
        selectionQueryTask?.cancel()
        selectionQueryTask = nil
        // Scrolling moves the text away from the outline and the card.
        dismissCard()
        guard state == .tracking else {
            return
        }
        lookupGeneration += 1
        pendingLocation = nil
        highlightedParagraph = nil
        ParagraphHighlightPanel.shared.hide()
        locateParagraph(at: NSEvent.mouseLocation)
    }

    // MARK: Tracking

    private func beginTracking() {
        lookupGeneration += 1
        state = .tracking
        locateParagraph(at: NSEvent.mouseLocation)
    }

    /// Stops following the mouse; a release translates the outlined paragraph if it has no card yet.
    private func endTracking(translatesHighlighted: Bool) {
        state = .idle
        lookupGeneration += 1
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
        // Pointer motion within the same paragraph needs no additional cross-process AX calls.
        if let highlightedParagraph, highlightedParagraph.frame.contains(location),
           ProcessInfo.processInfo.systemUptime - paragraphLocatedAt < Self.paragraphReuseInterval {
            if isLocating {
                pendingLocation = location
            }
            return
        }
        guard !isLocating else {
            pendingLocation = location
            return
        }
        isLocating = true
        let generation = lookupGeneration

        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        let locator = ParagraphLocator(
            coordinateSpace: AXCoordinateSpace(primaryScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0),
            maximumHeight: (screen?.frame.height ?? 0) * Self.maximumParagraphHeightRatio
        )
        locatorQueue.async { [weak self] in
            let paragraph = locator.paragraph(at: location)
            DispatchQueue.main.async {
                self?.didLocate(paragraph, generation: generation)
            }
        }
    }

    private func didLocate(_ paragraph: HoveredParagraph?, generation: Int) {
        isLocating = false
        let latestLocation = pendingLocation
        pendingLocation = nil
        guard state == .tracking else {
            return
        }
        guard generation == lookupGeneration else {
            // A scroll or a new hold invalidates geometry obtained before that transition.
            locateParagraph(at: latestLocation ?? NSEvent.mouseLocation)
            return
        }
        if let latestLocation, paragraph?.frame.contains(latestLocation) != true {
            locateParagraph(at: latestLocation)
            return
        }
        // A result remains useful when the pointer moved within the paragraph while AX was busy.
        paragraphLocatedAt = ProcessInfo.processInfo.systemUptime
        guard paragraph != highlightedParagraph else {
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
            await Task.sleep(seconds: Self.translationDelay)
            guard let self, !Task.isCancelled, state == .tracking, highlightedParagraph == paragraph else {
                return
            }
            translate(paragraph)
        }
    }

    // MARK: Card

    private func translate(_ paragraph: HoveredParagraph, isSelection: Bool = false) {
        translationTask?.cancel()
        cardParagraph = paragraph

        let service = ActionManager.shared.translateService
        let screen = NSScreen.screens.first { $0.frame.intersects(paragraph.frame) } ?? NSScreen.main
        let model = TranslationPreviewModel(
            service: service,
            activity: .translating,
            layout: isSelection
                ? .selection(text: paragraph.text, screenSize: screen?.visibleFrame.size ?? CGSize(width: 800, height: 600))
                : .reading(width: paragraph.frame.width + 2 * TranslationPreviewView.contentInset)
        )
        let cacheKey = "\(service.serviceTypeWithUniqueIdentifier())\n\(paragraph.text)"
        if !isSelection, let cachedTranslation = translationCache[cacheKey] {
            model.text = cachedTranslation
            model.phase = .finished
            present(model, below: paragraph)
            return
        }
        if isSelection {
            // Explicit requests show progress and detection failures, including text in the first language.
            present(model, below: paragraph)
        }

        translationTask = Task { [weak self] in
            do {
                guard let query = try await ActionManager.shared.readingQuery(
                    for: paragraph.text, isSelection: isSelection
                ) else {
                    self?.forgetCard(for: paragraph)
                    return
                }
                guard let self, !Task.isCancelled, cardParagraph == paragraph else {
                    return
                }

                if !isSelection {
                    present(model, below: paragraph)
                }
                let translation = try await ActionManager.shared.translateForReading(query, service: service) { text in
                    model.text = text
                }
                try Task.checkCancellation()
                guard !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw QueryError(type: .noResult)
                }
                model.text = translation
                model.phase = .finished
                if isSelection {
                    if Defaults[.autoCopyFirstTranslatedText] {
                        translation.copyToPasteboard()
                    }
                } else {
                    store(translation, forKey: cacheKey)
                }
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
