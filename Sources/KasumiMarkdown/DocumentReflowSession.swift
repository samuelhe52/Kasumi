import Foundation

/// Retains text preparation and current-width geometry for one document.
/// Create a new session when content, style, available fonts, or resources change.
/// Calls are serialized; snapshots remain immutable and safe to retain.
/// A completed idle snapshot may be reused by same-width viewport requests.
public actor DocumentReflowSession {
    private let document: MarkdownDocument
    private let style: RenderStyle
    private let scrollableTables: Bool
    private let readerImages: ReaderImageCache?
    private let preparesLocalImageLayout: Bool
    private let preparation = ReflowPreparation()
    private var layoutWidth: CGFloat?
    private(set) var warmCursor = 0
    private var warmEpoch = UUID()
    private var warmSnapshot: RenderedDocument?
    private lazy var supportsCompleteWarmup: Bool = {
        guard document.parsed.blocks.count <= 1_000 else { return false }
        var units = 0
        var imageOccurrences = 0
        var totalTableCells = 0
        var largestTable = 0
        var knownSources = Set<String>()
        for block in document.parsed.blocks {
            guard block.kind != .diagram,
                block.text.utf16.count <= 4_000 else { return false }
            let cells = block.rows.flatMap { $0 }
            guard cells.count <= (preparesLocalImageLayout ? 128 : 64),
                cells.allSatisfy({ $0.reduce(0) { $0 + $1.text.utf16.count } <= 4_000 }) else { return false }
            totalTableCells += cells.count
            largestTable = max(largestTable, cells.count)
            for run in block.runs + cells.flatMap({ $0 }) {
                if run.traits.contains(.image) {
                    imageOccurrences += 1
                    guard preparesLocalImageLayout, imageOccurrences <= 256, let source = run.imageSource
                    else { return false }
                    if knownSources.insert(source).inserted {
                        guard let image = DocumentImageStore.shared.readerSource(
                            for: source, baseURL: document.parsed.baseURL),
                            image.url.isFileURL || image.url.scheme?.lowercased() == "data"
                        else { return false }
                    }
                }
                units += run.text.utf16.count
                if units > 250_000 { return false }
            }
        }
        // Permit wider tables in this opt-in path while bounding total cell
        // work. Preserve the text-only envelope.
        return imageOccurrences > 0 ? totalTableCells <= 512 : largestTable <= 64
    }()

    private func useWidth(_ width: CGFloat) {
        guard layoutWidth != width else { return }
        layoutWidth = width
        warmCursor = 0
        warmEpoch = UUID()
        warmSnapshot = nil
    }

    public init(_ document: MarkdownDocument, style: RenderStyle, scrollableTables: Bool = false) {
        self.init(document, style: style, scrollableTables: scrollableTables, readerDisplayScale: nil)
    }

    /// A display scale opts into geometry-only image attachments. Interactive
    /// clients request the viewport's pixels separately after presentation.
    public init(
        _ document: MarkdownDocument, style: RenderStyle, scrollableTables: Bool = false,
        readerDisplayScale: CGFloat?
    ) {
        self.init(
            document, style: style, scrollableTables: scrollableTables,
            readerDisplayScale: readerDisplayScale, preparesLocalImageLayout: false)
    }

    /// Opt in to complete idle geometry for bounded local and embedded images.
    /// A valid reader display scale is required to keep pixels deferred.
    public init(
        _ document: MarkdownDocument, style: RenderStyle, scrollableTables: Bool = false,
        readerDisplayScale: CGFloat?, preparesLocalImageLayout: Bool
    ) {
        self.document = document
        self.style = style
        self.scrollableTables = scrollableTables
        readerImages = readerDisplayScale.flatMap {
            $0.isFinite && $0 > 0 ? ReaderImageCache(displayScale: $0) : nil
        }
        self.preparesLocalImageLayout = preparesLocalImageLayout && readerImages != nil
    }

    /// Makes remote dimensions and encoded sources available for reader layout.
    @discardableResult public static func preloadImages(_ document: MarkdownDocument) async -> Bool {
        await DocumentImageStore.shared.preload(document.parsed, forReader: true)
    }

    public func render(width: CGFloat) -> RenderedDocument {
        useWidth(width)
        return autoreleasepool {
            RenderedDocument(
                document, width: width, style: style, scrollableTables: scrollableTables, preparation: preparation,
                readerImages: readerImages)
        }
    }

    /// Measures paragraphs near the anchor, with overscan, and estimates offscreen
    /// heights. Text/search remain complete; offscreen geometry is approximate.
    /// Request another snapshot when `needsLayout(in:)` is true after scrolling.
    /// Offscreen prose, tables and math keep semantic text with estimated geometry.
    /// Visible tables refine as a unit. Resource-dependent images and diagram
    /// fallbacks keep their exact storage path. After idle preparation completes,
    /// requests at that width reuse the complete immutable snapshot and its lock.
    public func render(width: CGFloat, viewportHeight: CGFloat, anchor: ReadingAnchor? = nil) -> RenderedDocument {
        useWidth(width)
        if let warmSnapshot { return warmSnapshot }
        return autoreleasepool {
            RenderedDocument(
                document, width: width, style: style, scrollableTables: scrollableTables, preparation: preparation,
                viewport: viewportHeight.isFinite && viewportHeight > 0
                    ? ViewportLayoutRequest(height: viewportHeight, anchor: anchor) : nil,
                readerImages: readerImages)
        }
    }

    /// Optional idle work for bounded documents. Check cancellation between
    /// batches and yield the actor so visible requests can take priority.
    /// Returns nil for workloads outside the resource envelope. Width changes
    /// invalidate progress; cancellation retains completed preparation at that width.
    public func prepareForScrolling(width: CGFloat) async throws -> RenderedDocument? {
        try Task.checkCancellation()
        guard width.isFinite, width > 0, supportsCompleteWarmup else { return nil }
        useWidth(width)
        let epoch = warmEpoch
        var typography = style.typography
        typography.readerImages = readerImages
        while warmSnapshot == nil {
            try Task.checkCancellation()
            guard warmEpoch == epoch else { throw CancellationError() }
            let count = autoreleasepool {
                let construction = ViewportConstruction()
                construction.selected = Set(warmCursor..<(warmCursor + 8))
                let count = DocumentTypesetter.layout(
                    document.parsed, width: width, style: typography, insets: style.insets,
                    scrollableTables: scrollableTables, preparation: preparation, viewport: construction,
                    buildSemanticContent: false, buildTextStorage: false).paragraphs.count
                preparation.discardBreakItems(requiringGeometry: true)
                return count
            }
            warmCursor += 8
            if warmCursor >= count {
                warmSnapshot = render(width: width)
                preparation.discardBreakItems(requiringGeometry: false)
                break
            }
            await Task.yield()
        }
        try Task.checkCancellation()
        guard warmEpoch == epoch else { throw CancellationError() }
        return warmSnapshot
    }

}

/// Actor-owned text/measurement preparation. Glyph paint values use a separate
/// synchronized cache; CTTypesetter/CTLine/CTRun objects belong to snapshots.
final class ReflowPreparation {
    private struct Key: Hashable {
        let block: Int
        let slot: Int
    }
    private struct Request: Equatable {
        let runs: [InlineRun]
        let size: Double?
        let heading: Bool
        let code: Bool
        let level: Int?
    }
    private struct Entry {
        let request: Request
        let attributed: NSAttributedString
    }
    private var attributes: [Key: Entry] = [:]
    private var paragraphs: [ObjectIdentifier: ParagraphPreparation] = [:]
    private let glyphPaintStorage = FragmentGlyphPaintCache.Storage(countLimit: 8192, costLimit: 8 * 1024 * 1024)
    private var retained = Set<ObjectIdentifier>()
    private(set) var attributedBuilds = 0
    private(set) var shapedBuilds = 0
    private(set) var semanticBuilds = 0
    var shapedParagraphCount: Int { paragraphs.values.filter(\.didShape).count }

    func discardBreakItems(requiringGeometry: Bool) {
        for paragraph in paragraphs.values where !requiringGeometry || paragraph.geometry != nil {
            paragraph.discardBreakItems()
        }
    }
    private var documentParagraphs: [ParagraphSemanticContent] = []
    private var documentSemantic: DocumentSemanticContent?
    private var placeholders: [Key: (runs: [InlineRun], value: NSAttributedString)] = [:]
    private struct TableWidthRequest: Equatable {
        let rows: [[[InlineRun]]]
        let width: CGFloat
        let em: CGFloat
        let padding: CGFloat
        let scrollable: Bool
    }
    private var tableWidthCache: [Int: (request: TableWidthRequest, values: [CGFloat])] = [:]

    func placeholder(block: Int, slot: Int, runs: [InlineRun]) -> NSAttributedString {
        let key = Key(block: block, slot: slot)
        if let old = placeholders[key], old.runs == runs { return old.value }
        if let old = placeholders[key] {
            let id = ObjectIdentifier(old.value)
            retained.remove(id)
            paragraphs[id] = nil
        }
        let value = NSAttributedString(string: runs.map { $0.footnoteDisplay ?? $0.text }.joined())
        placeholders[key] = (runs, value)
        retained.insert(ObjectIdentifier(value))
        return value
    }

    func cachedTableWidths(
        block: Int, rows: [[[InlineRun]]], width: CGFloat, em: CGFloat, padding: CGFloat, scrollable: Bool
    ) -> [CGFloat]? {
        guard !rows.joined().joined().contains(where: { $0.traits.contains(.image) }) else { return nil }
        let request = TableWidthRequest(rows: rows, width: width, em: em, padding: padding, scrollable: scrollable)
        guard let old = tableWidthCache[block], old.request == request else { return nil }
        return old.values
    }

    func tableWidths(
        block: Int, rows: [[[InlineRun]]], width: CGFloat, em: CGFloat, padding: CGFloat, scrollable: Bool,
        build: () -> [CGFloat]
    ) -> [CGFloat] {
        // Image availability/dimensions can change independently of the session.
        guard !rows.joined().joined().contains(where: { $0.traits.contains(.image) }) else { return build() }
        let request = TableWidthRequest(rows: rows, width: width, em: em, padding: padding, scrollable: scrollable)
        if let old = tableWidthCache[block], old.request == request { return old.values }
        let values = build()
        tableWidthCache[block] = (request, values)
        return values
    }

    private var viewportSelection: (width: CGFloat, paragraphs: Set<Int>)?

    func selectedParagraphs(width: CGFloat) -> Set<Int> {
        viewportSelection?.width == width ? viewportSelection!.paragraphs : []
    }

    func rememberSelectedParagraphs(_ paragraphs: Set<Int>, width: CGFloat) {
        viewportSelection = (width, paragraphs)
    }

    private var heights: [Int: (width: CGFloat, height: CGFloat)] = [:]

    func height(at index: Int, width: CGFloat, prepared: ParagraphPreparation, lineHeight: CGFloat) -> CGFloat {
        if let old = heights[index] {
            if old.width == width { return old.height }
            return max(lineHeight, ceil(old.height / lineHeight * old.width / width) * lineHeight)
        }
        return max(lineHeight, ceil(prepared.estimatedAdvance / width) * lineHeight)
    }

    func measuredHeight(_ height: CGFloat, at index: Int, width: CGFloat) {
        heights[index] = (width, height)
    }

    func attributed(
        block: Int, slot: Int, runs: [InlineRun], size: Double?, heading: Bool, code: Bool, level: Int?,
        build: () -> NSAttributedString
    ) -> NSAttributedString {
        // Images depend on measure/resource availability. Math attachments own
        // Core Text lines, so they must not be shared by independent snapshots.
        guard !runs.contains(where: { !$0.traits.intersection([.image, .math]).isEmpty }) else { return build() }
        let key = Key(block: block, slot: slot)
        let request = Request(runs: runs, size: size, heading: heading, code: code, level: level)
        if let entry = attributes[key], entry.request == request { return entry.attributed }
        if let old = attributes[key] {
            let id = ObjectIdentifier(old.attributed)
            paragraphs[id] = nil
            retained.remove(id)
        }
        let attributed = NSAttributedString(attributedString: build())
        attributes[key] = Entry(request: request, attributed: attributed)
        retained.insert(ObjectIdentifier(attributed))
        attributedBuilds += 1
        return attributed
    }

    func paragraph(_ attributed: NSAttributedString, fontSize: CGFloat, verbatim: Bool) -> ParagraphPreparation? {
        let id = ObjectIdentifier(attributed)
        guard retained.contains(id) else { return nil }
        if let existing = paragraphs[id], existing.fontSize == fontSize, existing.verbatim == verbatim {
            return existing
        }
        let value = ParagraphPreparation(
            attributed, fontSize: fontSize, verbatim: verbatim, glyphPaintStorage: glyphPaintStorage)
        paragraphs[id] = value
        shapedBuilds += 1
        return value
    }

    func semanticContent(paragraphs: [PlacedText], storage: NSAttributedString) -> DocumentSemanticContent {
        let contents = paragraphs.map {
            $0.paragraph.semanticContent ?? ParagraphSemanticContent($0.paragraph.attributed)
        }
        // Rebuilt attachments may change rendered offsets even when their alt
        // text is unchanged. Compare the complete maps, not just semantic strings.
        if let documentSemantic, contents.count == documentParagraphs.count,
            zip(contents, documentParagraphs).allSatisfy({ $0 === $1 || $0.textMap == $1.textMap })
        {
            return documentSemantic
        }
        let value = DocumentSemanticContent(DocumentTextMap(storage), reusing: documentSemantic)
        documentParagraphs = contents
        documentSemantic = value
        semanticBuilds += 1
        return value
    }

}

final class ParagraphPreparation {
    private let glyphPaintStorage: FragmentGlyphPaintCache.Storage?
    lazy var glyphPaintCache = FragmentGlyphPaintCache(storage: glyphPaintStorage)
    let attributed: NSAttributedString
    let hasRTL: Bool
    let fontSize: CGFloat
    let verbatim: Bool
    private(set) var didShape = false
    lazy var input: ShapedParagraphInput? = {
        guard !verbatim && !hasRTL && attributed.length > 0 else { return nil }
        didShape = true
        return ParagraphShaper.shape(attributed, fallbackSize: fontSize)
    }()
    let hasDecorationCandidates: Bool
    let semanticContent: ParagraphSemanticContent
    let estimatedAdvance: CGFloat
    var geometry: ParagraphLayoutGeometry?
    private var cachedItems: (indent: Float, options: ParagraphProfileOptions, value: ParagraphEngine.Prepared)?
    private(set) var itemBuilds = 0

    func discardBreakItems() { cachedItems = nil }

    func items(indent: Float, options: ParagraphProfileOptions) -> ParagraphEngine.Prepared? {
        guard let input else { return nil }
        if let cachedItems, cachedItems.indent == indent, cachedItems.options == options { return cachedItems.value }
        let value = ParagraphEngine.prepare(
            clusters: input.clusters, runs: input.metrics, indent: indent, options: options)
        cachedItems = (indent, options, value)
        itemBuilds += 1
        return value
    }

    init(
        _ source: NSAttributedString, fontSize: CGFloat, verbatim: Bool,
        glyphPaintStorage: FragmentGlyphPaintCache.Storage? = nil
    ) {
        self.glyphPaintStorage = glyphPaintStorage
        self.fontSize = fontSize
        self.verbatim = verbatim
        attributed = TextUnderline.normalized(source)
        hasDecorationCandidates = TextUnderline.hasCandidates(in: attributed)
        semanticContent = ParagraphSemanticContent(attributed)
        hasRTL = attributed.string.unicodeScalars.contains {
            (0x0590...0x08ff).contains($0.value) || (0xfb1d...0xfdff).contains($0.value)
                || (0xfe70...0xfefc).contains($0.value)
        }
        // Estimation must not shape the entire offscreen document. Refine these
        // approximate advances with actual heights when the paragraph is visited.
        estimatedAdvance = attributed.string.unicodeScalars.reduce(CGFloat(0)) {
            $0 + fontSize * ($1.value < 0x2e80 ? 0.5 : 1)
        }
    }
}
