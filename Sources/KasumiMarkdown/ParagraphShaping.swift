import AppKit
import CoreText
import Foundation

extension NSAttributedString.Key {
    static let kasumiParagraphRun = NSAttributedString.Key("KasumiParagraphRun")
}

/// One record per original inline run, before Han/SimSong font substitutions.
/// Core spacing uses this Latin/base font's em, not each glyph's font size.
final class ParagraphRunStyle: NSObject {
    let baseFont: NSFont
    let hanFont: NSFont?
    let punctuationFont: NSFont?
    let flags: UInt32
    let isCode: Bool
    init(baseFont: NSFont, hanFont: NSFont? = nil, punctuationFont: NSFont? = nil, flags: UInt32, isCode: Bool) {
        self.baseFont = baseFont; self.hanFont = hanFont; self.punctuationFont = punctuationFont
        self.flags = flags; self.isCode = isCode
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
    var clusters: [ParagraphInputCluster]
    var ranges: [NSRange]
    var metrics: [ParagraphRunMetrics]
    var fonts: [NSFont]
}

enum ParagraphShaper {
    static func shape(_ attributed: NSAttributedString, fallbackSize: CGFloat) -> ShapedParagraphInput {
        var result = ShapedParagraphInput(clusters: [], ranges: [], metrics: [], fonts: [])
        var accumulated: [CGFloat] = []
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.kasumiParagraphRun, in: full) { value, range, _ in
            let style = value as? ParagraphRunStyle
            let font = style?.baseFont ?? attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: fallbackSize)
            let runIndex = result.metrics.count
            result.metrics.append(ParagraphRunMetrics(spaceAdvance: Float(advance(" ", font: font)), hyphenAdvance: Float(advance("-", font: font)), em: Float(font.pointSize), isCode: style?.isCode ?? false, flags: style?.flags ?? 0))
            result.fonts.append(font)
            let substring = attributed.attributedSubstring(from: range)
            var starts: [Int] = [], clusterIndices: [Int?] = [], offset = 0
            for character in substring.string {
                let text = String(character), length = text.utf16.count
                let global = NSRange(location: range.location + offset, length: length)
                starts.append(offset)
                // Legacy capsule spacers remain in attributed storage for its
                // semantic map; native input clusters exclude synthetic padding.
                let synthetic = substring.attribute(.kasumiSemanticText, at: offset, effectiveRange: nil) as? String == "" && text == "\u{FFFC}"
                if synthetic { clusterIndices.append(nil) }
                else {
                    clusterIndices.append(result.clusters.count)
                    result.clusters.append(ParagraphInputCluster(text: text, run: runIndex, advance: 0))
                    result.ranges.append(global)
                    accumulated.append(0)
                }
                offset += length
            }
            let line = CTLineCreateWithAttributedString(substring)
            var scalarAt: [Int: UInt32] = [:], scalarOffset = 0
            for scalar in substring.string.unicodeScalars {
                scalarAt[scalarOffset] = scalar.value
                scalarOffset += scalar.value > 0xffff ? 2 : 1
            }
            for glyphRun in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(glyphRun)
                var advances = [CGSize](repeating: .zero, count: count), indices = [CFIndex](repeating: 0, count: count)
                CTRunGetAdvances(glyphRun, CFRange(location: 0, length: 0), &advances)
                CTRunGetStringIndices(glyphRun, CFRange(location: 0, length: 0), &indices)
                let attributes = CTRunGetAttributes(glyphRun) as NSDictionary
                let actualFont = attributes[kCTFontAttributeName] as? NSFont ?? font
                for glyph in 0..<count {
                    let index = indices[glyph]
                    guard index >= 0, index < substring.length else { continue }
                    var lower = 0, upper = starts.count
                    while lower < upper {
                        let middle = (lower + upper) / 2
                        if starts[middle] <= index { lower = middle + 1 } else { upper = middle }
                    }
                    guard lower > 0, let cluster = clusterIndices[lower - 1] else { continue }
                    let scalar = scalarAt[index]
                    let normalized = scalar.map { normalizesToEm($0, font: actualFont, han: style?.hanFont, punctuation: style?.punctuationFont) } ?? false
                    let width = normalized ? actualFont.pointSize : advances[glyph].width
                    accumulated[cluster] += width
                }
            }
        }
        for index in result.clusters.indices { result.clusters[index].advance = Float(accumulated[index]) }
        return result
    }

    static func normalizesToEm(_ scalar: UInt32, font: NSFont, han: NSFont?, punctuation: NSFont?) -> Bool {
        if (0x3400...0x4dbf).contains(scalar) || (0x4e00...0x9fff).contains(scalar) ||
            (0xf900...0xfaff).contains(scalar) || (0x20000...0x3ffff).contains(scalar) { return true }
        guard !(0x302a...0x302f).contains(scalar),
              han.map({ CFEqual(font, $0) }) == true || punctuation.map({ CFEqual(font, $0) }) == true else { return false }
        return (0x3000...0x303f).contains(scalar) || (0xff01...0xff60).contains(scalar) || (0xffe0...0xffe6).contains(scalar)
    }

    private static func advance(_ string: String, font: NSFont) -> CGFloat {
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
