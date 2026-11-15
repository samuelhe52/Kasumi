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
/// objects are confined to construction, then accessed under `layoutLock` for
/// drawing and geometry queries. Immutable CGImage/CGColor/font-table assets are
/// retained, not mutated. Global image reads use NSCache's synchronized methods;
/// bundled font registration and math assets use Swift's serialized static lets.
/// The lock protects shared CTLine/CTRun objects, not mutable Kasumi draw state:
/// Apple's Core Text contract confines layout objects to one operation/queue/thread
/// even though individual functions and font objects are thread-safe.
/// https://developer.apple.com/documentation/CoreText
public final class RenderedDocument: @unchecked Sendable {
    public let size: CGSize
    public let backgroundColor: CGColor
    private let owner = UUID()
    private let layout: DocumentLayout
    private let readingIndex: ReadingPositionIndex
    private let baseURL: URL?
    private let layoutLock = NSLock()
    private let lines: [Line]
    private let semanticBoundaries: [Int]
    private let semanticText: String

    private struct Line {
        let paragraph: Int
        let shaped: ShapedLine
        let origin: CGPoint
        let range: NSRange
        let rect: CGRect
    }

    public init(_ document: MarkdownDocument, width: CGFloat, style: RenderStyle) {
        precondition(width.isFinite && width > 0, "Layout width must be finite and positive")
        let insets = style.insets
        precondition(
            [insets.top, insets.left, insets.bottom, insets.right].allSatisfy { $0.isFinite && $0 >= 0 },
            "Layout insets must be finite and nonnegative")
        let typography = style.typography
        var built = DocumentTypesetter.layout(document.parsed, width: width, style: typography, insets: insets)
        built.text = NSAttributedString(attributedString: built.text)
        layout = built
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
        // place() appends a storage separator after every paragraph; the last
        // separator is not document content and must not create a phantom caret.
        let text = built.textMap.string.hasSuffix("\n") ? String(built.textMap.string.dropLast()) : built.textMap.string
        semanticText = text
        var offset = 0
        var boundaries = [0]
        for character in text {
            offset += String(character).utf16.count
            boundaries.append(offset)
        }
        semanticBoundaries = boundaries
    }

    /// `rect` and the CGContext must use document coordinates (top-left, y down).
    /// Each caller owns its context. The clip protects adjacent tiles, and the
    /// existing sourceRange path excludes off-tile text/attachment drawing.
    public func draw(in context: CGContext, rect: CGRect) {
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
            DocumentTypesetter.draw(layout, in: context, sourceRange: (visible.minY - 4)..<(visible.maxY + 4))
        }
    }

    public var documentRange: TextRange {
        TextRange(position(0), position(semanticText.utf16.count))
    }

    public func position(closestTo point: CGPoint) -> TextPosition {
        guard point.x.isFinite, point.y.isFinite else { return documentRange.lowerBound }
        return layoutLock.withLock {
            guard let line = nearestLine(to: point) else { return position(0) }
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
            guard let line = line(containing: rendered) else {
                return CGRect(x: 0, y: 0, width: 1, height: 1)
            }
            let item = layout.paragraphs[line.paragraph]
            let x = line.origin.x + line.shaped.offset(forStringIndex: rendered - item.textOffset)
            return CGRect(x: x, y: line.rect.minY, width: 1, height: line.rect.height)
        }
    }

    public func selectionRects(for range: TextRange) -> [CGRect] {
        guard let semantic = checked(range), semantic.length > 0,
            let rendered = layout.textMap.renderedRange(for: semantic)
        else { return [] }
        return layoutLock.withLock {
            lines.compactMap { line in
                let overlap = NSIntersectionRange(rendered, line.range)
                guard overlap.length > 0 else { return nil }
                let item = layout.paragraphs[line.paragraph]
                let start = line.shaped.offset(forStringIndex: overlap.location - item.textOffset)
                let end = line.shaped.offset(
                    forStringIndex: NSMaxRange(overlap) - item.textOffset, affinity: .precedingFragment)
                return CGRect(
                    x: line.origin.x + min(start, end), y: line.rect.minY,
                    width: abs(end - start), height: line.rect.height)
            }
        }
    }

    /// Formula/image/diagram objects expand back to source TeX, alt text, or
    /// diagram source; code-capsule padding and synthetic glyphs contribute none.
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
            in: NSRange(location: 0, length: text.length), options: [.byWords, .substringNotRequired]
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

    /// Accepts a slug or a URL fragment, including footnote anchors not in outline.
    public func rect(forAnchor anchor: String) -> CGRect? {
        let key = (anchor.hasPrefix("#") ? String(anchor.dropFirst()) : anchor).removingPercentEncoding ?? anchor
        guard let y = layout.anchorPositions[key] else { return nil }
        if let line = lines.first(where: { abs($0.rect.minY - y) < 0.01 }) { return line.rect }
        return CGRect(x: 0, y: y, width: size.width, height: 1)
    }

    public func link(at point: CGPoint) -> URL? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return layoutLock.withLock {
            guard let line = nearestLine(to: point), line.rect.contains(point) else { return nil }
            let item = layout.paragraphs[line.paragraph]
            let x = point.x - line.origin.x
            let insertion = line.shaped.stringIndex(forPosition: CGPoint(x: x, y: 0))
            var local = max(line.shaped.range.location, insertion)
            if local > line.shaped.range.location, x < line.shaped.offset(forStringIndex: local) { local -= 1 }
            let index = min(NSMaxRange(line.shaped.range) - 1, local)
            guard index >= 0, index < item.paragraph.attributed.length,
                let value = item.paragraph.attributed.attribute(.link, at: index, effectiveRange: nil)
            else { return nil }
            if let url = value as? URL { return url }
            guard let string = value as? String else { return nil }
            return URL(string: string, relativeTo: string.hasPrefix("#") ? nil : baseURL)?.absoluteURL
        }
    }

    public func readingAnchor(atY y: CGFloat) -> ReadingAnchor {
        readingIndex.capture(y: y)
            ?? ReadingAnchor(blockKey: "", blockIndex: 0, offset: 0, blockCount: 0, verticalFraction: 0)
    }

    public func y(for anchor: ReadingAnchor) -> CGFloat? {
        if lines.isEmpty, anchor.blockCount == 0 { return 0 }
        return readingIndex.y(for: anchor)
    }

    // The PNG exporter must use the same snapshot, not re-layout mutable inputs.
    func imageData(scale: CGFloat, region: CGRect?) throws -> Data {
        try layoutLock.withLock {
            var style = Typography()
            style.explicitTheme = DocumentTheme(
                id: "snapshot", name: "Snapshot", appearance: .light,
                document: ["paper": PlatformColors.srgb(backgroundColor)])
            return try DocumentExporter.imageData(layout, style: style, scale: scale, region: region)
        }
    }

    private func position(_ offset: Int) -> TextPosition { TextPosition(owner: owner, offset: offset) }
    private func textRange(_ range: NSRange) -> TextRange {
        TextRange(position(range.location), position(NSMaxRange(range)))
    }
    private func checked(_ range: TextRange) -> NSRange? {
        guard range.lowerBound.owner == owner, range.upperBound.owner == owner else { return nil }
        let length = semanticText.utf16.count
        let lower = min(length, max(0, range.lowerBound.offset))
        let upper = min(length, max(lower, range.upperBound.offset))
        return NSRange(location: lower, length: upper - lower)
    }

    private func nearestSemanticBoundary(to offset: Int) -> Int {
        var lower = 0
        var upper = semanticBoundaries.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if semanticBoundaries[middle] < offset { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return 0 }
        guard lower < semanticBoundaries.count else { return semanticBoundaries.last ?? 0 }
        let a = semanticBoundaries[lower - 1]
        let b = semanticBoundaries[lower]
        return offset - a <= b - offset ? a : b
    }

    private func line(containing offset: Int) -> Line? {
        lines.first { NSLocationInRange(offset, $0.range) }
            ?? lines.last { $0.range.location <= offset } ?? lines.first
    }

    private func nearestLine(to point: CGPoint) -> Line? {
        func distance(_ line: Line) -> CGFloat {
            let dx = max(line.rect.minX - point.x, max(0, point.x - line.rect.maxX))
            let dy = max(line.rect.minY - point.y, max(0, point.y - line.rect.maxY))
            return dx * dx + dy * dy
        }
        return lines.min { distance($0) < distance($1) }
    }
}
