import Foundation

struct DocumentPageSlice {
    let range: Range<CGFloat>
    /// Oversized indivisible content is uniformly reduced to fit one page.
    let scale: CGFloat
}

struct PaginationBand {
    var range: Range<CGFloat>
    var keepWithNext = false
}

enum DocumentPaginator {
    static func pages(for layout: DocumentLayout, contentHeight: CGFloat) throws -> [DocumentPageSlice] {
        var bands: [PaginationBand] = []
        for item in layout.paragraphs {
            let heading = layout.headingPositions.values.contains { abs($0 - item.origin.y) < 0.01 }
            for line in item.paragraph.lines {
                let top = item.origin.y + line.origin.y - line.ascent
                let bottom = item.origin.y + line.origin.y + line.descent
                bands.append(PaginationBand(range: top..<max(top, bottom), keepWithNext: heading))
            }
        }
        for rect in layout.imageBounds { bands.append(PaginationBand(range: rect.minY..<rect.maxY)) }
        for range in layout.paginationGroups { bands.append(PaginationBand(range: range)) }
        for rule in layout.rules {
            let top = min(rule.start.y, rule.end.y) - rule.width / 2
            let bottom = max(rule.start.y, rule.end.y) + rule.width / 2
            bands.append(PaginationBand(range: top..<bottom))
        }
        return try pages(bands: bands, height: layout.height, contentHeight: contentHeight)
    }

    static func pages(bands: [PaginationBand], height: CGFloat, contentHeight: CGFloat) throws -> [DocumentPageSlice] {
        guard height.isFinite, height >= 0, contentHeight.isFinite, contentHeight > 0,
            bands.allSatisfy({
                $0.range.lowerBound.isFinite && $0.range.upperBound.isFinite && $0.range.lowerBound >= 0
            })
        else { throw DocumentExportError.invalidGeometry }
        let sorted = bands.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var indivisible: [Range<CGFloat>] = []
        var pendingKeep = false
        for band in sorted where !band.range.isEmpty {
            let overlaps = indivisible.last.map { band.range.lowerBound < $0.upperBound } ?? false
            if let prior = indivisible.last, pendingKeep || overlaps {
                indivisible[indivisible.count - 1] = prior.lowerBound..<max(prior.upperBound, band.range.upperBound)
            } else {
                indivisible.append(band.range)
            }
            pendingKeep = (overlaps && pendingKeep) || band.keepWithNext
        }
        // Ignore trailing paragraph separation so it cannot create a blank page.
        let end = indivisible.last?.upperBound ?? 0
        guard end > 0 else { return [] }
        var start: CGFloat = 0
        var pages: [DocumentPageSlice] = []
        var bandIndex = 0
        while start < end {
            var cut = min(end, start + contentHeight)
            // Page cuts advance monotonically; do not rescan earlier bands for every page.
            while bandIndex < indivisible.count, indivisible[bandIndex].upperBound <= cut { bandIndex += 1 }
            if bandIndex < indivisible.count {
                let band = indivisible[bandIndex]
                if band.lowerBound < cut && band.upperBound > cut {
                    cut = band.lowerBound > start + 0.01 ? band.lowerBound : band.upperBound
                }
            }
            guard cut > start else { throw DocumentExportError.invalidGeometry }
            pages.append(DocumentPageSlice(range: start..<cut, scale: min(1, contentHeight / (cut - start))))
            start = cut
        }
        return pages
    }
}
