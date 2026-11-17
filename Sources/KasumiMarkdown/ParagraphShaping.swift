import CoreText
import Foundation

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

extension NSAttributedString.Key {
    static let kasumiParagraphRun = NSAttributedString.Key("KasumiParagraphRun")
}

/// One record per original inline run, before Han/SimSong font substitutions.
/// Core spacing uses this Latin/base font's em, not each glyph's font size.
final class ParagraphRunStyle: NSObject {
    let baseFont: CTFont
    let hanFont: CTFont?
    let punctuationFont: CTFont?
    let flags: UInt32
    let isCode: Bool
    init(
        baseFont: PlatformFont, hanFont: PlatformFont? = nil, punctuationFont: PlatformFont? = nil, flags: UInt32,
        isCode: Bool
    ) {
        self.baseFont = baseFont as CTFont
        self.hanFont = hanFont.map { $0 as CTFont }
        self.punctuationFont = punctuationFont.map { $0 as CTFont }
        self.flags = flags
        self.isCode = isCode
    }
}

extension InlineRun {
    var paragraphFlags: UInt32 {
        var flags: UInt32 = 0
        if traits.contains(.strong) { flags |= 1 }
        if traits.contains(.emphasis) { flags |= 2 }
        if traits.contains(.code) { flags |= 4 }
        if traits.contains(.link) { flags |= 8 }
        if traits.contains(.footnote) { flags |= 0x10 }
        if traits.contains(.image) { flags |= 0x20 }
        if traits.contains(.math) { flags |= 0x40 }
        return flags
    }
}

struct ShapedParagraphInput {
    /// Whole graphemes, coalesced when one shaped glyph consumes several.
    var clusters: [ParagraphInputCluster]
    var ranges: [NSRange]
    var metrics: [ParagraphRunMetrics]
    var fonts: [CTFont]
}

enum ParagraphShaper {
    static func shape(_ attributed: NSAttributedString, fallbackSize: CGFloat) -> ShapedParagraphInput {
        var result = ShapedParagraphInput(clusters: [], ranges: [], metrics: [], fonts: [])
        var measurements: [(advance: CGFloat, hasGlyph: Bool, preserveAdvance: Bool)] = []
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.kasumiParagraphRun, in: full) { value, range, _ in
            let style = value as? ParagraphRunStyle
            let font =
                style?.baseFont
                ?? ((attributed.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont
                    ?? .systemFont(ofSize: fallbackSize)) as CTFont)
            let runIndex = result.metrics.count
            result.metrics.append(
                ParagraphRunMetrics(
                    spaceAdvance: Float(advance(" ", font: font)), hyphenAdvance: Float(advance("-", font: font)),
                    em: Float(CTFontGetSize(font)), isCode: style?.isCode ?? false, flags: style?.flags ?? 0))
            result.fonts.append(font)
            let substring = attributed.attributedSubstring(from: range)
            let line = CTLineCreateWithAttributedString(substring)
            var starts: [Int] = []
            var clusterIndices: [Int?] = []
            var offset = 0
            for character in substring.string {
                let text = String(character)
                let length = text.utf16.count
                let global = NSRange(location: range.location + offset, length: length)
                starts.append(offset)
                // Legacy capsule spacers remain in attributed storage for its
                // semantic map; native input clusters exclude synthetic padding.
                let synthetic =
                    substring.attribute(.kasumiSemanticText, at: offset, effectiveRange: nil) as? String == ""
                    && text == "\u{FFFC}"
                if synthetic {
                    clusterIndices.append(nil)
                } else {
                    clusterIndices.append(result.clusters.count)
                    result.clusters.append(ParagraphInputCluster(text: text, run: runIndex, advance: 0))
                    result.ranges.append(global)
                    let preserveAdvance = text.unicodeScalars.contains { scalar in
                        switch scalar.properties.generalCategory {
                        case .nonspacingMark, .spacingMark, .enclosingMark:
                            return !scalar.properties.isVariationSelector
                        default: return false
                        }
                    }
                    // Fallback mark runs can overlap their base run. Caret
                    // boundaries measure the whole grapheme without double-counting.
                    let advance =
                        preserveAdvance
                        ? abs(
                            CTLineGetOffsetForStringIndex(line, offset + length, nil)
                                - CTLineGetOffsetForStringIndex(line, offset, nil))
                        : 0
                    measurements.append((advance, false, preserveAdvance))
                }
                offset += length
            }
            var scalarAt: [Int: UInt32] = [:]
            var scalarOffset = 0
            for scalar in substring.string.unicodeScalars {
                scalarAt[scalarOffset] = scalar.value
                scalarOffset += scalar.value > 0xffff ? 2 : 1
            }
            for glyphRun in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(glyphRun)
                var advances = [CGSize](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetAdvances(glyphRun, CFRange(location: 0, length: 0), &advances)
                CTRunGetStringIndices(glyphRun, CFRange(location: 0, length: 0), &indices)
                let attributes = CTRunGetAttributes(glyphRun) as NSDictionary
                let actualFont = (attributes[kCTFontAttributeName] as! CTFont?) ?? font
                for glyph in 0..<count {
                    let index = indices[glyph]
                    guard index >= 0, index < substring.length else { continue }
                    var lower = 0
                    var upper = starts.count
                    while lower < upper {
                        let middle = (lower + upper) / 2
                        if starts[middle] <= index { lower = middle + 1 } else { upper = middle }
                    }
                    guard lower > 0, let cluster = clusterIndices[lower - 1] else { continue }
                    measurements[cluster].hasGlyph = true
                    guard !measurements[cluster].preserveAdvance else { continue }
                    let scalar = scalarAt[index]
                    let normalized =
                        scalar.map {
                            normalizesToEm(
                                $0, font: actualFont, han: style?.hanFont, punctuation: style?.punctuationFont)
                        } ?? false
                    let padding = (attributes[NSAttributedString.Key.kasumiPunctuationPadding] as? CGFloat) ?? 0
                    let width = normalized ? CTFontGetSize(actualFont) + padding : advances[glyph].width
                    measurements[cluster].advance += width
                }
            }
        }
        // Ligatures charge their advance to the first source grapheme. Absorb
        // the consumed graphemes so neither hyphenation nor emergency breaking
        // can split and reshape only part of that glyph.
        var count = 0
        for index in result.clusters.indices {
            let cluster = result.clusters[index]
            let range = result.ranges[index]
            let advance = Float(measurements[index].advance)
            if !measurements[index].hasGlyph, count > 0,
                result.clusters[count - 1].run == cluster.run,
                NSMaxRange(result.ranges[count - 1]) == range.location
            {
                result.clusters[count - 1].text += cluster.text
                result.clusters[count - 1].advance += advance
                result.ranges[count - 1].length += range.length
            } else {
                result.clusters[count] = cluster
                result.clusters[count].advance = advance
                result.ranges[count] = range
                count += 1
            }
        }
        result.clusters.removeSubrange(count...)
        result.ranges.removeSubrange(count...)
        return result
    }

    static func normalizesToEm(_ scalar: UInt32, font: CTFont, han: CTFont?, punctuation: CTFont?) -> Bool {
        if (0x3400...0x4dbf).contains(scalar) || (0x4e00...0x9fff).contains(scalar)
            || (0xf900...0xfaff).contains(scalar) || (0x20000...0x3ffff).contains(scalar)
        {
            return true
        }
        guard !(0x302a...0x302f).contains(scalar),
            han.map({ CFEqual(font, $0) }) == true || punctuation.map({ CFEqual(font, $0) }) == true
        else { return false }
        return (0x3000...0x303f).contains(scalar) || (0xff01...0xff60).contains(scalar)
            || (0xffe0...0xffe6).contains(scalar)
    }

    private static func advance(_ string: String, font: CTFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        var width: CGFloat = 0
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            var advances = [CGSize](repeating: .zero, count: CTRunGetGlyphCount(run))
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            width += advances.reduce(0) { $0 + $1.width }
        }
        return width
    }
}
