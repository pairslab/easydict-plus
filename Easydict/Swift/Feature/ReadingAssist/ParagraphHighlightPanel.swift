//
//  ParagraphHighlightPanel.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import SwiftUI

// MARK: - ParagraphHighlightPanel

/// Outlines the paragraph that hover translation will translate, gliding between paragraphs
/// as the mouse moves. The panel never takes focus or mouse events.
@MainActor
final class ParagraphHighlightPanel {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = ParagraphHighlightPanel()

    /// Shows the outline around `paragraphFrame` (Cocoa screen coordinates).
    func show(around paragraphFrame: CGRect) {
        let frame = paragraphFrame.insetBy(dx: -Self.padding.width, dy: -Self.padding.height)
        isHiding = false

        guard panel.isVisible, panel.alphaValue > 0 else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeInDuration
                panel.animator().alphaValue = 1
            }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.glideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible, !isHiding else {
            return
        }
        isHiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                // A paragraph highlighted during the fade keeps the panel on screen.
                guard let self, self.isHiding else {
                    return
                }
                self.panel.orderOut(nil)
                self.isHiding = false
            }
        }
    }

    // MARK: Private

    private static let padding = CGSize(width: 6, height: 4)
    private static let fadeInDuration: TimeInterval = 0.12
    private static let glideDuration: TimeInterval = 0.16
    private static let fadeOutDuration: TimeInterval = 0.18

    private var isHiding = false

    private lazy var panel: NSPanel = {
        let hostingView = NSHostingView(rootView: ParagraphHighlightView())
        // The outline follows the panel frame instead of resizing the panel itself.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        return NSPanel.floatingOverlay(level: .floating, contentView: hostingView)
    }()
}

// MARK: - ParagraphHighlightView

/// A soft accent-colored ring, like a focus ring drawn around a paragraph.
private struct ParagraphHighlightView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.accentColor.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
            }
    }
}
