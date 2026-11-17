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

    init(runs: [Run], leadingInset: CGFloat) {
        self.runs = runs
        self.leadingInset = leadingInset
    }

    var cost: Int {
        runs.reduce(0) { $0 + 64 + $1.glyphs.count * (MemoryLayout<CGGlyph>.size + MemoryLayout<CGPoint>.size) }
    }
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

    func value(for range: NSRange, build: () -> FragmentGlyphPaint?) -> FragmentGlyphPaint? {
        let key = NSValue(range: range)
        if let entry = values.object(forKey: key) { return entry.value }
        let value = build()
        values.setObject(Entry(value), forKey: key, cost: max(1, value?.cost ?? 0))
        return value
    }
}
