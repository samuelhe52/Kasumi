import KasumiMarkdown
import UIKit

struct ReaderTablePreview: Sendable {
    let image: CGImage
    let rect: CGRect
}

/// Each table owns horizontal motion; vertical drags continue in the reader.
final class ReaderTableScrollView: UIScrollView, UIScrollViewDelegate {
    var onScroll: (() -> Void)?
    var onBeginDragging: (() -> Void)?
    private let edgeMask = ReaderTableEdgeMask()

    init(rendered: RenderedDocument, table: RenderedTable, scale: CGFloat, preview: ReaderTablePreview?) {
        super.init(frame: table.frame)
        delegate = self
        contentInsetAdjustmentBehavior = .never
        isDirectionalLockEnabled = true
        alwaysBounceHorizontal = false
        showsVerticalScrollIndicator = false
        delaysContentTouches = false
        topEdgeEffect.style = .soft
        layer.mask = edgeMask
        let components =
            rendered.backgroundColor.converted(
                to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? [
                1, 1, 1, 1
            ]
        indicatorStyle = components.prefix(3).reduce(0, +) < 1.5 ? .white : .black
        contentSize = CGSize(width: table.contentWidth, height: table.frame.height)
        let content = UIView(frame: CGRect(origin: .zero, size: contentSize))
        content.isUserInteractionEnabled = false
        if let preview {
            let seed = CALayer()
            seed.frame = preview.rect
            seed.contents = preview.image
            seed.contentsScale = scale
            content.layer.addSublayer(seed)
        }
        let tiles = ReaderTableTileLayer(rendered: rendered, index: table.id)
        tiles.frame = content.bounds
        tiles.contentsScale = scale
        tiles.tileSize = CGSize(width: 512, height: 512)
        content.layer.addSublayer(tiles)
        addSubview(content)
        accessibilityIdentifier = "reader-table-\(table.id)"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
