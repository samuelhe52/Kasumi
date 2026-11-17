import CoreText
import Foundation

/// Snapshot-local factory. Its typesetter is never retained by reflow preparation
/// or shared with another snapshot. Access after publication requires layoutLock.
final class ParagraphFragmentFactory {
    private lazy var typesetter = CTTypesetterCreateWithAttributedString(attributed)
    private let source: NSString
    private let attributed: NSAttributedString
    private let glyphPaintCache: FragmentGlyphPaintCache?
    private var palette: [CGColor] = []

    init(_ attributed: NSAttributedString, glyphPaintCache: FragmentGlyphPaintCache? = nil) {
        source = attributed.string as NSString
        self.attributed = attributed
        self.glyphPaintCache = glyphPaintCache
    }

    func textLine(_ range: NSRange) -> CTLine {
        range.length == 0
            ? CTLineCreateWithAttributedString(NSAttributedString(string: ""))
            : CTTypesetterCreateLine(typesetter, CFRange(location: range.location, length: range.length))
    }

    func cachedGlyphPaint(_ range: NSRange) -> FragmentGlyphPaint? {
        glyphPaintCache?.cachedValue(for: range)
    }

    private func canonicalColor(_ color: CGColor) -> CGColor {
        if let existing = palette.first(where: { $0 == color }) { return existing }
        if palette.count < 16 { palette.append(color) }
        return color
    }

    func materialize(_ range: NSRange) -> FragmentMaterialization {
        // Keep interior grapheme carets even when one measured cluster contains
        // a ligature. This is the same source-backed cut as the eager path.
        var boundaries: [Int] = []
        var boundary = range.location
        while boundary < NSMaxRange(range) {
            boundaries.append(boundary)
            boundary = NSMaxRange(source.rangeOfComposedCharacterSequence(at: boundary))
        }
        if range.length > 0 { boundaries.append(NSMaxRange(range)) }
        let line = textLine(range)
        let glyphPaint = glyphPaintCache?.value(for: range) {
            ParagraphGlyphDrawing.prepare(
                line, attributed: attributed, boundaries: boundaries, canonicalColor: canonicalColor)
        }
        // Core Text adds contextual CJK/Latin spacing at fragment edges. The
        // engine already placed the fragment, so remove that leading inset.
        var inset: CGFloat = glyphPaint?.leadingInset ?? 0
        if glyphPaint == nil, let run = (CTLineGetGlyphRuns(line) as! [CTRun]).first, CTRunGetGlyphCount(run) > 0 {
            var position = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
            inset = max(0, position.x)
        }
        return FragmentMaterialization(line: line, glyphInset: inset, boundaries: boundaries, glyphPaint: glyphPaint)
    }
}

struct FragmentMaterialization {
    let line: CTLine
    let glyphInset: CGFloat
    let boundaries: [Int]
    let glyphPaint: FragmentGlyphPaint?
}

/// Geometry stays immutable. The paint/caret cache changes only during
/// single-threaded construction or under the owning snapshot's layoutLock.
/// Stores share immutable geometry, not wrappers, avoiding a reference cycle.
final class LineFragmentStore {
    private let factory: ParagraphFragmentFactory
    private let geometry: [FragmentGeometry]
    private var last: (index: Int, value: FragmentMaterialization)?
    private var paintValues: [FragmentGlyphPaint?]?

    init(factory: ParagraphFragmentFactory, geometry: [FragmentGeometry]) {
        self.factory = factory
        self.geometry = geometry
    }

    var isMaterialized: Bool { last != nil || paintValues != nil }
    func isMaterialized(at index: Int) -> Bool { last?.index == index || paintValues?[index] != nil }

    func cachedGlyphPaint(at index: Int) -> FragmentGlyphPaint? {
        if let paintValues { return paintValues[index] }
        if let last, last.index == index { return last.value.glyphPaint }
        return factory.cachedGlyphPaint(geometry[index].range)
    }

    func value(at index: Int) -> FragmentMaterialization {
        if let last, last.index == index { return last.value }
        if paintValues == nil {
            // Extract a line together, as on the original deferred path. Keep
            // compact immutable paint for fast revisits without retaining every
            // fragment's Core Text layout objects or depending on NSCache hits.
            let built = geometry.map { factory.materialize($0.range) }
            paintValues = built.map(\.glyphPaint)
            last = (index, built[index])
            return built[index]
        }
        let built = factory.materialize(geometry[index].range)
        last = (index, built)
        return built
    }
}

struct FragmentGeometry {
    let range: NSRange
    let x: CGFloat
    let width: CGFloat
    let drawOffset: CGFloat
    let capsuleLeft: CGFloat
    let capsuleRight: CGFloat
}
