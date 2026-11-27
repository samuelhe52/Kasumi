import CoreGraphics
import CoreText
import Foundation

/// A position in this immutable layout's semantic UTF-16 text. Obtain positions
/// from hit testing, search, or documentRange; rendered attachment offsets never
/// escape this boundary. Positions from different layouts are not interchangeable.
public struct TextPosition: Comparable, Hashable, Sendable {
    fileprivate let owner: UUID
    fileprivate let offset: Int

    public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        precondition(lhs.owner == rhs.owner, "Text positions must belong to the same rendered layout")
        return lhs.offset < rhs.offset
    }
}

public struct TextRange: Hashable, Sendable {
    public let lowerBound: TextPosition
    public let upperBound: TextPosition
    public var isEmpty: Bool { lowerBound == upperBound }

    public init(_ start: TextPosition, _ end: TextPosition) {
        lowerBound = min(start, end)
        upperBound = max(start, end)
    }
}

/// Empty options mean case- and diacritic-insensitive matching.
public struct SearchOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let caseSensitive = SearchOptions(rawValue: 1 << 0)
    public static let diacriticSensitive = SearchOptions(rawValue: 1 << 1)
}

/// Owns a frozen layout; callers may build it on a detached task and publish it
/// to UI/tile threads. No mutable attributed storage is exposed. Core Text layout
/// objects are created during construction or by snapshot-local lazy fragment
/// stores. Post-publication Core Text materialization and use are serialized by
/// `layoutLock`; layout content and geometry stay immutable. Immutable
/// CGImage/CGColor/font-table assets are retained, not mutated. Global image reads
/// use NSCache's synchronized methods;
/// bundled font registration and math assets use Swift's serialized static lets.
/// Reflow sessions may also share immutable glyph-paint values through a
/// synchronized NSCache; no CTLine/CTRun/CTTypesetter enters that shared cache.
/// The lock protects shared CTLine/CTRun objects, not mutable Kasumi draw state:
/// Apple's Core Text contract confines layout objects to one operation/queue/thread
/// even though individual functions and font objects are thread-safe.
/// https://developer.apple.com/documentation/CoreText
public final class RenderedDocument: @unchecked Sendable {
    /// Includes estimated offscreen heights in opt-in viewport snapshots.
    public let size: CGSize
    public let backgroundColor: CGColor
    public var tables: [RenderedTable] { layout.tables }
    /// Block/content/caption bounds and original source/language, separate from selectable text.
    public var codeBlocks: [RenderedCodeBlock] { layout.codeBlocks.map(\.block) }
    private let owner = UUID()
    private let layout: DocumentLayout
    private let readingIndex: ReadingPositionIndex
    private let baseURL: URL?
    private let layoutLock = NSLock()
    private let lines: [Line]
    private let semanticSource: NSString
    private var semanticLength: Int { semanticSource.length }
    private let semanticText: String
    private let estimatedRegions: [CGRect]
    private let estimatedPrefixBottoms: [CGFloat]
    private let readerImages: ReaderImageCache?
    private let placedImages: [PlacedReaderImage]
    private let imagePrefixBottoms: [CGFloat]

    /// Viewport snapshots have estimated offscreen heights and geometry. Their
    /// semantic text remains complete. Default/full snapshots always return false.
    public var hasEstimatedGeometry: Bool { !estimatedRegions.isEmpty }

    /// True when painting or interacting here needs a new viewport snapshot.
    /// Geometry outside measured paragraphs is approximate until that refinement.
    public func needsLayout(in rect: CGRect) -> Bool {
        guard !rect.isNull, rect.minY.isFinite, rect.maxY.isFinite else { return false }
        var lower = 0
        var upper = estimatedPrefixBottoms.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if estimatedPrefixBottoms[middle] > rect.minY { upper = middle } else { lower = middle + 1 }
        }
        return lower < estimatedRegions.count && estimatedRegions[lower].minY < rect.maxY
    }

    var paragraphStatistics: (total: Int, measured: Int) {
        (layout.paragraphs.count, layout.paragraphs.filter { $0.paragraph.estimate == nil }.count)
    }

    /// Internal instrumentation reads cache state without materializing fragments.
    var fragmentStatistics: (total: Int, materialized: Int) {
        layoutLock.withLock {
            var total = 0
            var built = 0
            for paragraph in layout.paragraphs {
                for line in paragraph.paragraph.lines {
                    total += line.fragments.count
                    for fragment in line.fragments where fragment.isMaterialized { built += 1 }
                }
            }
            return (total, built)
        }
    }

    private struct Line {
        let paragraph: Int
        let shaped: ShapedLine
        let origin: CGPoint
        let range: NSRange
        let rect: CGRect
    }

    /// Enable table overflow for interactive readers. Headless layouts default
    /// to fitting all columns inside the requested width.
    public convenience init(
        _ document: MarkdownDocument, width: CGFloat, style: RenderStyle, scrollableTables: Bool = false
    ) {
        self.init(document, width: width, style: style, scrollableTables: scrollableTables, preparation: nil)
    }

    init(
        _ document: MarkdownDocument, width: CGFloat, style: RenderStyle, scrollableTables: Bool,
        preparation: ReflowPreparation?, viewport: ViewportLayoutRequest? = nil, readerImages: ReaderImageCache? = nil
    ) {
        precondition(width.isFinite && width > 0, "Layout width must be finite and positive")
        let insets = style.insets
        precondition(
            [insets.top, insets.left, insets.bottom, insets.right].allSatisfy { $0.isFinite && $0 >= 0 },
            "Layout insets must be finite and nonnegative")
        var typography = style.typography
        self.readerImages = readerImages
        typography.readerImages = readerImages
        var built: DocumentLayout
        if let viewport, let preparation {
            built = DocumentTypesetter.viewportLayout(
                document.parsed, width: width, style: typography, insets: insets,
                scrollableTables: scrollableTables, preparation: preparation, request: viewport)
        } else {
            built = DocumentTypesetter.layout(
                document.parsed, width: width, style: typography, insets: insets, scrollableTables: scrollableTables,
                preparation: preparation)
        }
        built.text = NSAttributedString(attributedString: built.text)
        layout = built
        placedImages = built.readerImages.sorted { $0.rect.minY < $1.rect.minY }
        var imageBottom = -CGFloat.infinity
        imagePrefixBottoms = placedImages.map {
            imageBottom = max(imageBottom, $0.rect.maxY)
            return imageBottom
        }
        estimatedRegions = built.paragraphs.filter { $0.paragraph.estimate != nil }.map(\.estimatedPaintBounds)
            .sorted { $0.minY < $1.minY }
        var maximum = -CGFloat.infinity
        estimatedPrefixBottoms = estimatedRegions.map {
            maximum = max(maximum, $0.maxY)
            return maximum
        }
        size = CGSize(width: built.width, height: built.height)
        backgroundColor = typography.paperColor.cgColor
        readingIndex = ReadingPositionIndex(layout: built)
        baseURL = document.parsed.baseURL
        lines = built.paragraphs.enumerated().flatMap { index, item in
            item.paragraph.lines.map { line in
                let origin = CGPoint(x: item.origin.x + line.origin.x, y: item.origin.y + line.origin.y)
                return Line(
                    paragraph: index, shaped: line, origin: origin,
                    range: NSRange(location: item.textOffset + line.range.location, length: line.range.length),
                    rect: CGRect(
                        x: origin.x, y: origin.y - line.ascent, width: max(1, line.width),
                        height: max(1, line.ascent + line.descent)))
            }
        }
        let semantic = built.semanticContent ?? DocumentSemanticContent(built.textMap)
        semanticText = semantic.text
        semanticSource = semantic.text as NSString
    }

    public var hasReaderImages: Bool { !placedImages.isEmpty }

    /// Returns the image occurrences intersecting the visible document rect.
    /// Pass offsets for independently scrolling tables in their content coordinates.
    public func readerImageRegions(in rect: CGRect, tableOffsets: [Int: CGFloat] = [:]) -> [ReaderImageRegion] {
        guard !rect.isEmpty, rect.minY.isFinite, rect.maxY.isFinite else { return [] }
        var lower = 0
        var upper = imagePrefixBottoms.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if imagePrefixBottoms[middle] > rect.minY { upper = middle } else { lower = middle + 1 }
        }
        var regions: [ReaderImageRegion] = []
        for image in placedImages[lower...] {
            guard image.rect.minY < rect.maxY else { break }
            if let index = image.tableIndex, layout.tables[index].isScrollable {
                let table = layout.tables[index]
                let visible = rect.intersection(table.frame)
                let offset = tableOffsets[index] ?? 0
                guard !visible.isEmpty, image.rect.intersects(visible.offsetBy(dx: offset, dy: 0)) else { continue }
                regions.append(
                    ReaderImageRegion(
                        rect: image.rect.offsetBy(dx: -table.frame.minX, dy: -table.frame.minY),
                        tableID: index, request: image.request))
            } else if image.rect.intersects(rect) {
                regions.append(ReaderImageRegion(rect: image.rect, tableID: nil, request: image.request))
            }
        }
        return regions
    }

    /// True when no further preparation is needed for this occurrence.
    public func hasReaderImageResult(for region: ReaderImageRegion) -> Bool {
        readerImages?.hasResult(for: region.request) == true
    }

    /// Load one raster away from drawing. Hosts should serialize requests and
    /// invalidate the affected tiles when this returns true.
    @discardableResult public func prepareReaderImage(_ region: ReaderImageRegion) async -> Bool {
        await readerImages?.load(region.request) == true
    }

    package func prepareReaderResource(_ region: ReaderImageRegion) async -> ReaderResourceUpdate {
        await readerImages?.prepare(region.request) ?? .none
    }

    package var readerSemanticText: String { semanticText }

    /// `rect` and the CGContext must use document coordinates (top-left, y down).
    /// Each caller owns its context. The clip protects adjacent tiles, and the
    /// existing sourceRange path excludes off-tile text/attachment drawing.
    /// Unmeasured text is not painted: viewport clients must check `needsLayout`
    /// and request a refined snapshot when moving outside the measured window.
    public func draw(in context: CGContext, rect: CGRect, excludingScrollableTables: Bool = false) {
        draw(in: context, rect: rect, excludingScrollableTables: excludingScrollableTables, highlights: [])
    }

    package func draw(
        in context: CGContext, rect: CGRect, excludingScrollableTables: Bool,
        highlights: [(rects: [CGRect], color: CGColor)]
    ) {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
            rect.width > 0, rect.height > 0
        else { return }
        let visible = rect.intersection(CGRect(origin: .zero, size: size))
        guard !visible.isNull, !visible.isEmpty else { return }
        layoutLock.withLock {
            context.saveGState()
            defer { context.restoreGState() }
            context.clip(to: visible)
            // Let the clip apply fractional edge coverage exactly once.
            // Filling the same fractional rect would multiply alpha twice.
            context.setFillColor(backgroundColor)
            context.fill(visible.integral)
            DocumentTypesetter.draw(
                layout, in: context, sourceRange: (visible.minY - 4)..<(visible.maxY + 4),
                excludingScrollableTables: excludingScrollableTables, highlights: highlights)
        }
    }

    /// Paint one table in table-content coordinates (0,0 at its frame's origin),
    /// including columns outside the page. Use a native scroll view to clip it.
    public func drawTable(at index: Int, in context: CGContext, rect: CGRect) {
        drawTable(at: index, in: context, rect: rect, highlights: [])
    }

    package func drawTable(
        at index: Int, in context: CGContext, rect: CGRect, highlights: [(rects: [CGRect], color: CGColor)]
    ) {
        guard layout.tables.indices.contains(index),
            rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
            rect.width > 0, rect.height > 0
        else { return }
        let table = layout.tables[index]
        let visible = rect.intersection(CGRect(x: 0, y: 0, width: table.contentWidth, height: table.frame.height))
        guard !visible.isNull, !visible.isEmpty else { return }
        layoutLock.withLock {
            context.saveGState()
            defer { context.restoreGState() }
            context.clip(to: visible)
            context.setFillColor(backgroundColor)
            context.fill(visible.integral)
            context.translateBy(x: -table.frame.minX, y: -table.frame.minY)
            DocumentTypesetter.draw(
                layout, in: context,
                sourceRange: (visible.minY + table.frame.minY - 4)..<(visible.maxY + table.frame.minY + 4),
                tableIndex: index, highlights: highlights)
        }
    }

    public var documentRange: TextRange {
        TextRange(position(0), position(semanticLength))
    }

    package func readerTableTextRange(at index: Int) -> TextRange {
        let offsets = layout.tables[index].textOffsets
        return TextRange(
            position(layout.textMap.semanticOffset(forRenderedOffset: offsets.lowerBound)),
            position(layout.textMap.semanticOffset(forRenderedOffset: offsets.upperBound)))
    }

    /// Moves by semantic UTF-16 code units, as required by UIKit text input.
    /// Returns nil for a foreign snapshot, overflow, or an out-of-document offset.
    /// Hit testing snaps to graphemes; arithmetic intentionally preserves exact
    /// UTF-16 offsets so tokenizer distances and substring ranges round-trip.
    public func position(from start: TextPosition, offset: Int) -> TextPosition? {
        guard start.owner == owner else { return nil }
        let (next, overflow) = start.offset.addingReportingOverflow(offset)
        guard !overflow, next >= 0, next <= semanticLength else { return nil }
        return position(next)
    }

    /// The signed semantic UTF-16 distance, or nil for positions from another layout.
    public func offset(from start: TextPosition, to end: TextPosition) -> Int? {
        guard start.owner == owner, end.owner == owner else { return nil }
        return end.offset - start.offset
    }

    public func position(closestTo point: CGPoint) -> TextPosition {
        guard point.x.isFinite, point.y.isFinite else { return documentRange.lowerBound }
        return layoutLock.withLock {
            // Decide whether approximation is needed by vertical proximity, not
            // full-measure estimated widths. This keeps covered margin taps on
            // measured lines and offscreen gap/end hits near the queried Y.
            func verticalDistance(_ item: PlacedText) -> CGFloat {
                max(item.origin.y - point.y, max(0, point.y - item.origin.y - item.paragraph.height))
            }
            if hasEstimatedGeometry,
                let item = layout.paragraphs.min(by: { verticalDistance($0) < verticalDistance($1) }),
                item.paragraph.estimate != nil
            {
                let fraction = min(1, max(0, (point.y - item.origin.y) / max(1, item.paragraph.height)))
                let rendered = item.textOffset + Int(CGFloat(item.paragraph.attributed.length) * fraction)
                return position(nearestSemanticBoundary(to: layout.textMap.semanticOffset(forRenderedOffset: rendered)))
            }
            guard let line = nearestLine(to: point) else { return position(0) }
            if let diagram = layout.diagrams[line.paragraph], let offset = diagram.textOffset(at: point) {
                let start = layout.textMap.semanticOffset(forRenderedOffset: diagram.renderedOffset)
                return position(nearestSemanticBoundary(to: start + offset))
            }
            let item = layout.paragraphs[line.paragraph]
            let local = line.shaped.stringIndex(forPosition: CGPoint(x: point.x - line.origin.x, y: 0))
            let rendered = item.textOffset + min(NSMaxRange(line.shaped.range), max(line.shaped.range.location, local))
            let semantic = layout.textMap.semanticOffset(forRenderedOffset: rendered)
            return position(nearestSemanticBoundary(to: semantic))
        }
    }

    public func caretRect(for position: TextPosition) -> CGRect {
        guard position.owner == owner else { return .zero }
        return layoutLock.withLock {
            let rendered = layout.textMap.renderedOffset(forSemanticOffset: position.offset)
            if let item = estimatedParagraph(containing: rendered), let estimate = item.paragraph.estimate {
                let fraction = CGFloat(rendered - item.textOffset) / CGFloat(max(1, item.paragraph.attributed.length))
                return CGRect(
                    x: item.origin.x, y: item.origin.y + fraction * item.paragraph.height,
                    width: 1, height: estimate.lineHeight)
            }
            guard let line = line(containing: rendered) else {
                return CGRect(x: 0, y: 0, width: 1, height: 1)
            }
            if let diagram = layout.diagrams[line.paragraph] {
                let start = layout.textMap.semanticOffset(forRenderedOffset: diagram.renderedOffset)
                if let caret = diagram.caretRect(at: position.offset - start) { return caret }
            }
            let item = layout.paragraphs[line.paragraph]
            let x = line.origin.x + line.shaped.offset(forStringIndex: rendered - item.textOffset)
            return CGRect(x: x, y: line.rect.minY, width: 1, height: line.rect.height)
        }
    }

    /// A conservative semantic envelope of text overlapping a vertical window.
    /// Includes all table columns and full attachment replacements; unmeasured
    /// text contributes its whole paragraph. It can include intervening offscreen
    /// text. Exact selection geometry remains available through `selectionRects`.
    /// Empty/nonfinite windows or windows without searchable text return nil.
    /// This query does not materialize deferred glyphs or refine estimates.
    public func textRange(intersectingVerticalRange range: Range<CGFloat>) -> TextRange? {
        guard let rendered = readingIndex.renderedRange(intersectingVerticalRange: range),
            let semantic = layout.textMap.semanticRange(forRenderedRange: rendered)
        else { return nil }
        let limit = semanticLength
        let start = min(limit, semantic.location)
        let end = min(limit, NSMaxRange(semantic))
        guard end > start else { return nil }
        return textRange(NSRange(location: start, length: end - start))
    }

    public func selectionRects(for range: TextRange) -> [CGRect] {
        guard let semantic = checked(range), semantic.length > 0,
            let rendered = layout.textMap.renderedRange(for: semantic)
        else { return [] }
        return layoutLock.withLock {
            // Logical source ranges stay ordered even for RTL or table cells.
            // Seek past preceding text rather than scanning it for every Find
            // result. Keep all Core Text access under this snapshot's lock.
            var lower = 0
            var upper = lines.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if NSMaxRange(lines[middle].range) <= rendered.location { lower = middle + 1 } else { upper = middle }
            }
            var measured: [CGRect] = []
            for line in lines[lower...].prefix(while: { $0.range.location < NSMaxRange(rendered) }) {
                let overlap = NSIntersectionRange(rendered, line.range)
                guard overlap.length > 0 else { continue }
                if let diagram = layout.diagrams[line.paragraph] {
                    let start = layout.textMap.semanticOffset(forRenderedOffset: diagram.renderedOffset)
                    let diagramRange = NSRange(location: start, length: diagram.attachment.semanticText.utf16.count)
                    let overlap = NSIntersectionRange(semantic, diagramRange)
                    guard overlap.length > 0 else { continue }
                    let local = NSRange(location: overlap.location - start, length: overlap.length)
                    measured.append(contentsOf: diagram.selectionRects(for: local))
                    continue
                }
                let item = layout.paragraphs[line.paragraph]
                let start = line.shaped.offset(forStringIndex: overlap.location - item.textOffset)
                let end = line.shaped.offset(
                    forStringIndex: NSMaxRange(overlap) - item.textOffset, affinity: .precedingFragment)
                measured.append(
                    CGRect(
                        x: line.origin.x + min(start, end), y: line.rect.minY,
                        width: abs(end - start), height: line.rect.height))
            }
            lower = 0
            upper = layout.paragraphs.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                let item = layout.paragraphs[middle]
                if item.textOffset + item.paragraph.attributed.length <= rendered.location {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            let estimated = layout.paragraphs[lower...].prefix(while: { $0.textOffset < NSMaxRange(rendered) })
                .compactMap { item -> CGRect? in
                    guard let estimate = item.paragraph.estimate else { return nil }
                    let paragraphRange = NSRange(location: item.textOffset, length: item.paragraph.attributed.length)
                    let overlap = NSIntersectionRange(rendered, paragraphRange)
                    guard overlap.length > 0 else { return nil }
                    let unit = item.paragraph.height / CGFloat(max(1, paragraphRange.length))
                    return CGRect(
                        x: item.origin.x, y: item.origin.y + CGFloat(overlap.location - paragraphRange.location) * unit,
                        width: estimate.width, height: max(1, CGFloat(overlap.length) * unit))
                }
            return estimated.isEmpty ? measured : (measured + estimated).sorted { $0.minY < $1.minY }
        }
    }

    /// Formula, image and diagram objects contribute source TeX, alt text and
    /// visible labels respectively. Synthetic layout padding contributes no text.
    public func text(in range: TextRange) -> String {
        guard let selected = checked(range) else { return "" }
        return (semanticText as NSString).substring(with: selected)
    }

    public func wordRange(at position: TextPosition) -> TextRange? {
        guard position.owner == owner else { return nil }
        let text = semanticText as NSString
        guard text.length > 0 else { return nil }
        let index = min(max(0, position.offset), text.length - 1)
        var found: NSRange?
        text.enumerateSubstrings(
            in: text.paragraphRange(for: NSRange(location: index, length: 0)),
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, stop in
            if NSLocationInRange(index, range) {
                found = range
                stop.pointee = true
            }
        }
        return found.map(textRange)
    }

    public func ranges(matching query: String, options: SearchOptions = []) -> [TextRange] {
        guard !query.isEmpty else { return [] }
        let text = semanticText as NSString
        var flags: NSString.CompareOptions = []
        if !options.contains(.caseSensitive) { flags.insert(.caseInsensitive) }
        if !options.contains(.diacriticSensitive) { flags.insert(.diacriticInsensitive) }
        var cursor = 0
        var result: [TextRange] = []
        while cursor < text.length {
            let match = text.range(
                of: query, options: flags, range: NSRange(location: cursor, length: text.length - cursor),
                locale: Locale(identifier: "en_US_POSIX"))
            guard match.location != NSNotFound, match.length > 0 else { break }
            result.append(textRange(match))
            cursor = NSMaxRange(match)
        }
        return result
    }

    public func rect(for item: OutlineItem) -> CGRect? { rect(forAnchor: item.id) }

    /// Block top for a canonical outline ID, with no glyph or semantic lookup.
    package func readerAnchorY(for id: String) -> CGFloat? { layout.anchorPositions[id] }

    /// Accepts a slug or a URL fragment, including footnote anchors not in outline.
    public func rect(forAnchor anchor: String) -> CGRect? {
        let key = DocumentLink.anchorKey(anchor)
        guard let y = layout.anchorPositions[key] else { return nil }
        if let line = lines.first(where: { abs($0.rect.minY - y) < 0.01 }) { return line.rect }
        return CGRect(x: 0, y: y, width: size.width, height: 1)
    }

    /// Semantic target for an estimated heading/footnote position. Refine around
    /// this anchor before applying the final navigation inset.
    public func readingAnchor(forAnchor anchor: String) -> ReadingAnchor? {
        let key = DocumentLink.anchorKey(anchor)
        guard let y = layout.anchorPositions[key],
            let index = layout.paragraphs.firstIndex(where: { abs($0.origin.y - y) < 0.01 })
        else { return nil }
        return readingIndex.anchor(block: index, offset: 0)
    }

    public func link(at point: CGPoint) -> URL? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return layoutLock.withLock {
            guard let line = nearestLine(to: point), line.rect.contains(point) else { return nil }
            if let diagram = layout.diagrams[line.paragraph] {
                return diagram.link(at: point).flatMap { DocumentLink.url($0, relativeTo: baseURL) }
            }
            let item = layout.paragraphs[line.paragraph]
            let x = point.x - line.origin.x
            let insertion = line.shaped.stringIndex(forPosition: CGPoint(x: x, y: 0))
            var local = max(line.shaped.range.location, insertion)
            if local > line.shaped.range.location, x < line.shaped.offset(forStringIndex: local) { local -= 1 }
            let index = min(NSMaxRange(line.shaped.range) - 1, local)
            guard index >= 0, index < item.paragraph.attributed.length,
                let value = item.paragraph.attributed.attribute(.link, at: index, effectiveRange: nil)
            else { return nil }
            return DocumentLink.url(value, relativeTo: baseURL)
        }
    }

    /// Visible link geometry in document coordinates, with wide-table links
    /// shifted and clipped to the current horizontal table viewport.
    package func readerLinks(in rect: CGRect, tableOffsets: [Int: CGFloat] = [:]) -> [(url: URL, rect: CGRect)] {
        guard !rect.isEmpty, rect.minY.isFinite, rect.maxY.isFinite else { return [] }
        return layoutLock.withLock {
            var links: [(url: URL, rect: CGRect)] = []
            for line in lines where line.rect.minY < rect.maxY && line.rect.maxY > rect.minY {
                let item = layout.paragraphs[line.paragraph]
                var clip = rect
                var offset: CGFloat = 0
                if let index = item.tableIndex, layout.tables[index].isScrollable {
                    let table = layout.tables[index]
                    let requestedOffset = tableOffsets[index] ?? 0
                    if requestedOffset.isFinite {
                        offset = min(max(0, requestedOffset), table.contentWidth - table.frame.width)
                    }
                    clip = clip.intersection(table.frame)
                }
                guard !clip.isEmpty, line.rect.offsetBy(dx: -offset, dy: 0).intersects(clip) else { continue }
                func append(_ url: URL, _ bounds: CGRect) {
                    let visible = bounds.offsetBy(dx: -offset, dy: 0).intersection(clip)
                    if !visible.isEmpty { links.append((url, visible)) }
                }
                if let diagram = layout.diagrams[line.paragraph] {
                    for link in diagram.linkRects {
                        if let url = DocumentLink.url(link.target, relativeTo: baseURL) { append(url, link.rect) }
                    }
                    continue
                }
                let attributed = item.paragraph.attributed
                attributed.enumerateAttribute(.link, in: line.shaped.range) { value, range, _ in
                    guard let value, let url = DocumentLink.url(value, relativeTo: baseURL) else { return }
                    for bounds in line.shaped.linkRects(for: range, in: attributed) {
                        append(url, bounds.offsetBy(dx: line.origin.x, dy: line.origin.y))
                    }
                }
            }
            return links
        }
    }

    /// The first source line of the block at the viewport's top edge. The
    /// vertical space after a block belongs to that block until the next starts.
    package func readerSourceLine(atY y: CGFloat) -> Int? {
        let blocks = layout.sourceBlocks
        guard y.isFinite, !blocks.isEmpty else { return nil }
        var lower = 0
        var upper = blocks.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if blocks[middle].start <= y { lower = middle + 1 } else { upper = middle }
        }
        return blocks[max(0, lower - 1)].lines.lowerBound
    }

    /// Blank lines and non-rendered source resolve to the next block, or to
    /// the last block when the line is after the final rendered content.
    package func readerSourceTop(for line: Int) -> CGFloat? {
        var following: SourceBlockPosition?
        var preceding: SourceBlockPosition?
        for block in layout.sourceBlocks {
            if block.lines.contains(line) { return block.top }
            if line < block.lines.lowerBound {
                if following.map({ block.lines.lowerBound < $0.lines.lowerBound }) ?? true { following = block }
            } else if preceding.map({ block.lines.upperBound >= $0.lines.upperBound }) ?? true {
                preceding = block
            }
        }
        return (following ?? preceding)?.top
    }

    public func readingAnchor(atY y: CGFloat) -> ReadingAnchor {
        readingIndex.capture(y: y)
            ?? ReadingAnchor(blockKey: "", blockIndex: 0, offset: 0, blockCount: 0, verticalFraction: 0)
    }

    /// A semantic navigation target, including text in an unmeasured paragraph.
    /// Use this rather than capturing an approximate offscreen rectangle's Y.
    public func readingAnchor(at position: TextPosition) -> ReadingAnchor? {
        guard position.owner == owner else { return nil }
        let rendered = layout.textMap.renderedOffset(forSemanticOffset: position.offset)
        guard let index = layout.paragraphs.lastIndex(where: { $0.textOffset <= rendered }) else { return nil }
        let item = layout.paragraphs[index]
        let content = item.paragraph.semanticContent ?? ParagraphSemanticContent(item.paragraph.attributed)
        return readingIndex.anchor(
            block: index,
            offset: content.textMap.semanticOffset(
                forRenderedOffset: min(item.paragraph.attributed.length, max(0, rendered - item.textOffset))))
    }

    public func y(for anchor: ReadingAnchor) -> CGFloat? {
        if lines.isEmpty, anchor.blockCount == 0 { return 0 }
        return readingIndex.y(for: anchor)
    }

    // Snapshot image export must not re-layout mutable inputs.
    func imageData(
        scale: CGFloat, region: CGRect?, format: DocumentImageFormat = .png, quality: CGFloat = 0.9
    ) throws -> Data {
        if hasEstimatedGeometry {
            guard let region, !needsLayout(in: region) else { throw DocumentExportError.incompleteLayout }
        }
        return try layoutLock.withLock {
            var style = Typography()
            style.explicitTheme = DocumentTheme(
                id: "snapshot", name: "Snapshot", appearance: .light,
                document: ["paper": PlatformColors.srgb(backgroundColor)])
            return try DocumentExporter.imageData(
                layout, style: style, scale: scale, region: region, format: format, quality: quality)
        }
    }

    private func estimatedParagraph(containing offset: Int) -> PlacedText? {
        layout.paragraphs.first {
            $0.paragraph.estimate != nil && offset >= $0.textOffset
                && offset <= $0.textOffset + $0.paragraph.attributed.length
        }
    }

    private func position(_ offset: Int) -> TextPosition { TextPosition(owner: owner, offset: offset) }
    private func textRange(_ range: NSRange) -> TextRange {
        TextRange(position(range.location), position(NSMaxRange(range)))
    }
    private func checked(_ range: TextRange) -> NSRange? {
        guard range.lowerBound.owner == owner, range.upperBound.owner == owner else { return nil }
        let length = semanticLength
        let lower = min(length, max(0, range.lowerBound.offset))
        let upper = min(length, max(lower, range.upperBound.offset))
        return NSRange(location: lower, length: upper - lower)
    }

    private func nearestSemanticBoundary(to offset: Int) -> Int {
        SemanticTextBoundary.nearest(in: semanticSource, to: offset)
    }

    private func line(containing offset: Int) -> Line? {
        lines.first { NSLocationInRange(offset, $0.range) }
            ?? lines.last { $0.range.location <= offset } ?? lines.first
    }

    private func nearestLine(to point: CGPoint) -> Line? {
        lines.min { distance(from: point, to: $0.rect) < distance(from: point, to: $1.rect) }
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, max(0, point.x - rect.maxX))
        let dy = max(rect.minY - point.y, max(0, point.y - rect.maxY))
        return dx * dx + dy * dy
    }
}
