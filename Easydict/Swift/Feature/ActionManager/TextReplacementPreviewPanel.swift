//
//  TextReplacementPreviewPanel.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Combine
import SwiftUI

// MARK: - TextReplacementPreviewPanel

/// Hosts `TextReplacementPreviewView` in a non-activating panel next to the caret,
/// so the target app keeps keyboard focus while its text is processed.
@MainActor
final class TextReplacementPreviewPanel {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = TextReplacementPreviewPanel()

    /// Shows `model` below `anchorRect` (Cocoa screen coordinates), or below the mouse when nil.
    func present(_ model: TextReplacementPreviewModel, anchorRect: CGRect?) {
        dismissTask?.cancel()
        presentedModel = model
        self.anchorRect = anchorRect ?? mouseAnchorRect()
        placesAboveAnchor = nil

        hostingView.rootView = TextReplacementPreviewView(model: model)
        modelObservation = model.objectWillChange.sink { [weak self] _ in
            // `objectWillChange` fires before the new value is stored, so measure on the next turn.
            DispatchQueue.main.async { self?.updateFrame() }
        }
        updateFrame()

        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeInDuration
                panel.animator().alphaValue = 1
            }
        }
    }

    /// Fades out the preview after `delay`, unless a newer preview has been presented meanwhile.
    func dismiss(after delay: TimeInterval = 0) {
        dismissTask?.cancel()
        let modelToDismiss = presentedModel
        dismissTask = Task { [weak self] in
            await Task.sleep(seconds: delay)
            guard let self, !Task.isCancelled, presentedModel === modelToDismiss else {
                return
            }
            fadeOut()
        }
    }

    // MARK: Private

    private static let fadeInDuration: TimeInterval = 0.14
    private static let fadeOutDuration: TimeInterval = 0.22
    /// Vertical distance between the caret and the card.
    private static let anchorGap: CGFloat = 6

    private var presentedModel: TextReplacementPreviewModel?
    private var modelObservation: AnyCancellable?
    private var dismissTask: Task<(), Never>?
    private var anchorRect = CGRect.zero
    /// Placement is decided once per presentation so the card does not jump while it grows.
    private var placesAboveAnchor: Bool?

    private lazy var hostingView: NSHostingView<TextReplacementPreviewView> = {
        let placeholder = TextReplacementPreviewModel(
            serviceName: "",
            serviceIconName: "",
            activity: .translating
        )
        let view = NSHostingView(rootView: TextReplacementPreviewView(model: placeholder))
        // The panel frame is managed manually to keep the card pinned to the caret.
        view.sizingOptions = []
        return view
    }()

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = hostingView
        return panel
    }()

    private func updateFrame() {
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else {
            return
        }

        let inset = TextReplacementPreviewView.shadowInset
        let visibleFrame = screen(containing: anchorRect)?.visibleFrame ?? .zero

        // The panel carries a transparent inset around the card, so the card edges are
        // `inset` points inside the panel frame.
        let belowOriginY = anchorRect.minY - Self.anchorGap - size.height + inset
        let aboveOriginY = anchorRect.maxY + Self.anchorGap - inset
        if placesAboveAnchor == nil {
            placesAboveAnchor = belowOriginY + inset < visibleFrame.minY
        }

        var origin = CGPoint(
            x: anchorRect.minX - inset,
            y: placesAboveAnchor == true ? aboveOriginY : belowOriginY
        )
        origin.x = min(max(origin.x, visibleFrame.minX - inset), visibleFrame.maxX - size.width + inset)
        origin.y = min(max(origin.y, visibleFrame.minY - inset), visibleFrame.maxY - size.height + inset)

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func fadeOut() {
        let fadingModel = presentedModel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                // A preview presented during the fade owns the panel now.
                guard let self, self.presentedModel === fadingModel else {
                    return
                }
                self.panel.orderOut(nil)
                self.presentedModel = nil
                self.modelObservation = nil
            }
        }
    }

    private func mouseAnchorRect() -> CGRect {
        let location = NSEvent.mouseLocation
        return CGRect(x: location.x, y: location.y - 10, width: 1, height: 20)
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(rect) }
            ?? NSScreen.main
    }
}
