import CoreGraphics
import CoreText
import Foundation

/// A source-backed text fragment. Box geometry and glyph origin are distinct:
/// compressed opening punctuation can draw to the left of its selection box.
struct ShapedFragment {
    private enum PaintSource {
        case eager(FragmentMaterialization)
        case deferred(LineFragmentStore, Int)
    }
    private let geometry: FragmentGeometry
    private let paintSource: PaintSource

    init(_ geometry: FragmentGeometry, paint: FragmentMaterialization) {
        self.geometry = geometry
        paintSource = .eager(paint)
    }

    init(_ geometry: FragmentGeometry, store: LineFragmentStore, index: Int) {
        self.geometry = geometry
        paintSource = .deferred(store, index)
    }

    var range: NSRange { geometry.range }
    var x: CGFloat { geometry.x }
    var width: CGFloat { geometry.width }
    var drawOffset: CGFloat { geometry.drawOffset }
    var capsuleLeft: CGFloat { geometry.capsuleLeft }
    var capsuleRight: CGFloat { geometry.capsuleRight }

    var materialized: FragmentMaterialization {
        switch paintSource {
        case .eager(let value): return value
        case .deferred(let store, let index): return store.value(at: index)
        }
    }
    /// Immutable paint can outlive cache eviction during this draw. Querying it
    /// never creates the CTLine and grapheme records used by interaction.
    var cachedGlyphPaint: FragmentGlyphPaint? {
        switch paintSource {
        case .eager(let value): return value.glyphPaint
        case .deferred(let store, let index): return store.cachedGlyphPaint(at: index)
        }
    }
    var isMaterialized: Bool {
        switch paintSource {
        case .eager: return true
        case .deferred(let store, _): return store.isMaterialized
        }
    }
    var line: CTLine { materialized.line }
    var glyphInset: CGFloat { materialized.glyphInset }
    var boundaries: [Int] { cachedGlyphPaint?.carets?.boundaries ?? materialized.boundaries }

    func offset(for index: Int) -> CGFloat {
        guard range.length > 0 else { return x }
        if index <= range.location { return x }
        if index >= NSMaxRange(range) { return x + width }
        if let carets = cachedGlyphPaint?.carets, let offset = carets.interiorOffset(for: index) {
            guard carets.naturalWidth > 0 else { return x }
            return x + min(width, max(0, offset / carets.naturalWidth * width))
        }
        let paint = materialized
        let natural = CGFloat(CTLineGetTypographicBounds(paint.line, nil, nil, nil)) - paint.glyphInset
        guard natural > 0 else { return x }
        let offset = CTLineGetOffsetForStringIndex(paint.line, index, nil) - paint.glyphInset
        return x + min(width, max(0, offset / natural * width))
    }

    func index(at position: CGFloat) -> Int {
        boundaries.min { abs(offset(for: $0) - position) < abs(offset(for: $1) - position) } ?? range.location
    }
}

struct ShapedHyphen {
    let line: CTLine
    let x: CGFloat
    let width: CGFloat
}

enum SourceBoundaryAffinity {
    case followingFragment
    case precedingFragment
}

struct ShapedLine {
    let range: NSRange
    /// Logical source line. Fragment geometry below governs native paragraph
    /// drawing and hit testing; this line also supports the verbatim path.
    let line: CTLine
    let origin: CGPoint
    let ascent: CGFloat
    let descent: CGFloat
    let width: CGFloat
    var fragments: [ShapedFragment] = []
    var hyphen: ShapedHyphen? = nil
    var adjustmentRatio: Float = 0

    func offset(forStringIndex index: Int, affinity: SourceBoundaryAffinity = .followingFragment) -> CGFloat {
        guard !fragments.isEmpty else { return CTLineGetOffsetForStringIndex(line, index, nil) }
        let visible = fragments.filter { $0.range.length > 0 }
        guard let first = visible.first, let last = visible.last else { return 0 }
        if index <= first.range.location { return first.x }
        if index >= NSMaxRange(last.range) { return last.x + last.width }
        // Glue can separate two boxes without adding a source character.
        // A selection start belongs to the following box, its end to the
        // preceding box; a single caret coordinate cannot represent both.
        if affinity == .followingFragment, let fragment = visible.first(where: { $0.range.location == index }) {
            return fragment.x
        }
        if affinity == .precedingFragment, let fragment = visible.last(where: { NSMaxRange($0.range) == index }) {
            return fragment.x + fragment.width
        }
        var previous = first
        for fragment in visible {
            if index >= fragment.range.location && index <= NSMaxRange(fragment.range) {
                return fragment.offset(for: index)
            }
            if index < fragment.range.location {
                let count = fragment.range.location - NSMaxRange(previous.range)
                let fraction = count > 0 ? CGFloat(index - NSMaxRange(previous.range)) / CGFloat(count) : 0
                return previous.x + previous.width + fraction * (fragment.x - previous.x - previous.width)
            }
            previous = fragment
        }
        return last.x + last.width
    }

    func stringIndex(forPosition position: CGPoint) -> Int {
        guard !fragments.isEmpty else { return CTLineGetStringIndexForPosition(line, position) }
        let visible = fragments.filter { $0.range.length > 0 }
        guard
            let nearest = visible.min(by: {
                distance(position.x, from: $0) < distance(position.x, from: $1)
            })
        else { return range.location }
        return nearest.index(at: position.x)
    }

    private func distance(_ x: CGFloat, from fragment: ShapedFragment) -> CGFloat {
        max(fragment.x - x, max(0, x - fragment.x - fragment.width))
    }
}
