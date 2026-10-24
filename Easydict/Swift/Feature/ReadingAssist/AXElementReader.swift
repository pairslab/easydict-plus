//
//  AXElementReader.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import ApplicationServices

// MARK: - AXElementReader

/// Thin wrappers over the Accessibility C API for reading text and geometry from other apps,
/// including the WebKit/Chromium text-marker attributes that AXSwift does not cover.
///
/// Every call waits on the target app, so use these off the main thread.
enum AXElementReader {
    static let systemWide = AXUIElementCreateSystemWide()

    /// The element at a screen point in Accessibility (top-left origin) coordinates.
    static func element(at axPoint: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(axPoint.x), Float(axPoint.y), &element)
        return error == .success ? element : nil
    }

    static func processIdentifier(of element: AXUIElement) -> pid_t {
        var processIdentifier: pid_t = 0
        AXUIElementGetPid(element, &processIdentifier)
        return processIdentifier
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func parameterizedAttribute(_ element: AXUIElement, _ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value)
        return error == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func role(of element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        rect(from: attribute(element, "AXFrame"))
    }

    static func parent(of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(element, kAXParentAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    @discardableResult
    static func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }

    static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    static func rect(from value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    static func range(from value: CFTypeRef?) -> CFRange? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    static func pointValue(_ point: CGPoint) -> AXValue {
        var point = point
        return AXValueCreate(.cgPoint, &point)!
    }

    static func rangeValue(_ range: CFRange) -> AXValue {
        var range = range
        return AXValueCreate(.cfRange, &range)!
    }
}

// MARK: - WebTextGeometry

/// Asks a Chromium-based app to build the per-character geometry behind `AXBoundsForRange`.
///
/// Chromium gives tools that only read it basic accessibility, which omits inline text boxes,
/// so range bounds come back as empty rects; Electron apps may not expose their page text at all.
/// Electron switches to complete accessibility for `AXManualAccessibility`; Chrome rejects that
/// attribute and switches for `AXEnhancedUserInterface` after a two-second debounce.
final class WebTextGeometry: @unchecked Sendable {
    // MARK: Internal

    /// What the lookup found missing.
    enum Need: Hashable {
        /// Text exists but its range bounds are empty.
        case inlineTextBoxes
        /// The web area exposes no text under the pointer. Only Electron's flag is used here,
        /// because a page area without text is common and `AXEnhancedUserInterface` affects windows.
        case textTree
    }

    static let shared = WebTextGeometry()

    /// Requests geometry from the app at most once per interval.
    /// Returns whether a recent request may still be taking effect, so a retry can help.
    func request(_ need: Need, for processIdentifier: pid_t) -> Bool {
        let now = Date()
        let key = RequestKey(processIdentifier: processIdentifier, need: need)
        lock.lock()
        if let requested = requestDates[key], now.timeIntervalSince(requested) < Self.requestInterval {
            lock.unlock()
            return now.timeIntervalSince(requested) < Self.settleTime
        }
        if need == .textTree, completeTreePIDs.contains(processIdentifier) {
            // The app built its complete tree earlier, so text missing now is not going to appear.
            lock.unlock()
            return false
        }
        requestDates[key] = now
        lock.unlock()

        let app = AXUIElementCreateApplication(processIdentifier)
        let manual = AXElementReader.setAttribute(app, "AXManualAccessibility", kCFBooleanTrue)
        if need == .textTree {
            logInfo("Reading assist: requested web text tree, manual: \(manual.rawValue)")
            lock.lock()
            defer { lock.unlock() }
            guard manual == .success else {
                // Browsers reject the flag; forget the request so later taps do not wait on it.
                requestDates[key] = nil
                return false
            }
            completeTreePIDs.insert(processIdentifier)
            return true
        }
        let enhanced = manual == .success
            ? nil
            : AXElementReader.setAttribute(app, "AXEnhancedUserInterface", kCFBooleanTrue)
        logInfo(
            "Reading assist: requested web text geometry, manual: \(manual.rawValue), "
                + "enhanced: \(enhanced.map { "\($0.rawValue)" } ?? "skipped")"
        )
        return true
    }

    // MARK: Private

    private struct RequestKey: Hashable {
        let processIdentifier: pid_t
        let need: Need
    }

    /// Covers Chrome's debounce and the renderer rebuilding its tree.
    private static let settleTime: TimeInterval = 3
    private static let requestInterval: TimeInterval = 10

    private let lock = NSLock()
    private var requestDates: [RequestKey: Date] = [:]
    /// Apps that accepted `AXManualAccessibility` for a missing text tree.
    private var completeTreePIDs = Set<pid_t>()
}

// MARK: - SelectionGeometry

/// Relates an app's current text selection to the pointer. A translated selection stays highlighted
/// after the user moves on; this tells whether a later gesture still points at it, or at other text.
enum SelectionGeometry {
    // MARK: Internal

    enum Relation: Equatable {
        /// The pointer is on the selection, whose bounds are given in Accessibility coordinates.
        case underPointer(CGRect)
        /// The selection is somewhere else, or the pointer is over another app.
        case elsewhere
        /// The app reports neither the selection's bounds nor its text element's frame.
        case unknown
    }

    /// Relates the selection of the app with `processIdentifier` to `axPoint`.
    /// Every call waits on the target app, so run it off the main thread.
    static func relation(to axPoint: CGPoint, processIdentifier: pid_t) -> Relation {
        guard let element = AXElementReader.element(at: axPoint) else {
            return .unknown
        }
        guard AXElementReader.processIdentifier(of: element) == processIdentifier else {
            return .elsewhere
        }
        let focused = focusedElement(of: processIdentifier)
        // Web selections live on the document; native ones on the focused text element.
        let candidates = [webArea(above: element), focused].compactMap { $0 }
        for candidate in candidates {
            guard let bounds = markerBounds(of: candidate) ?? rangeBounds(of: candidate) else {
                continue
            }
            return bounds.insetBy(dx: -hitSlop, dy: -hitSlop).contains(axPoint) ? .underPointer(bounds) : .elsewhere
        }
        if let focused, let frame = AXElementReader.frame(of: focused), !frame.isEmpty {
            return frame.contains(axPoint) ? .unknown : .elsewhere
        }
        return .unknown
    }

    // MARK: Private

    /// Room around the selection that still counts as pointing at it.
    private static let hitSlop: CGFloat = 6
    private static let maximumWebAreaDepth = 32

    private static func focusedElement(of processIdentifier: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(processIdentifier)
        guard let value = AXElementReader.attribute(app, kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func webArea(above element: AXUIElement) -> AXUIElement? {
        var node = element
        for _ in 0 ..< maximumWebAreaDepth {
            if AXElementReader.role(of: node) == "AXWebArea" {
                return node
            }
            guard let parent = AXElementReader.parent(of: node) else {
                return nil
            }
            node = parent
        }
        return nil
    }

    /// WebKit and Chromium expose the selection as a text-marker range.
    private static func markerBounds(of element: AXUIElement) -> CGRect? {
        guard let range = AXElementReader.attribute(element, "AXSelectedTextMarkerRange") else {
            return nil
        }
        return nonEmpty(AXElementReader.rect(
            from: AXElementReader.parameterizedAttribute(element, "AXBoundsForTextMarkerRange", range)
        ))
    }

    /// Native text views expose the selection as a character range.
    private static func rangeBounds(of element: AXUIElement) -> CGRect? {
        guard let range = AXElementReader.range(from: AXElementReader.attribute(
            element,
            kAXSelectedTextRangeAttribute
        )),
            range.length > 0 else {
            return nil
        }
        return nonEmpty(AXElementReader.rect(
            from: AXElementReader.parameterizedAttribute(element, "AXBoundsForRange", AXElementReader.rangeValue(range))
        ))
    }

    /// Chromium answers with an empty rect until it builds its text geometry; that tells nothing.
    private static func nonEmpty(_ rect: CGRect?) -> CGRect? {
        guard let rect, rect.width > 0, rect.height > 0 else {
            return nil
        }
        return rect
    }
}

// MARK: - AXCoordinateSpace

/// Converts between Accessibility (top-left origin) and Cocoa (bottom-left origin) screen rects.
struct AXCoordinateSpace: Sendable {
    /// Top edge of the primary screen. Read it on the main thread.
    let primaryScreenMaxY: CGFloat

    func axPoint(fromCocoa point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    func cocoaRect(fromAX rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenMaxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
