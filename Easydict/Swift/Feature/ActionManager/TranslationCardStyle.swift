//
//  TranslationCardStyle.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/22.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import SFSafeSymbols
import SwiftUI

// MARK: - TranslationCardStyle

/// Shared metrics of the floating translation cards, so the word card and the translation card
/// read as one compact family that matches the result headers in the query window.
enum TranslationCardStyle {
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 8
    /// Transparent margin around a card so its shadow is not clipped by the panel.
    static let shadowInset: CGFloat = 18
    static let headerIconSize: CGFloat = 16

    /// Service titles and other headers; the query window's result headers use the same face.
    static let headerFont = Font.system(size: 12, weight: .semibold)
    static let bodyFont = Font.system(size: 14)
    static let captionFont = Font.system(size: 11, weight: .semibold)
    /// Empty and error states, quieter than content.
    static let placeholderFont = Font.system(size: 13)
}

// MARK: - TranslationCardChrome

/// The material, hairline border and shadow of a floating translation card.
private struct TranslationCardChrome<CardShape: Shape>: ViewModifier {
    let shape: CardShape

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: shape)
            .overlay {
                shape.stroke(.primary.opacity(0.1), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            .padding(TranslationCardStyle.shadowInset)
    }
}

extension View {
    /// Applies the shared card surface, then leaves room around it for the shadow.
    func translationCardChrome(in shape: some Shape) -> some View {
        modifier(TranslationCardChrome(shape: shape))
    }
}

// MARK: - LoadingLines

/// Softly pulsing placeholder bars shown while card content loads.
struct LoadingLines: View {
    // MARK: Internal

    /// Bar widths; nil fills the available width.
    let widths: [CGFloat?]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                Capsule()
                    .frame(width: width, height: 8)
                    .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .foregroundStyle(.primary.opacity(isPulsing ? 0.06 : 0.14))
        .padding(.vertical, 3)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    // MARK: Private

    @State private var isPulsing = false
}

// MARK: - ServiceDisplay

/// How a service is presented on translation results and cards.
///
/// Some providers are kept out of everyday translation chrome: they show a neutral title and the
/// system translate symbol instead of their brand. Settings keep each service's own name and icon,
/// and requests, credentials and model selection are unchanged.
@objc(EZServiceDisplay)
final class ServiceDisplay: NSObject {
    // MARK: Internal

    @objc(titleForService:)
    static func title(for service: QueryService) -> String {
        isUnbranded(service) ? String(localized: "query_result.service.neutral_title") : service.name()
    }

    /// The service icon, or a template symbol to tint like text when the brand is hidden.
    @objc(iconForService:)
    static func icon(for service: QueryService) -> NSImage? {
        guard isUnbranded(service) else {
            return NSImage(named: service.iconName())
        }
        let symbol: NSImage
        if #available(macOS 14.4, *) {
            symbol = NSImage(systemSymbol: .translate)
        } else {
            symbol = NSImage(systemSymbol: .characterBubble)
        }
        symbol.isTemplate = true
        return symbol
    }

    /// The model button title; a neutral label when the model name would repeat the brand.
    @MainActor
    @objc(modelTitleForService:)
    static func modelTitle(for service: StreamService) -> String {
        isUnbranded(service) ? String(localized: "query_result.service.model") : service.modelDisplayName
    }

    // MARK: Private

    private static let unbrandedTypes: Set<ServiceType> = [.deepSeek]

    private static func isUnbranded(_ service: QueryService) -> Bool {
        unbrandedTypes.contains(service.serviceType())
    }
}
