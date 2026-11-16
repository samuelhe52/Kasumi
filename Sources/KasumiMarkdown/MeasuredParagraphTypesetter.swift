import CoreText
import Foundation

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

enum MeasuredParagraphTypesetter {
    static func layout(
        _ attributed: NSAttributedString, width: CGFloat, fontSize: CGFloat, lineSpacing: CGFloat,
        alignment: ParagraphAlignment, indent: CGFloat, profileValues: ProfileValues?, outerWidth: CGFloat?,
        baseEm: CGFloat?
    ) -> ParagraphLayout {
        let input = ParagraphShaper.shape(attributed, fallbackSize: fontSize)
        let options = profileValues.map(ParagraphProfileOptions.init(values:)) ?? .init()
        let result = ParagraphEngine.layout(
            clusters: input.clusters, runs: input.metrics, width: Float(width),
            outerWidth: Float(outerWidth ?? width), baseEm: Float(baseEm ?? fontSize),
            alignment: alignment == .trailing ? .leading : alignment, indent: Float(indent), options: options)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let source = attributed.string as NSString
        func sourceRange(_ clusters: Range<Int>) -> NSRange {
            guard let first = input.ranges[safe: clusters.lowerBound], !clusters.isEmpty,
                let last = input.ranges[safe: clusters.upperBound - 1]
            else {
                return NSRange(
                    location: input.ranges[safe: clusters.lowerBound]?.location ?? attributed.length, length: 0)
            }
            return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        }
        // A line cut from the paragraph typesetter sees its neighbors, and Core Text
        // adds its own CJK-Latin space (1/8 em after `。`, for example) before the
        // first glyph. The engine already spaced the fragment, so that inset is removed.
        func leadingGlyphInset(_ line: CTLine) -> CGFloat {
            guard let run = (CTLineGetGlyphRuns(line) as! [CTRun]).first, CTRunGetGlyphCount(run) > 0 else { return 0 }
            var position = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
            return max(0, position.x)
        }
        func textLine(_ range: NSRange) -> CTLine {
            range.length == 0
                ? CTLineCreateWithAttributedString(NSAttributedString(string: ""))
                : CTTypesetterCreateLine(typesetter, CFRange(location: range.location, length: range.length))
        }
        var lines: [ShapedLine] = []
        var y: CGFloat = 0
        for selected in result.lines {
            let range = sourceRange(selected.clusterRange)
            var fragments: [ShapedFragment] = []
            for fragment in selected.fragments {
                var x = fragment.x
                func append(_ clusters: Range<Int>, width: Float) {
                    let range = sourceRange(clusters)
                    // A shaping span may contain a ligature. Keep its interior
                    // grapheme carets even though line breaking treats it atomically.
                    var boundaries: [Int] = []
                    var boundary = range.location
                    while boundary < NSMaxRange(range) {
                        boundaries.append(boundary)
                        boundary = NSMaxRange(source.rangeOfComposedCharacterSequence(at: boundary))
                    }
                    if range.length > 0 { boundaries.append(NSMaxRange(range)) }
                    let line = textLine(range)
                    fragments.append(
                        ShapedFragment(
                            range: range, line: line, x: CGFloat(x), width: CGFloat(width),
                            drawOffset: CGFloat(fragment.drawDx), glyphInset: leadingGlyphInset(line),
                            capsuleLeft: clusters.lowerBound == fragment.clusterRange.lowerBound
                                ? CGFloat(fragment.capsuleLeft) : 0,
                            capsuleRight: clusters.upperBound == fragment.clusterRange.upperBound
                                ? CGFloat(fragment.capsuleRight) : 0,
                            boundaries: boundaries))
                    x += width
                }
                guard fragment.clusterRange.count > 1 else {
                    append(fragment.clusterRange, width: fragment.width)
                    continue
                }
                // The engine may coalesce an unbreakable mixed-script box such
                // as `线“感`. Core Text adds internal spacing absent from its
                // glyph advances; isolate Han at the measured cluster positions.
                var start = fragment.clusterRange.lowerBound
                var width: Float = 0
                for index in fragment.clusterRange {
                    let cluster = input.clusters[index]
                    if cluster.text.first.map(CJKFontRole.usesHanFont) == true {
                        if start < index { append(start..<index, width: width) }
                        append(index..<(index + 1), width: cluster.advance)
                        start = index + 1
                        width = 0
                    } else {
                        width += cluster.advance
                    }
                }
                if start < fragment.clusterRange.upperBound {
                    append(start..<fragment.clusterRange.upperBound, width: fragment.width - (x - fragment.x))
                }
            }
            let logical = textLine(range)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(logical, &ascent, &descent, nil)
            var hyphen: ShapedHyphen?
            if let x = selected.hyphenX, let run = selected.hyphenRun, input.fonts.indices.contains(run) {
                let source = input.clusters.firstIndex(where: { $0.run == run }).flatMap {
                    input.ranges[safe: $0]?.location
                }
                let color =
                    source.flatMap {
                        attributed.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? PlatformColor
                    } ?? .black
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(string: "-", attributes: [.font: input.fonts[run], .foregroundColor: color]))
                hyphen = ShapedHyphen(
                    line: line, x: CGFloat(x), width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            }
            let used = max(fragments.map { $0.x + $0.width }.max() ?? 0, hyphen.map { $0.x + $0.width } ?? 0)
            let baseline = y + max(ascent, fontSize)
            let offset = alignment == .trailing ? max(0, width - used) : 0
            lines.append(
                ShapedLine(
                    range: range, line: logical, origin: CGPoint(x: offset, y: baseline), ascent: ascent,
                    descent: descent, width: used, fragments: fragments, hyphen: hyphen,
                    adjustmentRatio: selected.storedRatio))
            // Font line gap is ignored: line spacing is explicit, and fallback faces
            // such as Hiragino carry a half-em gap that made their lines taller.
            y = max(y + fontSize * lineSpacing, baseline + descent)
        }
        return ParagraphLayout(
            attributed: attributed, lines: lines, height: y, autoRagged: result.autoRagged,
            diagnostics: result.diagnostics.map(\.rawValue))
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
