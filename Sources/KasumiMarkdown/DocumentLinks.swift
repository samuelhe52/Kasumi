import CoreText
import Foundation

package enum DocumentLink {
    static func url(_ value: Any, relativeTo baseURL: URL?) -> URL? {
        if let url = value as? URL { return url }
        guard let string = value as? String, !string.isEmpty else { return nil }
        return URL(string: string, relativeTo: string.hasPrefix("#") ? nil : baseURL)?.absoluteURL
    }

    package static func anchorKey(_ anchor: String) -> String {
        let fragment = anchor.hasPrefix("#") ? String(anchor.dropFirst()) : anchor
        return fragment.removingPercentEncoding ?? fragment
    }
}

enum CoreTextRangeGeometry {
    /// Core Text lines can contain visually disjoint runs for a logical range.
    /// At bidi boundaries, use the edge of the intersected run for its caret.
    static func extents(in line: CTLine, for range: NSRange) -> [ClosedRange<CGFloat>] {
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        let spans: [ClosedRange<CGFloat>] = runs.compactMap { run in
            let source = CTRunGetStringRange(run)
            let overlap = NSIntersectionRange(range, NSRange(location: source.location, length: source.length))
            guard overlap.length > 0, CTRunGetGlyphCount(run) > 0 else { return nil }
            var origin = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &origin)
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(), nil, nil, nil))
            let left = origin.x
            let right = left + max(0, width)
            let rtl = CTRunGetStatus(run).contains(.rightToLeft)
            let start =
                overlap.location == source.location
                ? (rtl ? right : left) : CTLineGetOffsetForStringIndex(line, overlap.location, nil)
            let end =
                NSMaxRange(overlap) == source.location + source.length
                ? (rtl ? left : right) : CTLineGetOffsetForStringIndex(line, NSMaxRange(overlap), nil)
            return min(start, end)...max(start, end)
        }.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<CGFloat>] = []
        for span in spans where span.lowerBound < span.upperBound {
            if let last = merged.last, span.lowerBound <= last.upperBound + 0.01 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }
}

extension ShapedLine {
    func linkRects(for range: NSRange, in attributed: NSAttributedString) -> [CGRect] {
        if fragments.isEmpty {
            return CoreTextRangeGeometry.extents(in: line, for: range).map {
                CGRect(x: $0.lowerBound, y: -ascent, width: $0.upperBound - $0.lowerBound, height: ascent + descent)
            }
        }
        let start = offset(forStringIndex: range.location)
        var end = offset(forStringIndex: NSMaxRange(range), affinity: .precedingFragment)
        if let hyphen, NSMaxRange(range) == NSMaxRange(self.range),
            NSMaxRange(range) < attributed.length,
            attributed.attribute(.link, at: NSMaxRange(range), effectiveRange: nil) != nil
        {
            end = max(end, hyphen.x + CGFloat(CTLineGetTypographicBounds(hyphen.line, nil, nil, nil)))
        }
        return [CGRect(x: min(start, end), y: -ascent, width: abs(end - start), height: ascent + descent)]
    }
}

/// Streams annotations along with the clipped PDF drawing pass.
struct PDFLinkAnnotations {
    private let baseURL: URL?
    private let anchorNames: Set<String>
    private let destinations: [(name: String, y: CGFloat)]

    init(layout: DocumentLayout, baseURL: URL?) {
        self.baseURL = baseURL
        anchorNames = Set(layout.anchorPositions.keys)
        let anchorOrigins = Set(layout.anchorPositions.values)
        var tops: [CGFloat: CGFloat] = [:]
        for item in layout.paragraphs where anchorOrigins.contains(item.origin.y) {
            if let line = item.paragraph.lines.first {
                let y = item.origin.y + line.origin.y - line.ascent
                tops[item.origin.y] = min(tops[item.origin.y] ?? y, y)
            }
        }
        destinations = layout.anchorPositions.map { ($0.key, tops[$0.value] ?? $0.value) }
            .sorted { $0.y == $1.y ? $0.name < $1.name : $0.y < $1.y }
    }

    func writeDestinations(in context: CGContext, range: Range<CGFloat>) {
        var lower = 0
        var upper = destinations.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if destinations[middle].y < range.lowerBound { lower = middle + 1 } else { upper = middle }
        }
        for (name, y) in destinations[lower...].prefix(while: { $0.y < range.upperBound }) {
            let point = context.convertToDeviceSpace(CGPoint(x: 0, y: y))
            context.addDestination(name as CFString, at: point)
        }
    }

    func write(_ value: Any, rect: CGRect, clip: CGRect, in context: CGContext) {
        let visible = rect.intersection(clip)
        guard !visible.isNull, !visible.isEmpty,
            let url = DocumentLink.url(value, relativeTo: baseURL)
        else { return }
        let pdfRect = context.convertToDeviceSpace(visible)
        if url.relativeString.hasPrefix("#") {
            let key = DocumentLink.anchorKey(url.relativeString)
            if anchorNames.contains(key) { context.setDestination(key as CFString, for: pdfRect) }
        } else if let scheme = url.scheme?.lowercased(), !["javascript", "vbscript", "data"].contains(scheme) {
            context.setURL(url as CFURL, for: pdfRect)
        }
    }
}
