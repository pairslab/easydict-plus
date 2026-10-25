//
//  MathText.swift
//  Easydict
//
//  Created by chenyinuo on 2026/10/25.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import SwiftMath
import SwiftUI

// MARK: - MathText

/// Text with LaTeX math rendered: `$…$` and `\(…\)` inline, `$$…$$` and `\[…\]` centered on their own lines.
///
/// Every line break starts a new paragraph, so plain text lays out exactly as one `Text` per line.
/// Math that does not parse, or a delimiter that is still open while a result streams, stays as written.
struct MathText: View {
    // MARK: Internal

    let text: String
    let fontSize: CGFloat
    let paragraphSpacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: paragraphSpacing) {
            ForEach(Array(MathMarkup.lines(in: text).enumerated()), id: \.offset) { _, line in
                switch line {
                case let .text(pieces):
                    inlineText(pieces)
                        .frame(minHeight: pieces.isEmpty ? fontSize : nil, alignment: .leading)
                case let .display(latex, source):
                    displayMath(latex, source: source)
                }
            }
        }
    }

    // MARK: Private

    @ViewBuilder
    private func displayMath(_ latex: String, source: String) -> some View {
        if let rendering = MathRenderer.rendering(of: latex, fontSize: fontSize, isDisplay: true) {
            // Shrinks a formula wider than the card instead of clipping it.
            Image(nsImage: rendering.image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: rendering.image.size.width)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
        } else {
            Text(verbatim: source)
        }
    }

    private func inlineText(_ pieces: [MathMarkup.Piece]) -> Text {
        pieces.reduce(Text(verbatim: "")) { text, piece in
            switch piece {
            case let .text(string):
                return text + Text(verbatim: string)
            case let .math(latex, source):
                guard let rendering = MathRenderer.rendering(of: latex, fontSize: fontSize, isDisplay: false) else {
                    return text + Text(verbatim: source)
                }
                // Inline images sit on the baseline; lower the formula so its own baseline lines up.
                return text + Text(Image(nsImage: rendering.image).renderingMode(.template))
                    .baselineOffset(-rendering.descent)
            }
        }
    }
}

// MARK: - MathMarkup

/// Splits text into lines of plain text and math.
///
/// A single `$` follows Pandoc's rules so prices are left alone: the opening `$` is not followed by
/// whitespace, the closing `$` is not preceded by whitespace nor followed by a digit, and inline math
/// does not cross a line break.
enum MathMarkup {
    // MARK: Internal

    enum Piece: Equatable {
        case text(String)
        /// `source` is the math as written, delimiters included, shown when it cannot be rendered.
        case math(latex: String, source: String)
    }

    enum Line: Equatable {
        case text([Piece])
        case display(latex: String, source: String)
    }

    static func lines(in text: String) -> [Line] {
        var lines: [Line] = []
        var current: [Piece] = []
        // A display formula ends its line, so the break right after it does not add an empty line.
        var isLineOpen = true

        for token in tokens(in: text) {
            switch token {
            case let .text(string):
                for (index, part) in string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                    .enumerated() {
                    if index > 0 {
                        if isLineOpen {
                            lines.append(.text(current))
                        }
                        current = []
                        isLineOpen = true
                    }
                    if !part.isEmpty {
                        current.append(.text(String(part)))
                        isLineOpen = true
                    }
                }
            case let .inline(latex, source):
                current.append(.math(latex: latex, source: source))
                isLineOpen = true
            case let .display(latex, source):
                if !current.isEmpty {
                    lines.append(.text(current))
                }
                current = []
                lines.append(.display(latex: latex, source: source))
                isLineOpen = false
            }
        }
        if isLineOpen {
            lines.append(.text(current))
        }
        return lines
    }

    // MARK: Private

    private enum Token {
        case text(String)
        case inline(latex: String, source: String)
        case display(latex: String, source: String)
    }

    private static func tokens(in text: String) -> [Token] {
        guard text.contains("$") || text.contains("\\(") || text.contains("\\[") else {
            return [.text(text)]
        }

        var tokens: [Token] = []
        var plain = ""
        var index = text.startIndex

        func flushPlain() {
            if !plain.isEmpty {
                tokens.append(.text(plain))
                plain = ""
            }
        }

        while index < text.endIndex {
            let rest = text[index...]
            if rest.hasPrefix("\\$") {
                plain.append("$")
                index = text.index(index, offsetBy: 2)
                continue
            }
            if let (math, end) = delimited(rest, open: "$$", close: "$$")
                ?? delimited(rest, open: "\\[", close: "\\]") {
                flushPlain()
                tokens.append(.display(latex: math, source: String(text[index ..< end])))
                index = end
                continue
            }
            if let (math, end) = delimited(rest, open: "\\(", close: "\\)") ?? dollarMath(rest) {
                flushPlain()
                tokens.append(.inline(latex: math, source: String(text[index ..< end])))
                index = end
                continue
            }
            plain.append(text[index])
            index = text.index(after: index)
        }
        flushPlain()
        return tokens
    }

    /// Math between `open` at the start of `text` and the next `close`, with the index after `close`.
    private static func delimited(_ text: Substring, open: String, close: String) -> (String, String.Index)? {
        guard text.hasPrefix(open) else {
            return nil
        }
        let contentStart = text.index(text.startIndex, offsetBy: open.count)
        guard let closeRange = text[contentStart...].range(of: close) else {
            return nil
        }
        let math = text[contentStart ..< closeRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return math.isEmpty ? nil : (math, closeRange.upperBound)
    }

    /// Inline math opened by a single `$` at the start of `text`, following Pandoc's rules.
    private static func dollarMath(_ text: Substring) -> (String, String.Index)? {
        guard text.first == "$" else {
            return nil
        }
        let contentStart = text.index(after: text.startIndex)
        guard contentStart < text.endIndex, !text[contentStart].isWhitespace, text[contentStart] != "$" else {
            return nil
        }
        var index = contentStart
        while index < text.endIndex {
            let character = text[index]
            if character.isNewline {
                return nil
            }
            if character == "\\" {
                // Skip the escaped character, such as `\$` inside the formula.
                index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if character == "$" {
                let previous = text[text.index(before: index)]
                let next = text.index(after: index)
                if !previous.isWhitespace, next == text.endIndex || !text[next].isNumber {
                    return (String(text[contentStart ..< index]), next)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

// MARK: - MathRenderer

/// Renders LaTeX to template images, which take the color of the surrounding text, and caches them.
@MainActor
enum MathRenderer {
    // MARK: Internal

    struct Rendering {
        let image: NSImage
        /// Depth of the formula below its baseline.
        let descent: CGFloat
    }

    /// The rendering of `latex`, or nil when it does not parse.
    static func rendering(of latex: String, fontSize: CGFloat, isDisplay: Bool) -> Rendering? {
        let key = "\(isDisplay ? "display" : "inline")|\(fontSize)|\(latex)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.rendering
        }

        var mathImage = MathImage(
            latex: latex,
            fontSize: fontSize,
            textColor: .black,
            labelMode: isDisplay ? .display : .text,
            textAlignment: .left
        )
        let (error, image, layout) = mathImage.asImage()
        var rendering: Rendering?
        if error == nil, let image, let layout, image.size.width > 0, image.size.height > 0 {
            image.isTemplate = true
            rendering = Rendering(image: image, descent: layout.descent)
        } else {
            logInfo("Math rendering failed: \(error?.localizedDescription ?? "empty formula")")
        }
        cache.setObject(CachedRendering(rendering), forKey: key)
        return rendering
    }

    // MARK: Private

    /// Also remembers failures, so a streaming result does not parse broken math on every update.
    private final class CachedRendering {
        // MARK: Lifecycle

        init(_ rendering: Rendering?) {
            self.rendering = rendering
        }

        // MARK: Internal

        let rendering: Rendering?
    }

    private static let cache: NSCache<NSString, CachedRendering> = {
        let cache = NSCache<NSString, CachedRendering>()
        cache.countLimit = 300
        return cache
    }()
}
