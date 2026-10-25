//
//  WordLookupPanel.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Combine
import SwiftUI

// MARK: - WordLookupPanel

/// Hosts `WordLookupCardView` in a non-activating panel centered under the looked-up word, with
/// its arrow on the word; flips above the word when there is no room below.
///
/// The panel takes clicks only while the pointer is on the card itself, so its buttons work without
/// activating Easydict, and the transparent shadow margin never blocks clicks on the text around it.
@MainActor
final class WordLookupPanel {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = WordLookupPanel()

    /// Screen frame of the visible card, excluding its transparent shadow margin.
    var cardFrame: CGRect? {
        guard panel.isVisible, presentedModel != nil else {
            return nil
        }
        let inset = WordLookupCardView.shadowInset
        return panel.frame.insetBy(dx: inset, dy: inset)
    }

    /// Shows `model` pointing at `wordFrame` (Cocoa screen coordinates).
    func present(_ model: WordLookupModel, wordFrame: CGRect) {
        presentedModel = model
        self.wordFrame = wordFrame
        placesAboveWord = nil

        modelObservation = model.objectWillChange.sink { [weak self] _ in
            // `objectWillChange` fires before the new value is stored, so measure on the next turn.
            DispatchQueue.main.async { self?.updateLayout() }
        }
        updateLayout()
        startTrackingPointer()

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            panel.animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard let fadingModel = presentedModel else {
            return
        }
        stopTrackingPointer()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                // A word looked up during the fade owns the panel now.
                guard let self, self.presentedModel === fadingModel else {
                    return
                }
                self.panel.orderOut(nil)
                self.presentedModel = nil
                self.modelObservation = nil
            }
        }
    }

    /// Lets the card take clicks only while `location` (Cocoa screen coordinates) is on it.
    func updatePointerInteraction(at location: CGPoint) {
        let isOnCard = cardFrame?.contains(location) ?? false
        if panel.ignoresMouseEvents == isOnCard {
            panel.ignoresMouseEvents = !isOnCard
        }
    }

    // MARK: Private

    private static let fadeInDuration: TimeInterval = 0.14
    private static let fadeOutDuration: TimeInterval = 0.18
    /// Distance between the word and the arrow tip.
    private static let wordGap: CGFloat = 4

    private var presentedModel: WordLookupModel?
    private var modelObservation: AnyCancellable?
    private var wordFrame = CGRect.zero
    /// Placement is decided once per lookup so the card does not jump while it fills in.
    private var placesAboveWord: Bool?
    private var currentArrow = WordLookupCardView.Arrow()
    /// Pointer motion over the panel itself, which global monitors do not see.
    private var localPointerMonitor: Any?

    private lazy var hostingView: FirstClickHostingView<WordLookupCardView> = {
        let view = FirstClickHostingView(rootView: WordLookupCardView(model: WordLookupModel(word: "")))
        // The panel frame is managed manually: report the card's size for `fittingSize`, but do not
        // let it constrain the panel's minimum or maximum size.
        view.sizingOptions = [.intrinsicContentSize]
        return view
    }()

    private lazy var panel: NSPanel = {
        let panel = NSPanel.floatingOverlay(level: .statusBar, contentView: hostingView)
        panel.acceptsMouseMovedEvents = true
        return panel
    }()

    private func startTrackingPointer() {
        updatePointerInteraction(at: NSEvent.mouseLocation)
        guard localPointerMonitor == nil else {
            return
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updatePointerInteraction(at: NSEvent.mouseLocation)
            return event
        }
    }

    private func stopTrackingPointer() {
        panel.ignoresMouseEvents = true
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
            self.localPointerMonitor = nil
        }
    }

    private func updateLayout() {
        guard let presentedModel else {
            return
        }

        hostingView.rootView = WordLookupCardView(model: presentedModel, arrow: currentArrow)
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else {
            return
        }

        let inset = WordLookupCardView.shadowInset
        let visibleFrame = screen(containing: wordFrame)?.visibleFrame ?? .zero
        let belowOriginY = wordFrame.minY - Self.wordGap - size.height + inset
        let aboveOriginY = wordFrame.maxY + Self.wordGap - inset
        if placesAboveWord == nil {
            placesAboveWord = belowOriginY + inset < visibleFrame.minY
        }

        // Center the card on the word, then keep it on screen.
        var originX = wordFrame.midX - size.width / 2
        originX = min(max(originX, visibleFrame.minX - inset), visibleFrame.maxX - size.width + inset)
        let originY = placesAboveWord == true ? aboveOriginY : belowOriginY

        let arrow = WordLookupCardView.Arrow(
            edge: placesAboveWord == true ? .bottom : .top,
            tipX: wordFrame.midX - (originX + inset)
        )
        if arrow != currentArrow {
            currentArrow = arrow
            hostingView.rootView = WordLookupCardView(model: presentedModel, arrow: arrow)
        }
        panel.setFrame(CGRect(x: originX, y: originY, width: size.width, height: size.height), display: true)
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(rect) }
            ?? NSScreen.main
    }
}

// MARK: - FirstClickHostingView

/// Accepts the first click, so card buttons respond while another app stays active.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
