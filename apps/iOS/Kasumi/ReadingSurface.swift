import KasumiMarkdown
import SwiftUI
import UIKit

struct ReadingSurface: UIViewRepresentable {
    let document: MarkdownDocument
    let revision: UUID
    let style: RenderStyle
    /// `FontStore.revision`: a face that became available changes the rendering
    /// even when the style's resolved families stay the same.
    let fontRevision: Int
    let outline: [OutlineItem]
    let fileURL: URL?
    let viewport: ReaderViewport
    let openLink: (URL) -> Void

    func makeUIView(context: Context) -> ReaderScrollView { ReaderScrollView() }
    func updateUIView(_ view: ReaderScrollView, context: Context) {
        view.update(
            document: document, revision: revision, style: style, fontRevision: fontRevision, outline: outline,
            fileURL: fileURL, viewport: viewport, openLink: openLink)
    }
    static func dismantleUIView(_ view: ReaderScrollView, coordinator: ()) { view.finish() }
}

final class ReaderScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let headingTopInset: CGFloat = 15

    // Pages swap inside a permanent container so the scroll view's own subviews
    // never change; replacing them directly drops the soft top edge effect until
    // the next scroll.
    private let content = UIView()
    private var page: ReaderPageView?
    private var rendered: RenderedDocument?
    private let openingIndicator = UIActivityIndicatorView(style: .medium)
    private var document: MarkdownDocument?
    private var revision: UUID?
    private var style: RenderStyle?
    private var fontRevision = 0
    private var outline: [OutlineItem] = []
    private var headings: [(String, CGFloat)] = []
    private var fileURL: URL?
    private weak var viewport: ReaderViewport?
    private var openLink: ((URL) -> Void)?
    private var restoreAnchor: ReadingAnchor?
    private var layoutTask: Task<Void, Never>?
    private var generation = UUID()
    private var requestedWidth: CGFloat = 0
    private var pageScale: CGFloat = 1
    private var lastJump: UUID?
    private var adjusting = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        alwaysBounceVertical = true
        contentInsetAdjustmentBehavior = .automatic
        topEdgeEffect.style = .soft
        addSubview(content)
        openingIndicator.hidesWhenStopped = true
        openingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(openingIndicator)
        NSLayoutConstraint.activate([
            openingIndicator.centerXAnchor.constraint(equalTo: frameLayoutGuide.centerXAnchor),
            openingIndicator.centerYAnchor.constraint(equalTo: frameLayoutGuide.centerYAnchor)
        ])
        openingIndicator.startAnimating()
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
        accessibilityLabel = "Document reading surface"
        accessibilityIdentifier = "reader-surface"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { layoutTask?.cancel() }

    func update(
        document: MarkdownDocument, revision: UUID, style: RenderStyle, fontRevision: Int, outline: [OutlineItem],
        fileURL: URL?, viewport: ReaderViewport, openLink: @escaping (URL) -> Void
    ) {
        self.viewport = viewport
        self.openLink = openLink
        self.fileURL = fileURL
        let persisted = viewport.prepare(fileURL: fileURL)
        if rendered == nil {
            restoreAnchor = persisted
            setPaper(style.theme)
        }
        let changed = self.revision != revision || self.style != style || self.fontRevision != fontRevision
        self.fontRevision = fontRevision
        self.document = document
        self.outline = outline
        self.revision = revision
        self.style = style
        if changed {
            requestedWidth = 0
            rebuildIfNeeded()
        }
        jumpIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let backgroundColor { window?.backgroundColor = backgroundColor }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildIfNeeded()
        updateScrollExtent()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            reportPosition()
            viewport?.flush()
        }
        super.willMove(toWindow: newWindow)
    }

    private func updateScrollExtent() {
        guard let rendered else { return }
        let size = CGSize(width: bounds.width, height: rendered.size.height * pageScale)
        if contentSize != size { contentSize = size }
        content.frame = CGRect(origin: .zero, size: size)
    }

    private var topY: CGFloat { max(0, (contentOffset.y + adjustedContentInset.top) / max(0.001, pageScale)) }

    private func rebuildIfNeeded() {
        let width = bounds.width
        guard width > 0, width != requestedWidth, let document, let style else { return }
        let anchor = rendered?.readingAnchor(atY: topY) ?? restoreAnchor
        requestedWidth = width
        layoutTask?.cancel()
        let token = UUID()
        generation = token
        // Continue displaying the previous snapshot at the new measure while its
        // replacement is built; preserve its semantic anchor, not its raw offset.
        if let rendered, let page {
            adjusting = true
            pageScale = width / rendered.size.width
            page.transform = CGAffineTransform(scaleX: pageScale, y: pageScale)
            updateScrollExtent()
            if let anchor, let y = rendered.y(for: anchor) { setTop(y * pageScale) }
            adjusting = false
        }
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let rendered = RenderedDocument(document, width: width, style: style)
            try Task.checkCancellation()
            return rendered
        }
        layoutTask = Task { [weak self] in
            do {
                let next = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self, self.generation == token else { return }
                // A user can continue scrolling during the build; prefer the
                // latest old-snapshot anchor over the one captured at kickoff.
                let latest = self.rendered?.readingAnchor(atY: self.topY) ?? anchor
                self.install(next, restoring: latest)
            } catch { /* Cancellation leaves the previous snapshot visible. */  }
        }
    }

    private func install(_ next: RenderedDocument, restoring anchor: ReadingAnchor?) {
        adjusting = true
        let firstLayout = rendered == nil
        let nextPage = ReaderPageView(rendered: next, scale: max(1, traitCollection.displayScale))
        content.addSubview(nextPage)
        page?.removeFromSuperview()
        rendered = next
        page = nextPage
        pageScale = 1
        backgroundColor = UIColor(cgColor: next.backgroundColor)
        window?.backgroundColor = backgroundColor
        indicatorStyle = style?.theme.appearance == .dark ? .white : .black
        headings = outline.compactMap { item in next.rect(for: item).map { (item.id, $0.minY) } }
        updateScrollExtent()
        setTop(anchor.flatMap { next.y(for: $0) } ?? 0)
        viewport?.rendered = next
        adjusting = false
        jumpIfNeeded()
        openingIndicator.stopAnimating()
        if firstLayout, !UIAccessibility.isReduceMotionEnabled {
            nextPage.alpha = 0
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                nextPage.alpha = 1
            }
        }
        reportPosition()
    }

    private func setPaper(_ theme: DocumentTheme) {
        guard let c = theme.document["paper"] else { return }
        backgroundColor = UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
        window?.backgroundColor = backgroundColor
    }

    private func setTop(_ y: CGFloat, animated: Bool = false) {
        let minimum = -adjustedContentInset.top
        let maximum = max(minimum, contentSize.height - bounds.height + adjustedContentInset.bottom)
        setContentOffset(CGPoint(x: 0, y: min(maximum, max(minimum, y - adjustedContentInset.top))), animated: animated)
    }

    private func jumpIfNeeded() {
        guard let viewport, lastJump != viewport.jumpRevision, let id = viewport.jumpID,
            let rendered, let rect = rendered.rect(forAnchor: id)
        else { return }
        lastJump = viewport.jumpRevision
        adjusting = true
        setTop(max(0, rect.minY * pageScale - headingTopInset), animated: !UIAccessibility.isReduceMotionEnabled)
        adjusting = false
        reportPosition()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !adjusting else { return }
        reportPosition()
    }
    private func reportPosition() {
        guard window != nil, let rendered else { return }
        let y = topY
        let heading = headings.last { $0.1 <= y + headingTopInset / pageScale }?.0 ?? headings.first?.0
        viewport?.moved(anchor: rendered.readingAnchor(atY: y), heading: heading)
    }
    func finish() {
        viewport?.flush()
        layoutTask?.cancel()
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let rendered, let page else { return }
        let point = gesture.location(in: page)
        guard let url = rendered.link(at: point) else { return }
        if let fragment = url.fragment, url.scheme == nil || (url.isFileURL && url.path == fileURL?.path),
            let rect = rendered.rect(forAnchor: fragment)
        {
            adjusting = true
            setTop(max(0, rect.minY * pageScale - 8))
            adjusting = false
            reportPosition()
        } else {
            openLink?(url)
        }
    }
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }
}

fileprivate final class ReaderPageView: UIView {
    init(rendered: RenderedDocument, scale: CGFloat) {
        super.init(frame: CGRect(origin: .zero, size: rendered.size))
        layer.anchorPoint = .zero
        layer.position = .zero
        backgroundColor = UIColor(cgColor: rendered.backgroundColor)
        let tiles = ReaderTileLayer(rendered: rendered)
        tiles.frame = bounds
        tiles.contentsScale = scale
        tiles.tileSize = CGSize(width: 512, height: 512)
        layer.addSublayer(tiles)
        isAccessibilityElement = true
        accessibilityLabel = rendered.text(in: rendered.documentRange)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

fileprivate final class ReaderTileLayer: CATiledLayer {
    private let rendered: RenderedDocument?
    init(rendered: RenderedDocument) {
        self.rendered = rendered
        super.init()
    }
    override init(layer: Any) {
        rendered = (layer as? ReaderTileLayer)?.rendered
        super.init(layer: layer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override class func fadeDuration() -> CFTimeInterval { 0 }
    override func draw(in context: CGContext) { rendered?.draw(in: context, rect: context.boundingBoxOfClipPath) }
}
