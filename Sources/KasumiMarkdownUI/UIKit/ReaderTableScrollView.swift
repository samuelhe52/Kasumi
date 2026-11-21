#if os(iOS)
import KasumiMarkdown
import UIKit

struct ReaderTablePreview: Sendable {
    let image: CGImage
    let rect: CGRect
}

/// Each table owns horizontal motion; vertical drags continue in the reader.
final class ReaderTableScrollView: UIScrollView, UIScrollViewDelegate {
    let tableID: Int
    var onScroll: (() -> Void)?
    var onBeginDragging: (() -> Void)?
    private let edgeMask = ReaderTableEdgeMask()
    private let canvas = UIView()
    private var seedLayer: CALayer?
    private var tileLayer: ReaderTableTileLayer?

    init(rendered: RenderedDocument, table: RenderedTable, scale: CGFloat, preview: ReaderTablePreview?) {
        tableID = table.id
        super.init(frame: table.frame)
        delegate = self
        contentInsetAdjustmentBehavior = .never
        isDirectionalLockEnabled = true
        alwaysBounceHorizontal = false
        showsVerticalScrollIndicator = false
        delaysContentTouches = false
        if #available(iOS 26.0, *) { topEdgeEffect.style = .soft }
        layer.mask = edgeMask
        canvas.isUserInteractionEnabled = false
        addSubview(canvas)
        refine(rendered: rendered, table: table, scale: scale, preview: preview)
        accessibilityIdentifier = "reader-table-\(table.id)"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Keep the scroll/gesture owner and its horizontal position while replacing
    /// snapshot-local painting data and estimated document-space placement.
    func refine(rendered: RenderedDocument, table: RenderedTable, scale: CGFloat, preview: ReaderTablePreview?) {
        let previousOffset = contentOffset
        let horizontalExtentChanged = contentSize.width != table.contentWidth || bounds.width != table.frame.width
        frame = table.frame
        let components =
            rendered.backgroundColor.converted(
                to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? [
                1, 1, 1, 1
            ]
        indicatorStyle = components.prefix(3).reduce(0, +) < 1.5 ? .white : .black
        let size = CGSize(width: table.contentWidth, height: table.frame.height)
        if contentSize != size { contentSize = size }
        canvas.frame = CGRect(origin: .zero, size: contentSize)
        seedLayer?.removeFromSuperlayer()
        tileLayer?.removeFromSuperlayer()
        seedLayer = nil
        if let preview {
            let seed = CALayer()
            seed.frame = preview.rect
            seed.contents = preview.image
            seed.contentsScale = scale
            canvas.layer.addSublayer(seed)
            seedLayer = seed
        }
        let tiles = ReaderTableTileLayer(rendered: rendered, index: table.id)
        tiles.frame = canvas.bounds
        tiles.contentsScale = scale
        tiles.tileSize = CGSize(width: 512, height: 512)
        canvas.layer.addSublayer(tiles)
        tileLayer = tiles
        let clamped = CGPoint(x: min(max(0, previousOffset.x), max(0, contentSize.width - bounds.width)), y: 0)
        // Preserve an in-flight edge bounce when horizontal geometry is stable.
        if horizontalExtentChanged, contentOffset != clamped { setContentOffset(clamped, animated: false) }
        updateEdgeMask()
    }

    func invalidateImage(in rect: CGRect) { tileLayer?.setNeedsDisplay(rect) }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateEdgeMask()
    }

    private func updateEdgeMask() {
        edgeMask.update(viewport: bounds, contentWidth: contentSize.width)
    }

    // Keep UIKit's native pan admission: a touch during deceleration can begin
    // the pan before it has velocity. A velocity gate can reject that takeover.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateEdgeMask()
        onScroll?()
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { onBeginDragging?() }
}

fileprivate final class ReaderTableTileLayer: CATiledLayer {
    private let rendered: RenderedDocument?
    private let index: Int
    init(rendered: RenderedDocument, index: Int) {
        self.rendered = rendered
        self.index = index
        super.init()
    }
    override init(layer: Any) {
        rendered = (layer as? ReaderTableTileLayer)?.rendered
        index = (layer as? ReaderTableTileLayer)?.index ?? 0
        super.init(layer: layer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override class func fadeDuration() -> CFTimeInterval { 0 }
    override func draw(in context: CGContext) {
        rendered?.drawTable(at: index, in: context, rect: context.boundingBoxOfClipPath)
    }
}
#endif
