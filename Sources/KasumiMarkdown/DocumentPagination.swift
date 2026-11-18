import Foundation

struct DocumentPageSlice {
    let range: Range<CGFloat>
    /// Oversized indivisible content is uniformly reduced to fit one page.
    let scale: CGFloat
    /// Source decoration to repeat above a continued code block.
    var continuationHeader: Range<CGFloat>? = nil
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
        return try pages(
            bands: bands, height: layout.height, contentHeight: contentHeight, codeBlocks: layout.codeBlocks)
    }

    static func pages(
        bands: [PaginationBand], height: CGFloat, contentHeight: CGFloat, codeBlocks: [CodeBlockLayout] = []
    ) throws -> [DocumentPageSlice] {
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
        var codeIndex = 0
        while start < end {
            while codeIndex < codeBlocks.count, codeBlocks[codeIndex].block.frame.maxY <= start { codeIndex += 1 }
            var header: Range<CGFloat>?
            if codeIndex < codeBlocks.count {
                let block = codeBlocks[codeIndex].block
                if block.captionFrame != nil, block.frame.minY < start, start < block.frame.maxY {
                    header = block.frame.minY..<block.contentFrame.minY
                }
            }
            let headerHeight = header.map { $0.upperBound - $0.lowerBound } ?? 0
            var cut = min(end, start + max(0, contentHeight - headerHeight))
            while bandIndex < indivisible.count, indivisible[bandIndex].upperBound <= start { bandIndex += 1 }
            let firstBand = bandIndex
            // Page cuts advance monotonically; do not rescan earlier bands for every page.
            while bandIndex < indivisible.count, indivisible[bandIndex].upperBound <= cut { bandIndex += 1 }
            if bandIndex < indivisible.count {
                let band = indivisible[bandIndex]
                if band.lowerBound < cut && band.upperBound > cut {
                    cut = band.lowerBound > start + 0.01 ? band.lowerBound : band.upperBound
                }
                // An oversized repeated header must travel with actual content,
                // even when both need scaling to fit a very short page.
                if headerHeight > 0, bandIndex == firstBand, cut <= band.lowerBound {
                    cut = band.upperBound
                }
            }
            guard cut > start else { throw DocumentExportError.invalidGeometry }
            pages.append(
                DocumentPageSlice(
                    range: start..<cut, scale: min(1, contentHeight / (headerHeight + cut - start)),
                    continuationHeader: header))
            start = cut
        }
        return pages
    }
}
