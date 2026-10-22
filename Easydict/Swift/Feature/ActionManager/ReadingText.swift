//
//  ReadingText.swift
//  Easydict
//
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation

/// Keeps selection structure outside translation requests so models cannot merge separate blocks.
struct ReadingText {
    // MARK: Lifecycle

    init(_ text: String) {
        // Some AX clients concatenate list items as "sentence.• next item". Only restore boundaries
        // supported by sentence punctuation and a bullet, never ordinary periods or multiplication dots.
        source = text.replacingOccurrences(
            of: #"(?<=[.!?。！？;；])[\t ]*(?=[•●▪◦‣][\t ]+\S)"#,
            with: "\n",
            options: .regularExpression
        )

        var start = source.startIndex
        while start < source.endIndex {
            let end = source[start...].firstIndex(where: \.isNewline) ?? source.endIndex
            appendLine(String(source[start ..< end]))
            guard end < source.endIndex else { break }
            start = source.index(after: end)
            pieces.append(.literal(String(source[end ..< start])))
        }
    }

    // MARK: Internal

    struct Segment {
        let text: String
        let prefix: String
        let suffix: String
    }

    let source: String
    private(set) var segments: [Segment] = []

    /// Restores exact separators, indentation and list markers in source order, including while streaming.
    func formatted(_ translations: [String]) -> String {
        pieces.map { piece in
            switch piece {
            case let .literal(text):
                return text
            case let .segment(index):
                let text = translations[index].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return "" }
                let segment = segments[index]
                return segment.prefix + text + segment.suffix
            }
        }.joined()
    }

    // MARK: Private

    private enum Piece {
        case literal(String)
        case segment(Int)
    }

    private var pieces: [Piece] = []

    private mutating func appendLine(_ line: String) {
        guard let first = line.firstIndex(where: { !$0.isWhitespace }),
              let last = line.lastIndex(where: { !$0.isWhitespace }) else {
            pieces.append(.literal(line))
            return
        }
        let end = line.index(after: last)
        var content = String(line[first ..< end])
        var prefix = String(line[..<first])
        if let marker = content.range(
            of: #"^(?:[•●▪◦‣⁃*+\-]|\d+[.)]|[A-Za-z][.)]|#{1,6})[\t ]+"#,
            options: .regularExpression
        ) {
            prefix += content[marker]
            content.removeSubrange(marker)
        }
        pieces.append(.segment(segments.count))
        segments.append(Segment(text: content, prefix: prefix, suffix: String(line[end...])))
    }
}
