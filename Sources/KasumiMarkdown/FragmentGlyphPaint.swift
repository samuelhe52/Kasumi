import CoreText
import Foundation

/// Immutable values only. CTFont/CGColor are shareable assets; layout objects
/// such as CTLine/CTRun never cross snapshot ownership through this cache.
final class FragmentGlyphPaint {
    struct Run {
        let font: CTFont
        let color: CGColor
        let glyphs: [CGGlyph]
        let positions: [CGPoint]
    }
    let runs: [Run]
    let leadingInset: CGFloat
    let carets: FragmentCaretGeometry?

    init(runs: [Run], leadingInset: CGFloat, carets: FragmentCaretGeometry?) {
        self.runs = runs
        self.leadingInset = leadingInset
        self.carets = carets
    }

    var cost: Int {
        runs.reduce(0) { $0 + 64 + $1.glyphs.count * (MemoryLayout<CGGlyph>.size + MemoryLayout<CGPoint>.size) }
            + (carets?.cost ?? 0)
    }
}

/// Source-backed natural offsets, independent of a snapshot's fragment width.
/// Bound work on a cold paint: long fragments keep their existing CTLine path.
struct FragmentCaretGeometry {
    let boundaries: [Int]
    let naturalWidth: CGFloat
    private let offsets: [CGFloat]

    init?(line: CTLine, inset: CGFloat, boundaries: [Int]) {
        guard boundaries.count <= 64 else { return nil }
        self.boundaries = boundaries
        naturalWidth = boundaries.count > 2 ? CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - inset : 0
        offsets = boundaries.enumerated().map { index, boundary in
            index > 0 && index < boundaries.count - 1 ? CTLineGetOffsetForStringIndex(line, boundary, nil) - inset : 0
        }
    }

    /// Endpoints use the current fragment's box geometry, never these values.
    func interiorOffset(for index: Int) -> CGFloat? {
        var lower = 1
        var upper = max(1, boundaries.count - 1)
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if boundaries[middle] < index { lower = middle + 1 } else { upper = middle }
        }
        guard lower < boundaries.count - 1, boundaries[lower] == index else { return nil }
        return offsets[lower]
    }

    var cost: Int { 32 + boundaries.count * (MemoryLayout<Int>.size + MemoryLayout<CGFloat>.size) }
}

/// One namespace per immutable prepared paragraph. NSCache synchronizes reads
/// and writes; concurrent misses may compute equivalent immutable values twice.
/// Limits are eviction hints, not a process-memory budget.
final class FragmentGlyphPaintCache {
    private final class Entry: NSObject {
        let value: FragmentGlyphPaint?
        init(_ value: FragmentGlyphPaint?) { self.value = value }
    }
    private let values = NSCache<NSValue, Entry>()

    init() {
        values.countLimit = 2048
        values.totalCostLimit = 256 * 1024
    }

    /// A paint-only hit must not build a snapshot-local line or caret records.
    /// Missing and unsupported entries both retain the materialization fallback.
    func cachedValue(for range: NSRange) -> FragmentGlyphPaint? {
        values.object(forKey: NSValue(range: range))?.value
    }

    func value(for range: NSRange, build: () -> FragmentGlyphPaint?) -> FragmentGlyphPaint? {
        let key = NSValue(range: range)
        if let entry = values.object(forKey: key) { return entry.value }
        let value = build()
        values.setObject(Entry(value), forKey: key, cost: max(1, value?.cost ?? 0))
        return value
    }
}
