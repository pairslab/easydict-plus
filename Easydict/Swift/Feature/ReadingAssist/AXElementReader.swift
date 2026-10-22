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
/// so range bounds come back as empty rects. Electron switches to complete accessibility for
/// `AXManualAccessibility`; Chrome rejects that attribute and switches for
/// `AXEnhancedUserInterface` after a two-second debounce.
final class WebTextGeometry: @unchecked Sendable {
    // MARK: Internal

    static let shared = WebTextGeometry()

    /// Requests geometry from the app at most once per interval.
    /// Returns whether a recent request may still be taking effect, so a retry can help.
    func request(for processIdentifier: pid_t) -> Bool {
        let now = Date()
        lock.lock()
        if let requested = requestDates[processIdentifier],
           now.timeIntervalSince(requested) < Self.requestInterval {
            lock.unlock()
            return now.timeIntervalSince(requested) < Self.settleTime
        }
        requestDates[processIdentifier] = now
        lock.unlock()

        let app = AXUIElementCreateApplication(processIdentifier)
        let manual = AXElementReader.setAttribute(app, "AXManualAccessibility", kCFBooleanTrue)
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

    /// Covers Chrome's debounce and the renderer rebuilding its tree.
    private static let settleTime: TimeInterval = 3
    private static let requestInterval: TimeInterval = 10

    private let lock = NSLock()
    private var requestDates: [pid_t: Date] = [:]
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
