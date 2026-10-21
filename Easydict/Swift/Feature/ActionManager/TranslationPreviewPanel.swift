//
//  TranslationPreviewPanel.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Combine
import SwiftUI

// MARK: - TranslationPreviewPanel

/// Hosts `TranslationPreviewView` in a non-activating panel next to its source text,
/// so the target app keeps keyboard focus while its text is processed.
@MainActor
final class TranslationPreviewPanel {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = TranslationPreviewPanel()

    /// Screen frame of the visible card, excluding its transparent shadow margin.
    var cardFrame: CGRect? {
        guard panel.isVisible, presentedModel != nil else {
            return nil
        }
        let inset = TranslationPreviewView.shadowInset
        return panel.frame.insetBy(dx: inset, dy: inset)
    }

    /// Shows `model` below `anchorRect` (Cocoa screen coordinates), or below the mouse when nil.
    ///
    /// - Parameter alignsTextWithAnchor: Lines the card text up with the anchor's leading edge,
    ///   as when the card sits under a paragraph, instead of lining up the card edge.
    func present(_ model: TranslationPreviewModel, anchorRect: CGRect?, alignsTextWithAnchor: Bool = false) {
        dismissTask?.cancel()
        presentedModel = model
        self.anchorRect = anchorRect ?? mouseAnchorRect()
        leadingOffset = alignsTextWithAnchor ? TranslationPreviewView.contentInset : 0
        placesAboveAnchor = nil

        hostingController.rootView = TranslationPreviewView(model: model)
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

    /// Whether `model` is the card currently shown.
    func isPresenting(_ model: TranslationPreviewModel) -> Bool {
        presentedModel === model && panel.isVisible
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
    /// Vertical distance between the source text and the card.
    private static let anchorGap: CGFloat = 10
    /// Unconstrained proposal so the card reports its natural size; its width is fixed in SwiftUI.
    private static let maximumMeasureSize = CGSize(width: 10_000, height: 10_000)

    private var presentedModel: TranslationPreviewModel?
    private var modelObservation: AnyCancellable?
    private var dismissTask: Task<(), Never>?
    private var anchorRect = CGRect.zero
    /// Extra leftward shift of the card so its text, not its edge, starts at the anchor.
    private var leadingOffset: CGFloat = 0
    /// Placement is decided once per presentation so the card does not jump while it grows.
    private var placesAboveAnchor: Bool?

    private lazy var hostingController: NSHostingController<TranslationPreviewView> = {
        let placeholder = TranslationPreviewModel(
            serviceName: "",
            serviceIconName: "",
            activity: .translating
        )
        let controller = NSHostingController(rootView: TranslationPreviewView(model: placeholder))
        // The panel frame is managed manually to keep the card pinned to its source. Without
        // sizing options the view reports a zero `fittingSize`, so measure via `sizeThatFits`.
        controller.sizingOptions = []
        return controller
    }()

    private lazy var panel = NSPanel.floatingOverlay(level: .statusBar, contentView: hostingController.view)

    private func updateFrame() {
        let size = hostingController.sizeThatFits(in: Self.maximumMeasureSize)
        guard size.width > 0, size.height > 0 else {
            return
        }

        let inset = TranslationPreviewView.shadowInset
        let visibleFrame = screen(containing: anchorRect)?.visibleFrame ?? .zero

        // The panel carries a transparent inset around the card, so the card edges are
        // `inset` points inside the panel frame.
        let belowOriginY = anchorRect.minY - Self.anchorGap - size.height + inset
        let aboveOriginY = anchorRect.maxY + Self.anchorGap - inset
        if placesAboveAnchor == nil {
            placesAboveAnchor = belowOriginY + inset < visibleFrame.minY
        }

        var origin = CGPoint(
            x: anchorRect.minX - leadingOffset - inset,
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
