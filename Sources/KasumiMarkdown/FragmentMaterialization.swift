import CoreText
import Foundation

/// Snapshot-local factory. Its typesetter is never retained by reflow preparation
/// or shared with another snapshot. Access after publication requires layoutLock.
final class ParagraphFragmentFactory {
    private let typesetter: CTTypesetter
    private let source: NSString

    init(_ attributed: NSAttributedString) {
        typesetter = CTTypesetterCreateWithAttributedString(attributed)
        source = attributed.string as NSString
    }

    func textLine(_ range: NSRange) -> CTLine {
        range.length == 0
            ? CTLineCreateWithAttributedString(NSAttributedString(string: ""))
            : CTTypesetterCreateLine(typesetter, CFRange(location: range.location, length: range.length))
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
        // Core Text adds contextual CJK/Latin spacing at fragment edges. The
        // engine already placed the fragment, so remove that leading inset.
        var inset: CGFloat = 0
        if let run = (CTLineGetGlyphRuns(line) as! [CTRun]).first, CTRunGetGlyphCount(run) > 0 {
            var position = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
            inset = max(0, position.x)
        }
        return FragmentMaterialization(line: line, glyphInset: inset, boundaries: boundaries)
    }
}

struct FragmentMaterialization {
    let line: CTLine
    let glyphInset: CGFloat
    let boundaries: [Int]
}

/// Geometry stays immutable. The paint/caret cache changes only during
/// single-threaded construction or under the owning snapshot's layoutLock.
/// Stores hold source ranges, not fragments, avoiding a reference cycle.
final class LineFragmentStore {
    private var factory: ParagraphFragmentFactory?
    private var ranges: [NSRange]
    private var values: [FragmentMaterialization]?

    init(factory: ParagraphFragmentFactory, ranges: [NSRange]) {
        self.factory = factory
        self.ranges = ranges
    }

    var isMaterialized: Bool { values != nil }

    func value(at index: Int) -> FragmentMaterialization {
        if let values { return values[index] }
        guard let factory else { preconditionFailure("Unbuilt fragment store lost its factory") }
        let built = ranges.map(factory.materialize)
        values = built
        self.factory = nil
        ranges = []
        return built[index]
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
