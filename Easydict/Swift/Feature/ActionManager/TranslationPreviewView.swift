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

    init(serviceTitle: String, serviceIcon: NSImage?, activity: Activity, layout: Layout = .compact) {
        self.serviceTitle = serviceTitle
        self.serviceIcon = serviceIcon
        self.activity = activity
        self.layout = layout
    }

    /// A card for `service`, presented as translation results present it; see `ServiceDisplay`.
    convenience init(service: QueryService, activity: Activity, layout: Layout = .compact) {
        self.init(
            serviceTitle: ServiceDisplay.title(for: service),
            serviceIcon: ServiceDisplay.icon(for: service),
            activity: activity,
            layout: layout
        )
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
        var maximumContentHeight: CGFloat?

        /// A card matching the width of the paragraph being read, within comfortable bounds.
        static func reading(width: CGFloat) -> Layout {
            Layout(width: min(max(width, 320), 620), maxLines: nil, fontSize: 15, maximumContentHeight: 400)
        }

        /// Chooses a comfortable width from the source blocks instead of treating a pointer anchor as text width.
        @MainActor
        static func selection(text: String, screenSize: CGSize) -> Layout {
            let maximumWidth = min(620, max(240, screenSize.width - 40))
            let maximumHeight = min(560, max(160, screenSize.height * 0.65))
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 8
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15),
                .paragraphStyle: paragraphStyle,
            ]
            let source = ReadingText(text).source as NSString
            var width = min(320, maximumWidth)
            while width < maximumWidth {
                let bounds = source.boundingRect(
                    with: CGSize(width: width - 2 * TranslationPreviewView.contentInset, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes
                )
                if bounds.height <= min(maximumHeight, width * 0.65) { break }
                width = min(width + 60, maximumWidth)
            }
            return Layout(width: width, maxLines: nil, fontSize: 15, maximumContentHeight: maximumHeight)
        }
    }

    let serviceTitle: String
    let serviceIcon: NSImage?
    let activity: Activity
    let layout: Layout

    @Published var text = ""
    @Published var phase = Phase.processing
    /// Measured by the reading view so short translations stay compact and long ones scroll.
    @Published var contentHeight: CGFloat = 0
}

// MARK: - TranslationPreviewView

/// A glass card that streams the processed text next to its source.
struct TranslationPreviewView: View {
    // MARK: Internal

    static let shadowInset = TranslationCardStyle.shadowInset
    /// Horizontal padding between the card edge and its text.
    static let contentInset = TranslationCardStyle.horizontalPadding

    @ObservedObject var model: TranslationPreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: TranslationCardStyle.sectionSpacing) {
            header
            content
        }
        .padding(.horizontal, Self.contentInset)
        .padding(.vertical, TranslationCardStyle.verticalPadding)
        .frame(width: model.layout.width, alignment: .leading)
        .translationCardChrome(in: cardShape)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: model.phase)
        .animation(.easeOut(duration: 0.16), value: model.text)
    }

    // MARK: Private

    private struct ContentHeightKey: PreferenceKey {
        static var defaultValue: CGFloat { 0 }

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TranslationCardStyle.cornerRadius, style: .continuous)
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
            if let icon = model.serviceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(icon.isTemplate ? .template : .original)
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: TranslationCardStyle.headerIconSize, height: TranslationCardStyle.headerIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            Text(model.serviceTitle)
                .font(TranslationCardStyle.headerFont)
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
                .font(TranslationCardStyle.captionFont)
                .foregroundStyle(outcome == .copied ? Color.accentColor : Color.green)
                .transition(.scale(scale: 0.8).combined(with: .opacity))

        case .failed:
            Label("action.text_replacement.preview.failed", systemSymbol: .exclamationmarkTriangleFill)
                .font(TranslationCardStyle.captionFont)
                .foregroundStyle(.orange)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var content: some View {
        if case let .failed(message) = model.phase {
            Text(message)
                .font(TranslationCardStyle.placeholderFont)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.text.isEmpty {
            LoadingLines(widths: [nil, 180])
        } else {
            if let maximumHeight = model.layout.maximumContentHeight {
                ScrollView {
                    translatedText
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
                            }
                        }
                }
                .frame(height: min(maximumHeight, model.contentHeight))
                .onPreferenceChange(ContentHeightKey.self) { height in
                    let roundedHeight = ceil(height)
                    if model.contentHeight != roundedHeight {
                        model.contentHeight = roundedHeight
                    }
                }
            } else {
                translatedText
            }
        }
    }

    private var translatedText: some View {
        Group {
            if model.layout.maximumContentHeight != nil {
                MathText(text: model.text, fontSize: model.layout.fontSize, paragraphSpacing: 8)
            } else {
                // Write-back previews show the text exactly as it will be inserted.
                Text(model.text)
                    .lineLimit(model.layout.maxLines)
                    // Compact write-back previews show the latest words while streaming.
                    .truncationMode(model.phase == .processing ? .head : .tail)
            }
        }
        .font(.system(size: model.layout.fontSize))
        .foregroundStyle(.primary)
        .lineSpacing(model.layout.fontSize * 0.25)
        .fixedSize(horizontal: false, vertical: true)
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
