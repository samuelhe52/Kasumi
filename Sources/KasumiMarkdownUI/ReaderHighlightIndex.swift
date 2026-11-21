import Foundation
import KasumiMarkdown

/// Numeric search intervals keep original result indices while bounding geometry
/// work. The origin validates snapshot ownership without retaining its layout.
struct ReaderHighlightIndex {
    private let origin: KasumiMarkdown.TextPosition
    private let ranges: [NSRange]

    init?(_ matches: [KasumiMarkdown.TextRange], in rendered: RenderedDocument) {
        let origin = rendered.documentRange.lowerBound
        var ranges: [NSRange] = []
        var previousEnd = 0
        ranges.reserveCapacity(matches.count)
        for match in matches {
            guard let start = rendered.offset(from: origin, to: match.lowerBound),
                let end = rendered.offset(from: origin, to: match.upperBound),
                start >= previousEnd, end > start
            else { return nil }
            ranges.append(NSRange(location: start, length: end - start))
            previousEnd = end
        }
        self.origin = origin
        self.ranges = ranges
    }

    func candidates(in rendered: RenderedDocument, verticalRange: Range<CGFloat>) -> Range<Int> {
        guard let visible = rendered.textRange(intersectingVerticalRange: verticalRange),
            let start = rendered.offset(from: origin, to: visible.lowerBound),
            let end = rendered.offset(from: origin, to: visible.upperBound)
        else { return 0..<0 }
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(ranges[middle]) <= start { lower = middle + 1 } else { upper = middle }
        }
        let first = lower
        upper = ranges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if ranges[middle].location < end { lower = middle + 1 } else { upper = middle }
        }
        return first..<lower
    }
}
