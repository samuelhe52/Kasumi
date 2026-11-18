import CoreText
import Foundation

extension NSAttributedString.Key {
    static let kasumiOriginalPunctuation = NSAttributedString.Key("KasumiOriginalPunctuation")
    static let kasumiPunctuationPadding = NSAttributedString.Key("KasumiPunctuationPadding")
}

/// An opt-in, linear script/context policy. No recognizer or language model.
struct PunctuationPlan {
    let strategy: String
    let offsets: [[Int]]
    private struct Entry {
        let scalar: UInt32
        let run: Int
        let offset: Int
        /// 0: ignorable, 1: Han, 2: other letter, 3: digit, 4: opaque, 5: protected.
        let kind: UInt8
    }
    private static let replacements: [UInt32: UInt16] = [
        44: 0xFF0C, 46: 0x3002, 59: 0xFF1B, 58: 0xFF1A,
        33: 0xFF01, 63: 0xFF1F, 40: 0xFF08, 41: 0xFF09
    ]
    private static let protected: Set<InlineRun.Trait> = [.code, .math, .image, .link, .footnote]

    static func make(runs: [InlineRun], strategy: String) -> Self? {
        guard strategy == "fold" || strategy == "spacing" else { return nil }
        var entries: [Entry] = []
        var candidates: [Int] = []
        var hasHan = false
        for (runIndex, run) in runs.enumerated() {
            guard run.traits.isDisjoint(with: protected) else {
                entries.append(Entry(scalar: 0, run: runIndex, offset: 0, kind: 5))
                continue
            }
            var offset = 0
            for scalar in run.text.unicodeScalars {
                let value = scalar.value
                if value < 128 {
                    let kind: UInt8
                    switch value {
                    case 65...90, 97...122: kind = 2
                    case 48...57: kind = 3
                    case 9...13, 32, 33, 34, 35, 37...47, 58, 59, 63, 64, 91...93, 95, 123, 125: kind = 0
                    default: kind = 4
                    }
                    if replacements[value] != nil { candidates.append(entries.count) }
                    entries.append(Entry(scalar: value, run: runIndex, offset: offset, kind: kind))
                    offset += 1
                    continue
                }
                // Whole-paragraph veto is intentionally conservative. Han-only
                // Japanese is intrinsically ambiguous without explicit language data.
                if (0x3040...0x30FF).contains(value) || (0x31F0...0x31FF).contains(value)
                    || (0xFF65...0xFFDC).contains(value) || (0x1100...0x11FF).contains(value)
                    || (0x3130...0x318F).contains(value) || (0xA960...0xA97F).contains(value)
                    || (0xAC00...0xD7FF).contains(value) || (0x1B000...0x1B16F).contains(value)
                {
                    return nil
                }
                let kind: UInt8
                if (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value)
                    || (0xF900...0xFAFF).contains(value) || (0x20000...0x323AF).contains(value)
                {
                    kind = 1
                    hasHan = true
                } else if scalar.properties.numericType != nil {
                    kind = 3
                } else if scalar.properties.isAlphabetic {
                    kind = 2
                } else if scalar.properties.isWhitespace || isPunctuation(scalar) {
                    kind = 0
                } else {
                    kind = 4
                }
                if replacements[value] != nil { candidates.append(entries.count) }
                entries.append(Entry(scalar: value, run: runIndex, offset: offset, kind: kind))
                offset += value > 0xFFFF ? 2 : 1
            }
        }
        guard hasHan, !candidates.isEmpty else { return nil }
        // Nearest significant context is computed once in each direction, so
        // punctuation/whitespace chains cannot trigger quadratic rescanning.
        var preceding = [Int](repeating: -1, count: entries.count)
        var following = preceding
        var last = -1
        for index in entries.indices {
            preceding[index] = last
            if entries[index].kind != 0 { last = index }
        }
        last = -1
        for index in entries.indices.reversed() {
            following[index] = last
            if entries[index].kind != 0 { last = index }
        }
        var eligible = [Bool](repeating: false, count: entries.count)
        for index in candidates {
            let left = preceding[index]
            let right = following[index]
            if [44, 46, 58].contains(entries[index].scalar), left >= 0, right >= 0,
                entries[left].kind == 3, entries[right].kind == 3
            {
                continue
            }
            eligible[index] =
                (left >= 0 && index - left <= 16 && entries[left].kind == 1)
                || (right >= 0 && right - index <= 16 && entries[right].kind == 1)
        }
        // Matched parentheses transform together. Unbalanced/protected pairs stay
        // literal rather than producing mismatched half/full-width delimiters.
        var opens: [Int] = []
        var paired = Set<Int>()
        for index in entries.indices {
            if entries[index].kind == 5 { opens.removeAll(keepingCapacity: true) }
            if entries[index].scalar == 40 { opens.append(index) }
            if entries[index].scalar == 41, let open = opens.popLast() {
                let transform = eligible[open] || eligible[index]
                eligible[open] = transform
                eligible[index] = transform
                paired.insert(open)
                paired.insert(index)
            }
        }
        var offsets = [[Int]](repeating: [], count: runs.count)
        for index in candidates where eligible[index] {
            let entry = entries[index]
            if entry.scalar == 40 || entry.scalar == 41, !paired.contains(index) { continue }
            offsets[entry.run].append(entry.offset)
        }
        guard offsets.contains(where: { !$0.isEmpty }) else { return nil }
        return Self(strategy: strategy, offsets: offsets)
    }

    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .openPunctuation, .closePunctuation, .initialPunctuation, .finalPunctuation,
            .otherPunctuation, .dashPunctuation:
            true
        default: false
        }
    }

    func displayed(_ text: String, run: Int) -> String {
        guard strategy == "fold", !offsets[run].isEmpty else { return text }
        var units = Array(text.utf16)
        for offset in offsets[run] { units[offset] = Self.replacements[UInt32(units[offset])]! }
        return String(decoding: units, as: UTF16.self)
    }

    func markOriginals(in piece: NSMutableAttributedString, original: String, run: Int) {
        guard strategy == "fold" else { return }
        let source = original as NSString
        for offset in offsets[run] {
            piece.addAttribute(
                .kasumiOriginalPunctuation, value: source.substring(with: NSRange(location: offset, length: 1)),
                range: NSRange(location: offset, length: 1))
        }
    }

    static func addSpacing(to text: NSMutableAttributedString, at offsets: [Int]) {
        guard !offsets.isEmpty else { return }
        let source = text.string as NSString
        let selected = Set(offsets)
        func add(_ amount: CGFloat, at range: NSRange) {
            let old = text.attribute(.kern, at: range.location, effectiveRange: nil) as? CGFloat ?? 0
            let padding =
                text.attribute(.kasumiPunctuationPadding, at: range.location, effectiveRange: nil) as? CGFloat ?? 0
            text.addAttributes([.kern: old + amount, .kasumiPunctuationPadding: padding + amount], range: range)
        }
        for offset in offsets {
            let metadata = text.attribute(.kasumiParagraphRun, at: offset, effectiveRange: nil) as? ParagraphRunStyle
            let padding = (metadata.map { CTFontGetSize($0.baseFont) } ?? 16) / 8
            if offset > 0, !selected.contains(offset - 1) {
                let range = source.rangeOfComposedCharacterSequence(at: offset - 1)
                let before = source.substring(with: range)
                let prior =
                    text.attribute(.kasumiParagraphRun, at: range.location, effectiveRange: nil) as? ParagraphRunStyle
                if !before.unicodeScalars.allSatisfy(\.properties.isWhitespace), (prior?.flags ?? 0) & 0x7C == 0 {
                    add(padding, at: range)
                }
            }
            if offset + 1 < source.length, !selected.contains(offset + 1) {
                let range = source.rangeOfComposedCharacterSequence(at: offset + 1)
                if !source.substring(with: range).unicodeScalars.allSatisfy(\.properties.isWhitespace) {
                    add(padding, at: NSRange(location: offset, length: 1))
                }
            }
        }
    }
}
