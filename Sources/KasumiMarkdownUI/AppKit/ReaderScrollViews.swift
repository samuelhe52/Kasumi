#if os(macOS)
import AppKit
import KasumiMarkdown

@MainActor final class ReaderVerticalScrollView: NSScrollView {
    weak var owner: MarkdownReaderView?

    override func scrollWheel(with event: NSEvent) {
        owner?.userWillScroll()
        super.scrollWheel(with: event)
    }

    override func performTextFinderAction(_ sender: Any?) {
        if let action = readerFindAction(from: sender) { owner?.performFindAction(action) }
        else { super.performTextFinderAction(sender) }
    }
}

@MainActor final class ReaderTableScrollView: NSScrollView {
    weak var owner: MarkdownReaderView?
    let tableCanvas = ReaderTableCanvas()
    private var installing = false
    private var usesHorizontalGesture: Bool?

    init(frame frameRect: NSRect, scrollerClass: NSScroller.Type = NSScroller.self) {
        super.init(frame: frameRect)
        if scrollerClass != NSScroller.self { horizontalScroller = scrollerClass.init(frame: .zero) }
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        drawsBackground = false
        verticalScrollElasticity = .none
        horizontalScrollElasticity = .none
        tableCanvas.host = self
        documentView = tableCanvas
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(horizontalPositionChanged), name: NSView.boundsDidChangeNotification,
            object: contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init() instead") }

    func replaceHorizontalScroller(with type: NSScroller.Type) {
        let offset = contentView.bounds.minX
        let wasInstalling = installing
        installing = true
        horizontalScroller = type.init(frame: horizontalScroller?.frame ?? .zero)
        tile()
        applyOffset(offset)
        installing = wasInstalling
    }

    func install(_ table: RenderedTable, offset: CGFloat) {
        installing = true
        frame = table.frame
        tableCanvas.table = table
        tableCanvas.frame = CGRect(origin: .zero, size: CGSize(width: table.contentWidth, height: table.frame.height))
        applyOffset(offset)
        updateEdgeMask()
        installing = false
        tableCanvas.needsDisplay = true
    }

    func applyOffset(_ offset: CGFloat) {
        contentView.scroll(to: CGPoint(x: offset, y: 0))
        reflectScrolledClipView(contentView)
    }

    @objc private func horizontalPositionChanged() {
        updateEdgeMask()
        guard !installing, let table = tableCanvas.table else { return }
        owner?.tableOffsetChanged(contentView.bounds.minX, table: table)
    }

    private let edgeMask = ReaderTableEdgeMask()

    override func layout() {
        super.layout()
        updateEdgeMask()
    }

    private func updateEdgeMask() {
        guard let table = tableCanvas.table else { return }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return }
        edgeMask.update(viewport: contentView.bounds, contentWidth: table.contentWidth, maskBounds: layer.bounds)
        // The scroller is a sibling of the clip view.
        if layer.mask !== edgeMask { layer.mask = edgeMask }
    }

    override func scrollWheel(with event: NSEvent) {
        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        if event.phase.contains(.began) { usesHorizontalGesture = horizontal }
        let insideGesture = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if (insideGesture ? (usesHorizontalGesture ?? horizontal) : horizontal) {
            super.scrollWheel(with: event)
        } else {
            owner?.scrollVertically(with: event)
        }
        if event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) {
            usesHorizontalGesture = nil
        }
    }

    override func tile() {
        super.tile()
        // The table frame comes from the typesetter and includes its bottom
        // rule. Keep it all in the viewport with the legacy knob above it.
        if scrollerStyle == .legacy { contentView.frame = bounds }
    }
}

@MainActor final class ReaderTableCanvas: NSView {
    weak var host: ReaderTableScrollView?
    var table: RenderedTable?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let owner = host?.owner,
            let rendered = owner.rendered, let table
        else { return }
        rendered.drawTable(
            at: table.id, in: context, rect: dirtyRect, highlights: owner.highlights(in: dirtyRect, table: table))
    }

    override func mouseDown(with event: NSEvent) { host?.owner?.canvas.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { host?.owner?.canvas.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { host?.owner?.canvas.mouseUp(with: event) }
}

/// A prepainted viewport image. Background prepaint hands only this immutable
/// value back to the main actor, never the context it drew into.
struct ReaderViewportBitmap: Sendable {
    let image: CGImage
    let rect: CGRect
    let pixelSize: CGSize

    static func paint(
        _ document: RenderedDocument, rect: CGRect, scale: CGFloat, colorSpace: CGColorSpace,
        excludingScrollableTables: Bool
    ) -> ReaderViewportBitmap? {
        let width = ceil(rect.width * scale)
        let height = ceil(rect.height * scale)
        guard !rect.isEmpty, width > 0, height > 0, width * height <= 32_000_000 else { return nil }
        return autoreleasepool {
            guard let context = CGContext(
                data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.translateBy(x: 0, y: CGFloat(context.height))
            context.scaleBy(x: scale, y: -scale)
            context.translateBy(x: -rect.minX, y: -rect.minY)
            document.draw(in: context, rect: rect, excludingScrollableTables: excludingScrollableTables)
            guard let image = context.makeImage() else { return nil }
            // The raster was rounded up to a device pixel. Do not stretch it
            // back down while blitting, which would resample text at the edges.
            let pixelSize = CGSize(width: width / scale, height: height / scale)
            return ReaderViewportBitmap(image: image, rect: rect, pixelSize: pixelSize)
        }
    }
}
#endif
