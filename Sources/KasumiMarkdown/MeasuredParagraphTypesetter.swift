import AppKit
import CoreText
import Foundation

enum MeasuredParagraphTypesetter {
    static func layout(_ attributed: NSAttributedString, width: CGFloat, fontSize: CGFloat, lineSpacing: CGFloat,
                       alignment: ParagraphAlignment, indent: CGFloat, profileValues: ProfileValues?, outerWidth: CGFloat?, baseEm: CGFloat?) -> ParagraphLayout {
        let input = ParagraphShaper.shape(attributed, fallbackSize: fontSize)
        let options = profileValues.map(ParagraphProfileOptions.init(values:)) ?? .init()
        let result = ParagraphEngine.layout(clusters: input.clusters, runs: input.metrics, width: Float(width),
                                            outerWidth: Float(outerWidth ?? width), baseEm: Float(baseEm ?? fontSize),
                                            alignment: alignment == .trailing ? .leading : alignment, indent: Float(indent), options: options)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        func sourceRange(_ clusters: Range<Int>) -> NSRange {
            guard let first = input.ranges[safe: clusters.lowerBound], !clusters.isEmpty,
                  let last = input.ranges[safe: clusters.upperBound - 1] else {
                return NSRange(location: input.ranges[safe: clusters.lowerBound]?.location ?? attributed.length, length: 0)
            }
            return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        }
        func textLine(_ range: NSRange) -> CTLine {
            range.length == 0 ? CTLineCreateWithAttributedString(NSAttributedString(string: ""))
                : CTTypesetterCreateLine(typesetter, CFRange(location: range.location, length: range.length))
        }
        var lines: [ShapedLine] = [], y: CGFloat = 0
        for selected in result.lines {
            let range = sourceRange(selected.clusterRange)
            var fragments = [ShapedFragment]()
            for fragment in selected.fragments {
                let range = sourceRange(fragment.clusterRange)
                let boundaries = fragment.clusterRange.compactMap { input.ranges[safe: $0]?.location } + (range.length > 0 ? [NSMaxRange(range)] : [])
                fragments.append(ShapedFragment(range: range, line: textLine(range), x: CGFloat(fragment.x), width: CGFloat(fragment.width),
                                                drawOffset: CGFloat(fragment.drawDx), capsuleLeft: CGFloat(fragment.capsuleLeft), capsuleRight: CGFloat(fragment.capsuleRight), boundaries: boundaries))
            }
            let logical = textLine(range)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(logical, &ascent, &descent, &leading)
            var hyphen: ShapedHyphen?
            if let x = selected.hyphenX, let run = selected.hyphenRun, input.fonts.indices.contains(run) {
                let source = input.clusters.firstIndex(where: { $0.run == run }).flatMap { input.ranges[safe: $0]?.location }
                let color = source.flatMap { attributed.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? NSColor } ?? .textColor
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: "-", attributes: [.font: input.fonts[run], .foregroundColor: color]))
                hyphen = ShapedHyphen(line: line, x: CGFloat(x), width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            }
            let used = max(fragments.map { $0.x + $0.width }.max() ?? 0, hyphen.map { $0.x + $0.width } ?? 0)
            let baseline = y + max(ascent, fontSize)
            let offset = alignment == .trailing ? max(0, width - used) : 0
            lines.append(ShapedLine(range: range, line: logical, origin: CGPoint(x: offset, y: baseline), ascent: ascent,
                                    descent: descent, width: used, fragments: fragments, hyphen: hyphen, adjustmentRatio: selected.storedRatio))
            y = max(y + fontSize * lineSpacing, baseline + descent + leading)
        }
        return ParagraphLayout(attributed: attributed, lines: lines, height: y, autoRagged: result.autoRagged,
                               diagnostics: result.diagnostics.map(\.rawValue))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
