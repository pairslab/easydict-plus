//
//  TranslationPreviewView.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import SFSafeSymbols
import SwiftUI

// MARK: - TranslationPreviewModel

/// Observable state of the floating glass card that streams a translation next to its source,
/// shared by text replacement and hover translation.
@MainActor
final class TranslationPreviewModel: ObservableObject {
    // MARK: Lifecycle

    init(serviceName: String, serviceIconName: String, activity: Activity, layout: Layout = .compact) {
        self.serviceName = serviceName
        self.serviceIconName = serviceIconName
        self.activity = activity
        self.layout = layout
    }

    // MARK: Internal

    /// What the service is doing with the text.
    enum Activity {
        case translating
        case polishing
    }

    /// How the processed text reached the user.
    enum Outcome {
        case replaced
        case inserted
        case copied
    }

    enum Phase: Equatable {
        case processing
        /// The text is complete and needs no status badge, as when reading a hover translation.
        case finished
        case completed(Outcome)
        case failed(String)
    }

    /// Card metrics, so the same card fits both a caret-side status and paragraph reading.
    struct Layout {
        /// A narrow card beside the caret that shows the latest lines while streaming.
        static let compact = Layout(width: 340, maxLines: 8, fontSize: 14)

        let width: CGFloat
        let maxLines: Int?
        let fontSize: CGFloat

        /// A card matching the width of the paragraph being read, within comfortable bounds.
        static func reading(width: CGFloat) -> Layout {
            Layout(width: min(max(width, 320), 620), maxLines: 24, fontSize: 15)
        }
    }

    let serviceName: String
    let serviceIconName: String
    let activity: Activity
    let layout: Layout

    @Published var text = ""
    @Published var phase = Phase.processing
}

// MARK: - TranslationPreviewView

/// A glass card that streams the processed text next to its source.
struct TranslationPreviewView: View {
    // MARK: Internal

    /// Transparent margin around the card so its shadow is not clipped by the panel.
    static let shadowInset: CGFloat = 18
    /// Horizontal padding between the card edge and its text.
    static let contentInset: CGFloat = 14

    @ObservedObject var model: TranslationPreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .padding(.horizontal, Self.contentInset)
        .padding(.vertical, 12)
        .frame(width: model.layout.width, alignment: .leading)
        .background(.regularMaterial, in: cardShape)
        .overlay {
            cardShape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
        .padding(Self.shadowInset)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: model.phase)
        .animation(.easeOut(duration: 0.16), value: model.text)
    }

    // MARK: Private

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var activityTitle: LocalizedStringKey {
        switch model.activity {
        case .translating:
            "action.text_replacement.preview.translating"
        case .polishing:
            "action.text_replacement.preview.polishing"
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(model.serviceIconName)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(model.serviceName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            status
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .processing:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text(activityTitle)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)

        case .finished:
            EmptyView()

        case let .completed(outcome):
            Label(outcomeTitle(outcome), systemSymbol: outcomeSymbol(outcome))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(outcome == .copied ? Color.accentColor : Color.green)
                .transition(.scale(scale: 0.8).combined(with: .opacity))

        case .failed:
            Label("action.text_replacement.preview.failed", systemSymbol: .exclamationmarkTriangleFill)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var content: some View {
        if case let .failed(message) = model.phase {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.text.isEmpty {
            PlaceholderLines()
        } else {
            Text(model.text)
                .font(.system(size: model.layout.fontSize))
                .foregroundStyle(.primary)
                .lineSpacing(model.layout.fontSize * 0.25)
                .lineLimit(model.layout.maxLines)
                // While streaming, keep the newest words visible; once done, read from the start.
                .truncationMode(model.phase == .processing ? .head : .tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func outcomeTitle(_ outcome: TranslationPreviewModel.Outcome) -> LocalizedStringKey {
        switch outcome {
        case .replaced:
            "action.text_replacement.preview.replaced"
        case .inserted:
            "action.text_replacement.preview.inserted"
        case .copied:
            "action.text_replacement.preview.copied"
        }
    }

    private func outcomeSymbol(_ outcome: TranslationPreviewModel.Outcome) -> SFSymbol {
        switch outcome {
        case .inserted, .replaced:
            .checkmarkCircleFill
        case .copied:
            .docOnClipboardFill
        }
    }
}

// MARK: - PlaceholderLines

/// Softly pulsing skeleton lines shown until the first chunk of text arrives.
private struct PlaceholderLines: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().frame(height: 8)
            Capsule().frame(width: 180, height: 8)
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
