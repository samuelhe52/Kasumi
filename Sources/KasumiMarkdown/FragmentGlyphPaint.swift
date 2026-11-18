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
    struct SingleGlyph {
        let font: CTFont
        let color: CGColor
        let glyph: CGGlyph
        let position: CGPoint
    }
    enum Storage {
        case single(SingleGlyph)
        case runs([Run])
    }
    let storage: Storage
    let leadingInset: CGFloat
    let carets: FragmentCaretGeometry?

    init(runs: [Run], leadingInset: CGFloat, carets: FragmentCaretGeometry?) {
        if runs.count == 1, let run = runs.first, run.glyphs.count == 1, run.positions.count == 1 {
            storage = .single(.init(font: run.font, color: run.color, glyph: run.glyphs[0], position: run.positions[0]))
        } else {
            storage = .runs(runs)
        }
        self.leadingInset = leadingInset
        self.carets = carets
    }

    init(single: SingleGlyph, leadingInset: CGFloat, carets: FragmentCaretGeometry?) {
        storage = .single(single)
        self.leadingInset = leadingInset
        self.carets = carets
    }

    var cost: Int {
        let paint: Int
        switch storage {
        case .single: paint = 64
        case .runs(let runs):
            paint = runs.reduce(0) {
                $0 + 64 + $1.glyphs.count * (MemoryLayout<CGGlyph>.size + MemoryLayout<CGPoint>.size)
            }
        }
        return paint + (carets?.cost ?? 0)
    }
}

/// Source-backed natural offsets, independent of a snapshot's fragment width.
/// Bound work on a cold paint: long fragments keep their existing CTLine path.
struct FragmentCaretGeometry {
    private enum Storage {
        case endpoints(NSRange)
        case detailed(boundaries: [Int], width: CGFloat, offsets: [CGFloat])
    }
    private let storage: Storage
    var boundaries: [Int] {
        switch storage {
        case .endpoints(let range): return [range.location, NSMaxRange(range)]
        case .detailed(let boundaries, _, _): return boundaries
        }
    }
    var naturalWidth: CGFloat {
        switch storage {
        case .endpoints: return 0
        case .detailed(_, let width, _): return width
        }
    }

    init?(line: CTLine, inset: CGFloat, boundaries: [Int]) {
        guard boundaries.count <= 64 else { return nil }
        if boundaries.count == 2 {
            storage = .endpoints(NSRange(location: boundaries[0], length: boundaries[1] - boundaries[0]))
            return
        }
        let naturalWidth = boundaries.count > 2 ? CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - inset : 0
        let offsets = boundaries.enumerated().map { index, boundary in
            index > 0 && index < boundaries.count - 1 ? CTLineGetOffsetForStringIndex(line, boundary, nil) - inset : 0
        }
        storage = .detailed(boundaries: boundaries, width: naturalWidth, offsets: offsets)
    }

    /// Endpoints use the current fragment's box geometry, never these values.
    func interiorOffset(for index: Int) -> CGFloat? {
        guard case .detailed(let boundaries, _, let offsets) = storage else { return nil }
        var lower = 1
        var upper = max(1, boundaries.count - 1)
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if boundaries[middle] < index { lower = middle + 1 } else { upper = middle }
        }
        guard lower < boundaries.count - 1, boundaries[lower] == index else { return nil }
        return offsets[lower]
    }

    var cost: Int {
        switch storage {
        case .endpoints: return 32
        case .detailed(let boundaries, _, _):
            return 32 + boundaries.count * (MemoryLayout<Int>.size + MemoryLayout<CGFloat>.size)
        }
    }
}

/// One namespace per immutable prepared paragraph, with a session-wide storage
/// budget. NSCache synchronizes reads and writes; concurrent misses may compute
/// equivalent immutable values twice. Limits are hints, not a process budget.
final class FragmentGlyphPaintCache {
    fileprivate final class Key: NSObject {
        let namespace: UUID
        let range: NSRange
        init(namespace: UUID, range: NSRange) {
            self.namespace = namespace
            self.range = range
        }
        override var hash: Int { namespace.hashValue ^ range.hashValue }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return namespace == other.namespace && range == other.range
        }
    }
    fileprivate final class Entry: NSObject {
        let value: FragmentGlyphPaint?
        init(_ value: FragmentGlyphPaint?) { self.value = value }
    }
    final class Storage {
        fileprivate let values = NSCache<Key, Entry>()
        init(countLimit: Int = 2048, costLimit: Int = 256 * 1024) {
            values.countLimit = countLimit
            values.totalCostLimit = costLimit
        }
        func removeAll() { values.removeAllObjects() }
    }
    private let storage: Storage
    private let namespace = UUID()

    init(storage: Storage? = nil) { self.storage = storage ?? Storage() }

    /// A paint-only hit must not build a snapshot-local line or caret records.
    /// Missing and unsupported entries both retain the materialization fallback.
    func cachedValue(for range: NSRange) -> FragmentGlyphPaint? {
        storage.values.object(forKey: Key(namespace: namespace, range: range))?.value
    }

    func value(for range: NSRange, build: () -> FragmentGlyphPaint?) -> FragmentGlyphPaint? {
        let key = Key(namespace: namespace, range: range)
        if let entry = storage.values.object(forKey: key) { return entry.value }
        let value = build()
        storage.values.setObject(Entry(value), forKey: key, cost: 128 + (value?.cost ?? 0))
        return value
    }
}
