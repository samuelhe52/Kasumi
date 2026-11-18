import CHyphenation
import Foundation

/// Dictionary opportunities in the original block's UTF8 coordinates. The
/// segmentation and scalar-wise case mapping follow the native paragraph
/// frontend; dictionary storage and Liang scoring live in the pinned bridge.
enum ParagraphHyphenation {
    static func opportunities(in text: String, language: String = "auto") -> Set<Int> {
        guard let selection = Selection(language) else { return [] }
        var result = Set<Int>()
        var word = String.UnicodeScalarView()
        var wordLength = 0
        var rejectedWord = false
        var wordStart = 0
        var position = 0
        let tag = Array(selection.tag.utf8)
        func flush() {
            if wordLength >= 2 + selection.rightMinimum {
                for offset in breaks(in: word, tag: tag) { result.insert(wordStart + offset) }
            }
            if wordLength > 0 {
                word = String.UnicodeScalarView()
                wordLength = 0
            }
            rejectedWord = false
        }
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let ascii = asciiLetter(value)
            let belongs =
                ascii
                || (!selection.automatic
                    && (value < 128 ? (48...57).contains(value) : scalar.properties.isAlphabetic || combining(value)))
            if belongs {
                if !rejectedWord {
                    if selection.accepts(value, ascii: ascii) {
                        if wordLength == 0 { wordStart = position }
                        word.append(scalar)
                        wordLength += 1
                    } else {
                        // An unsupported scalar invalidates the whole word.
                        // Skip the rest without allocating a copy of that run.
                        rejectedWord = true
                        word = String.UnicodeScalarView()
                        wordLength = 0
                    }
                }
            } else {
                flush()
            }
            position += scalar.utf8.count
        }
        flush()
        return result
    }

    private struct Selection {
        let tag: String
        let automatic: Bool
        let russian: Bool
        let rightMinimum: Int
        init?(_ name: String) {
            let normalized = name.lowercased()
            automatic = normalized == "auto"
            switch normalized {
            case "auto", "en-us": tag = "en-us"
            case "en-gb": tag = "en-gb"
            case "de", "de-1996": tag = "de-1996"
            case "fr", "es", "it", "pt", "nl", "sv", "da", "nb", "fi", "pl", "cs", "ru": tag = normalized
            default: return nil
            }
            russian = tag == "ru"
            rightMinimum = ["en-us", "en-gb", "pt", "cs"].contains(tag) ? 3 : 2
        }

        func accepts(_ value: UInt32, ascii: Bool) -> Bool {
            if value < 128 { return ascii && !russian }
            if russian { return (0x0400...0x04FF).contains(value) }
            return (0x00C0...0x024F).contains(value) || (0x1E00...0x1EFF).contains(value)
        }
    }

    private static func asciiLetter(_ value: UInt32) -> Bool {
        (65...90).contains(value) || (97...122).contains(value)
    }

    private static func combining(_ value: UInt32) -> Bool {
        (0x0300...0x036F).contains(value) || (0x1AB0...0x1AFF).contains(value) || (0x1DC0...0x1DFF).contains(value)
            || (0x20D0...0x20FF).contains(value) || (0xFE20...0xFE2F).contains(value)
    }

    private static func breaks(in word: String.UnicodeScalarView, tag: [UInt8]) -> [Int] {
        var lowercase = String()
        var sourceOffset = 0
        var lowerOffset = 0
        var sourceBoundaries = [0: 0]
        for scalar in word {
            let mapped = String(scalar).lowercased()
            // Native rejects expanding case maps (notably capital dotted I).
            guard mapped.unicodeScalars.count == 1 else { return [] }
            lowercase += mapped
            sourceOffset += scalar.utf8.count
            lowerOffset += mapped.utf8.count
            sourceBoundaries[lowerOffset] = sourceOffset
        }
        let bytes = Array(lowercase.utf8)
        return bytes.withUnsafeBufferPointer { input in
            tag.withUnsafeBufferPointer { language in
                let required = kasumi_hyphenate(
                    input.baseAddress, input.count, language.baseAddress, language.count, nil, 0)
                guard let count = Int(exactly: required), count > 0, count < input.count else { return [] }
                var output = [Int](repeating: 0, count: count)
                let written = output.withUnsafeMutableBufferPointer {
                    kasumi_hyphenate(
                        input.baseAddress, input.count, language.baseAddress, language.count, $0.baseAddress, $0.count)
                }
                guard Int(exactly: written) == count else { return [] }
                return output.compactMap { offset in
                    guard offset > 0, offset < lowerOffset, let original = sourceBoundaries[offset] else { return nil }
                    return original
                }
            }
        }
    }
}
