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
/// VoiceOver uses, falling back to the nearest block element; native text views are split by
/// line breaks around the character under the point; other elements contribute their own text.
/// Every lookup waits on the target app, so run it off the main thread.
struct ParagraphLocator: Sendable {
    // MARK: Lifecycle

    /// - Parameters:
    ///   - primaryScreenMaxY: Top edge of the primary screen, used to flip between Cocoa and
    ///     Accessibility coordinates. Read it on the main thread.
    ///   - maximumHeight: Tallest frame accepted as a paragraph, so a whole page is never taken.
    init(primaryScreenMaxY: CGFloat, maximumHeight: CGFloat) {
        self.primaryScreenMaxY = primaryScreenMaxY
        self.maximumHeight = maximumHeight
    }

    // MARK: Internal

    /// The paragraph under `cocoaPoint`, or nil when there is no readable text there.
    func paragraph(at cocoaPoint: CGPoint) -> HoveredParagraph? {
        let point = CGPoint(x: cocoaPoint.x, y: primaryScreenMaxY - cocoaPoint.y)
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(Self.systemWide, Float(point.x), Float(point.y), &hitElement)
            == .success,
            let element = hitElement
        else {
            return nil
        }

        var processIdentifier: pid_t = 0
        AXUIElementGetPid(element, &processIdentifier)
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        let candidates: [() -> (text: String, axFrame: CGRect)?] = [
            { webParagraph(from: element, at: point) },
            { webBlock(containing: element) },
            { nativeParagraph(in: element, at: point) },
            { ownText(of: element) },
        ]
        for candidate in candidates {
            guard let found = candidate(), let paragraph = validated(
                text: found.text,
                axFrame: found.axFrame,
                point: point,
                processIdentifier: processIdentifier
            ) else {
                continue
            }
            return paragraph
        }
        return nil
    }

    // MARK: Private

    private static let systemWide = AXUIElementCreateSystemWide()
    private static let maximumAncestorDepth = 8
    private static let maximumTextLength = 4000
    /// Slack around a paragraph frame that still counts as pointing at it.
    private static let hitSlop: CGFloat = 6
    /// Roles whose own title or value is worth translating, such as UI labels in another language.
    private static let labelRoles: Set<String> = [
        kAXStaticTextRole, kAXButtonRole, kAXMenuItemRole, kAXMenuBarItemRole, kAXCheckBoxRole,
        kAXRadioButtonRole, kAXPopUpButtonRole, kAXCellRole, "AXHeading", "AXLink",
    ]

    private let primaryScreenMaxY: CGFloat
    private let maximumHeight: CGFloat

    // MARK: Lookups

    /// The paragraph from WebKit or Chromium text markers, asked on the element or its ancestors.
    private func webParagraph(from element: AXUIElement, at point: CGPoint) -> (text: String, axFrame: CGRect)? {
        var current: AXUIElement? = element
        for _ in 0 ..< Self.maximumAncestorDepth {
            guard let node = current else {
                return nil
            }
            if let marker = parameterizedValue(node, "AXTextMarkerForPosition", pointValue(point)),
               let range = parameterizedValue(node, "AXParagraphTextMarkerRangeForTextMarker", marker),
               let text = parameterizedValue(node, "AXStringForTextMarkerRange", range) as? String,
               let bounds = rect(from: parameterizedValue(node, "AXBoundsForTextMarkerRange", range)) {
                return (text, bounds)
            }
            if role(of: node) == "AXWebArea" {
                return nil
            }
            current = parent(of: node)
        }
        return nil
    }

    /// The joined text of the block that holds a static text run, for engines without paragraph markers.
    private func webBlock(containing element: AXUIElement) -> (text: String, axFrame: CGRect)? {
        guard role(of: element) == kAXStaticTextRole, var block = parent(of: element) else {
            return nil
        }
        // Climb out of inline wrappers such as links to reach the paragraph-level element.
        while role(of: block) == "AXLink", let next = parent(of: block) {
            block = next
        }
        guard role(of: block) != "AXWebArea", let frame = rect(from: attributeValue(block, "AXFrame")) else {
            return nil
        }
        let text = staticTexts(in: block).joined()
        return text.isEmpty ? nil : (text, frame)
    }

    /// The paragraph around the character under the point in a native text view.
    private func nativeParagraph(in element: AXUIElement, at point: CGPoint) -> (text: String, axFrame: CGRect)? {
        guard let indexValue = parameterizedValue(element, "AXRangeForPosition", pointValue(point)),
              let fullText = attributeValue(element, kAXValueAttribute) as? String,
              !fullText.isEmpty
        else {
            return nil
        }

        var characterRange = CFRange()
        guard CFGetTypeID(indexValue) == AXValueGetTypeID(),
              AXValueGetValue(indexValue as! AXValue, .cfRange, &characterRange)
        else {
            return nil
        }

        let nsText = fullText as NSString
        let location = min(max(characterRange.location, 0), nsText.length - 1)
        let paragraphRange = nsText.paragraphRange(for: NSRange(location: location, length: 0))
        let range = CFRange(location: paragraphRange.location, length: paragraphRange.length)
        guard let bounds = rect(from: parameterizedValue(element, "AXBoundsForRange", rangeValue(range))) else {
            return nil
        }
        return (nsText.substring(with: paragraphRange), bounds)
    }

    /// The element's own text, such as a label, heading, or button title.
    private func ownText(of element: AXUIElement) -> (text: String, axFrame: CGRect)? {
        guard let role = role(of: element), Self.labelRoles.contains(role),
              let frame = rect(from: attributeValue(element, "AXFrame"))
        else {
            return nil
        }
        let text = [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
            .lazy
            .compactMap { attributeValue(element, $0) as? String }
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

        let cocoaFrame = CGRect(
            x: axFrame.minX,
            y: primaryScreenMaxY - axFrame.maxY,
            width: axFrame.width,
            height: axFrame.height
        )
        return HoveredParagraph(
            text: String(trimmed.prefix(Self.maximumTextLength)),
            frame: cocoaFrame,
            processIdentifier: processIdentifier
        )
    }

    // MARK: Accessibility helpers

    private func staticTexts(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < Self.maximumAncestorDepth else {
            return []
        }
        if role(of: element) == kAXStaticTextRole {
            return (attributeValue(element, kAXValueAttribute) as? String).map { [$0] } ?? []
        }
        let children = attributeValue(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return children.flatMap { staticTexts(in: $0, depth: depth + 1) }
    }

    private func role(of element: AXUIElement) -> String? {
        attributeValue(element, kAXRoleAttribute) as? String
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        guard let value = attributeValue(element, kAXParentAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func attributeValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    private func parameterizedValue(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
        return error == .success ? value : nil
    }

    private func rect(from value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    private func pointValue(_ point: CGPoint) -> AXValue {
        var point = point
        return AXValueCreate(.cgPoint, &point)!
    }

    private func rangeValue(_ range: CFRange) -> AXValue {
        var range = range
        return AXValueCreate(.cfRange, &range)!
    }
}
