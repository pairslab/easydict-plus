//
//  WordLookupCardView.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/21.
//  Copyright © 2026 izual. All rights reserved.
//

import SFSafeSymbols
import SwiftUI

// MARK: - WordLookupModel

/// Observable content of the dictionary card shown for the word under the pointer.
@MainActor
final class WordLookupModel: ObservableObject {
    // MARK: Lifecycle

    init(word: String) {
        self.word = word
    }

    // MARK: Internal

    struct Phonetic: Hashable {
        /// Short accent label such as 英 or 美.
        let label: String
        let value: String
    }

    struct Sense: Hashable {
        /// Part of speech such as n. or v., empty when the dictionary gives none.
        let partOfSpeech: String
        let meaning: String
    }

    let word: String

    @Published var phonetics: [Phonetic] = []
    @Published var senses: [Sense] = []
    @Published var isLoadingDictionary = true

    /// Whether the sentence around the word is known, so its meaning in context can be shown.
    @Published var hasContext = true
    /// What the word means in the sentence it was read in.
    @Published var contextualMeaning = ""
    @Published var isLoadingContext = true
}

// MARK: - WordLookupCardView

/// A glass popover with the word's pronunciation, dictionary senses, and its meaning in context.
/// Its arrow points at the word, like the system Look Up popover.
struct WordLookupCardView: View {
    // MARK: Internal

    /// Where the arrow sits on the card.
    struct Arrow: Equatable {
        var edge: VerticalEdge = .top
        /// Horizontal position of the arrow tip, measured from the card's leading edge.
        var tipX: CGFloat = 40
    }

    static let shadowInset = TranslationCardStyle.shadowInset
    static let arrowSize = CGSize(width: 18, height: 8)
    static let cardWidth: CGFloat = 320

    @ObservedObject var model: WordLookupModel

    var arrow = Arrow()

    var body: some View {
        VStack(alignment: .leading, spacing: TranslationCardStyle.sectionSpacing) {
            headword
            senses
            if model.hasContext {
                Divider()
                    .opacity(0.6)
                contextualMeaning
            }
        }
        .padding(.horizontal, TranslationCardStyle.horizontalPadding)
        .padding(.vertical, TranslationCardStyle.verticalPadding)
        .frame(width: Self.cardWidth, alignment: .leading)
        .padding(arrow.edge == .top ? .top : .bottom, Self.arrowSize.height)
        .translationCardChrome(in: cardShape)
        .animation(.easeOut(duration: 0.18), value: model.isLoadingDictionary)
        .animation(.easeOut(duration: 0.16), value: model.contextualMeaning)
    }

    // MARK: Private

    private var cardShape: PopoverShape {
        PopoverShape(arrow: arrow, arrowSize: Self.arrowSize, cornerRadius: TranslationCardStyle.cornerRadius)
    }

    /// The word with its pronunciations beside it, or below it when a long word leaves no room.
    private var headword: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                wordTitle
                phonetics
            }
            VStack(alignment: .leading, spacing: 4) {
                wordTitle
                phonetics
            }
        }
    }

    private var wordTitle: some View {
        Text(model.word)
            .font(.system(size: 20, weight: .semibold, design: .serif))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var phonetics: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ForEach(model.phonetics, id: \.self) { phonetic in
                HStack(spacing: 3) {
                    Text(phonetic.label)
                        .foregroundStyle(.tertiary)
                    Text("/\(phonetic.value)/")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .lineLimit(1)
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var senses: some View {
        if model.isLoadingDictionary {
            LoadingLines(widths: [220, 160])
        } else if model.senses.isEmpty {
            Text("word_lookup.no_definition")
                .font(TranslationCardStyle.placeholderFont)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.senses.prefix(4), id: \.self) { sense in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !sense.partOfSpeech.isEmpty {
                            Text(sense.partOfSpeech)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        Text(sense.meaning)
                            .font(TranslationCardStyle.bodyFont)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private var contextualMeaning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Label("word_lookup.in_context", systemSymbol: .sparkles)
                .labelStyle(.titleAndIcon)
                .font(TranslationCardStyle.captionFont)
                .foregroundStyle(Color.accentColor)
                .fixedSize()

            if model.contextualMeaning.isEmpty {
                if model.isLoadingContext {
                    LoadingLines(widths: [150])
                } else {
                    Text("word_lookup.no_context")
                        .font(TranslationCardStyle.placeholderFont)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(model.contextualMeaning)
                    .font(TranslationCardStyle.bodyFont)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - PopoverShape

/// A rounded rectangle with a small arrow on its top or bottom edge, leaving room for the
/// arrow inside the given rect.
struct PopoverShape: Shape {
    // MARK: Internal

    var arrow: WordLookupCardView.Arrow
    var arrowSize: CGSize
    var cornerRadius: CGFloat

    /// Traces the card and its arrow as one outline, so a stroke shows no seam at the arrow's base.
    func path(in rect: CGRect) -> Path {
        let isTop = arrow.edge == .top
        let body = CGRect(
            x: rect.minX,
            y: isTop ? rect.minY + arrowSize.height : rect.minY,
            width: rect.width,
            height: rect.height - arrowSize.height
        )
        let radius = min(cornerRadius, body.height / 2, body.width / 2)
        let halfWidth = arrowSize.width / 2
        // Keep the arrow clear of the rounded corners.
        let tipX = min(max(rect.minX + arrow.tipX, body.minX + radius + halfWidth), body.maxX - radius - halfWidth)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        if isTop {
            addArrow(to: &path, tipX: tipX, baseY: body.minY, tipY: rect.minY, forward: true)
        }
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.minY),
            tangent2End: CGPoint(x: body.maxX, y: body.minY + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.maxY),
            tangent2End: CGPoint(x: body.maxX - radius, y: body.maxY),
            radius: radius
        )
        if !isTop {
            addArrow(to: &path, tipX: tipX, baseY: body.maxY, tipY: rect.maxY, forward: false)
        }
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.maxY),
            tangent2End: CGPoint(x: body.minX, y: body.maxY - radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.minY),
            tangent2End: CGPoint(x: body.minX + radius, y: body.minY),
            radius: radius
        )
        path.closeSubpath()
        return path
    }

    // MARK: Private

    /// Adds a softly curved arrow along an edge; `forward` walks the edge left to right.
    private func addArrow(
        to path: inout Path,
        tipX: CGFloat,
        baseY: CGFloat,
        tipY: CGFloat,
        forward: Bool
    ) {
        let halfWidth = arrowSize.width / 2
        let direction: CGFloat = forward ? 1 : -1
        let start = tipX - halfWidth * direction
        let end = tipX + halfWidth * direction
        path.addLine(to: CGPoint(x: start, y: baseY))
        path.addQuadCurve(
            to: CGPoint(x: tipX, y: tipY),
            control: CGPoint(x: tipX - halfWidth * 0.35 * direction, y: tipY)
        )
        path.addQuadCurve(
            to: CGPoint(x: end, y: baseY),
            control: CGPoint(x: tipX + halfWidth * 0.35 * direction, y: tipY)
        )
    }
}
