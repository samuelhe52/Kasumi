import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import KasumiMarkdown

fileprivate func paintedGlyph(in line: ShapedLine, at index: Int) throws -> (CTFont, CGGlyph, CGPoint) {
    for fragment in line.fragments {
        for run in CTLineGetGlyphRuns(fragment.line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var indices = [CFIndex](repeating: 0, count: count)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            guard let slot = indices.firstIndex(of: index) else { continue }
            let values = CTRunGetAttributes(run) as NSDictionary
            let value = try #require(values[kCTFontAttributeName])
            let font = value as! CTFont
            return (
                font, glyphs[slot],
                CGPoint(
                    x: line.origin.x + fragment.x + fragment.drawOffset - fragment.glyphInset + positions[slot].x,
                    y: line.origin.y - positions[slot].y)
            )
        }
    }
    throw NSError(domain: "Missing painted test glyph", code: index)
}

/// Independent reference using point-in-outline queries, not the production
/// control-polygon clipping. Dense sampling bounds its error to 0.004 em.
fileprivate func sampledContour(_ path: CGPath, band: ClosedRange<CGFloat>, em: CGFloat) -> ClosedRange<CGFloat>? {
    let step = em * 0.002
    let box = path.boundingBoxOfPath
    var left = CGFloat.infinity
    var right = -CGFloat.infinity
    for y in stride(from: band.lowerBound - em * 0.06, through: band.upperBound + em * 0.06, by: step) {
        for x in stride(from: box.minX, through: box.maxX, by: step) {
            if path.contains(CGPoint(x: x, y: -y)) {
                left = min(left, x)
                right = max(right, x)
            }
        }
    }
    return left <= right ? (left - em * 0.06)...(right + em * 0.06) : nil
}

@Suite struct UnderlineClearanceTests {
    @Test(arguments: ["p", "g"], [16.0, 32.0, 64.0])
    func descenderGapsFollowContourRatherThanCharacterAdvance(letter: String, size: Double) throws {
        let source = "aa \(letter) aa"
        let style = Typography().applying(ProfileValues([.baseSize: .number(size)]))
        let document = DocumentParser.parse("[\(source)](#target)")
        let layout = DocumentTypesetter.layout(document, width: 800, style: style)
        let paragraph = try #require(layout.paragraphs.first).paragraph
        let line = try #require(paragraph.lines.first)
        let index = (paragraph.attributed.string as NSString).range(of: letter).location
        let (font, glyph, position) = try paintedGlyph(in: line, at: index)
        let em = CTFontGetSize(font)
        let path = try #require(CTFontCreatePathForGlyph(font, glyph, nil))
        let top = line.origin.y + style.size * 0.185
        let bottom = top + max(0.5, style.size * 0.07)
        let sampled = try #require(sampledContour(path, band: (top - position.y)...(bottom - position.y), em: em))
        let parts = paragraph.underlines
        #expect(parts.count == 2)
        let before = try #require(parts.first)
        let after = try #require(parts.last)
        // Control polygons enclose their curves, so the cut may exceed the
        // sampled outline slightly but must never cut into it.
        let leftExcess = sampled.lowerBound - (before.rect.maxX - position.x)
        let rightExcess = after.rect.minX - position.x - sampled.upperBound
        #expect(leftExcess > -em * 0.004 && leftExcess < em * 0.01)
        #expect(rightExcess > -em * 0.004 && rightExcess < em * 0.01)
        #expect(before.rect.maxX < after.rect.minX)
        #expect(before.rect.minX == line.origin.x)
        #expect(abs(after.rect.maxX - line.origin.x - line.width) < 0.001)
        // The gap must retain the glyph's actual contour plus breathing room,
        // not suppress an arbitrary whole word or the glyph's advance box.
        #expect(after.rect.minX - before.rect.maxX < em)
    }

    @Test func clearanceDoesNotRestartFileLinkDashPhase() throws {
        let style = Typography().applying(ProfileValues([.baseSize: .number(32)]))
        let layout = DocumentTypesetter.layout(
            DocumentParser.parse("[aa p aa g aa](LinkJumps.md)"), width: 800, style: style)
        let paragraph = try #require(layout.paragraphs.first).paragraph
        let line = try #require(paragraph.lines.first)
        let period: CGFloat = 32 * 0.45
        let dash: CGFloat = 32 * 0.3
        for paint in paragraph.underlines {
            // Clipped pieces may start partway through a dash, but no ink may
            // occupy the original grid's gaps after a descender is removed.
            let start = paint.rect.minX - line.origin.x
            let end = paint.rect.maxX - line.origin.x
            let cell = floor((start + 0.0001) / period)
            #expect(start >= cell * period - 0.001)
            #expect(end <= cell * period + dash + 0.001)
        }
        #expect(paragraph.underlines.contains { $0.rect.minX > line.origin.x + period * 3 })
    }
}
