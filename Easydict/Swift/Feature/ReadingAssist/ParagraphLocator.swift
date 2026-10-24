//
//  ParagraphLocator.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import ApplicationServices

// MARK: - HoveredParagraph

/// A paragraph of on-screen text under the mouse.
struct HoveredParagraph: Equatable, Sendable {
    let text: String
    /// Screen frame of the paragraph, in Cocoa coordinates.
    let frame: CGRect
    let processIdentifier: pid_t
}

// MARK: - ParagraphLocator

/// Finds the paragraph under a screen point through the Accessibility API.
///
/// Web content (Safari, Chromium and Electron apps) is read with the text-marker API that
/// VoiceOver uses, falling back to the paragraph joined from neighboring text runs; native text
/// views are split by line breaks around the character under the point; other elements contribute
/// their own text.
/// Every lookup waits on the target app, so run it off the main thread.
struct ParagraphLocator: Sendable {
    // MARK: Internal

    let coordinateSpace: AXCoordinateSpace
    /// Tallest frame accepted as a paragraph, so a whole page is never taken.
    let maximumHeight: CGFloat

    /// The paragraph under `cocoaPoint`, or nil when there is no readable text there.
    func paragraph(at cocoaPoint: CGPoint) -> HoveredParagraph? {
        let point = coordinateSpace.axPoint(fromCocoa: cocoaPoint)
        guard let element = AXElementReader.element(at: point) else {
            return nil
        }
        let processIdentifier = AXElementReader.processIdentifier(of: element)
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        let candidates: [(source: String, read: () -> (text: String, axFrame: CGRect)?)] = [
            ("text markers", { webParagraph(from: element, at: point) }),
            ("text runs", { webBlock(containing: element) }),
            ("native text", { nativeParagraph(in: element, at: point) }),
            ("element text", { ownText(of: element) }),
        ]
        for candidate in candidates {
            guard let found = candidate.read(), let paragraph = validated(
                text: found.text,
                axFrame: found.axFrame,
                point: point,
                processIdentifier: processIdentifier
            ) else {
                continue
            }
            // Length and height only, never the text, so overly broad captures can be diagnosed.
            logInfo(
                "Reading assist: paragraph from \(candidate.source), characters: \(paragraph.text.count), "
                    + "height: \(Int(found.axFrame.height))"
            )
            return paragraph
        }
        return nil
    }

    // MARK: Private

    private static let maximumTextLength = 4000
    private static let maximumDepth = 8
    /// Slack around a paragraph frame that still counts as pointing at it.
    private static let hitSlop: CGFloat = 6
    /// Roles whose own title or value is worth translating, such as UI labels in another language.
    private static let labelRoles: Set<String> = [
        kAXStaticTextRole, kAXButtonRole, kAXMenuItemRole, kAXMenuBarItemRole, kAXCheckBoxRole,
        kAXRadioButtonRole, kAXPopUpButtonRole, kAXCellRole, "AXHeading", "AXLink",
    ]

    /// The paragraph from WebKit or Chromium text markers, asked on the element or its ancestors.
    private func webParagraph(from element: AXUIElement, at point: CGPoint) -> (text: String, axFrame: CGRect)? {
        var node = element
        for depth in 0 ..< Self.maximumDepth {
            if let marker = AXElementReader.parameterizedAttribute(
                node,
                "AXTextMarkerForPosition",
                AXElementReader.pointValue(point)
            ),
                let range = AXElementReader.parameterizedAttribute(
                    node,
                    "AXParagraphTextMarkerRangeForTextMarker",
                    marker
                ),
                let text = AXElementReader.parameterizedAttribute(node, "AXStringForTextMarkerRange", range) as? String,
                let bounds = AXElementReader.rect(
                    from: AXElementReader.parameterizedAttribute(node, "AXBoundsForTextMarkerRange", range)
                ) {
                return (text, bounds)
            }
            if AXElementReader.role(of: node) == "AXWebArea" {
                return nil
            }
            // Avoid fetching every ancestor before trying the element already under the pointer.
            guard depth + 1 < Self.maximumDepth, let parent = AXElementReader.parent(of: node) else {
                return nil
            }
            node = parent
        }
        return nil
    }

    /// The paragraph continuing around a static text run, for engines without paragraph markers.
    ///
    /// Joined by layout rather than as the whole block, which in a PDF text layer is a page.
    private func webBlock(containing element: AXUIElement) -> (text: String, axFrame: CGRect)? {
        guard AXElementReader.role(of: element) == kAXStaticTextRole,
              let lineHeight = TextRunReader.lineHeight(of: element),
              let paragraph = TextRunReader.paragraph(
                  around: element, lineHeight: lineHeight, limit: Self.maximumTextLength / 2
              )
        else {
            return nil
        }
        let joined = paragraph.joined
        return joined.text.isEmpty ? nil : (joined.text, joined.frame)
    }

    /// The paragraph around the character under the point in a native text view.
    private func nativeParagraph(in element: AXUIElement, at point: CGPoint) -> (text: String, axFrame: CGRect)? {
        guard let characterRange = AXElementReader.range(
            from: AXElementReader.parameterizedAttribute(
                element,
                "AXRangeForPosition",
                AXElementReader.pointValue(point)
            )
        ),
            let fullText = AXElementReader.string(element, kAXValueAttribute),
            !fullText.isEmpty
        else {
            return nil
        }

        let nsText = fullText as NSString
        let location = min(max(characterRange.location, 0), nsText.length - 1)
        let paragraphRange = nsText.paragraphRange(for: NSRange(location: location, length: 0))
        let range = CFRange(location: paragraphRange.location, length: paragraphRange.length)
        guard let bounds = AXElementReader.rect(
            from: AXElementReader.parameterizedAttribute(element, "AXBoundsForRange", AXElementReader.rangeValue(range))
        ) else {
            return nil
        }
        return (nsText.substring(with: paragraphRange), bounds)
    }

    /// The element's own text, such as a label, heading, or button title.
    private func ownText(of element: AXUIElement) -> (text: String, axFrame: CGRect)? {
        guard let role = AXElementReader.role(of: element), Self.labelRoles.contains(role),
              let frame = AXElementReader.frame(of: element)
        else {
            return nil
        }
        let text = [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
            .lazy
            .compactMap { AXElementReader.string(element, $0) }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return text.map { ($0, frame) }
    }

    /// Accepts text worth translating whose frame is on screen, under the point, and not page-sized.
    private func validated(
        text: String,
        axFrame: CGRect,
        point: CGPoint,
        processIdentifier: pid_t
    )
        -> HoveredParagraph? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.contains(where: \.isLetter),
              axFrame.width > 4, axFrame.height > 4, axFrame.height <= maximumHeight,
              axFrame.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(point)
        else {
            return nil
        }
        return HoveredParagraph(
            text: String(trimmed.prefix(Self.maximumTextLength)),
            frame: coordinateSpace.cocoaRect(fromAX: axFrame),
            processIdentifier: processIdentifier
        )
    }
}
