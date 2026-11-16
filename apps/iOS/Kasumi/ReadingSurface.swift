import KasumiMarkdown
import SwiftUI
import UIKit
import os

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
    let findRequest: Int
    let openLink: (URL) -> Void

    func makeUIView(context: Context) -> ReaderScrollView { ReaderScrollView() }
    func updateUIView(_ view: ReaderScrollView, context: Context) {
        view.update(
            document: document, revision: revision, style: style, fontRevision: fontRevision, outline: outline,
            fileURL: fileURL, viewport: viewport, openLink: openLink)
        view.requestFind(findRequest)
    }
    static func dismantleUIView(_ view: ReaderScrollView, coordinator: ()) { view.finish() }
}

final class ReaderScrollView: UIScrollView, UIScrollViewDelegate, UIFindInteractionDelegate {
    nonisolated private static let signposter = OSSignposter(subsystem: "com.samuelhe.Kasumi", category: "ReaderReflow")
    private let headingTopInset: CGFloat = 15

    // Pages swap inside a permanent container so the scroll view's own subviews
    // never change; replacing them directly drops the soft top edge effect until
    // the next scroll.
    private let content = UIView()
    private var page: ReaderPageView?
    private var rendered: RenderedDocument?
    private var reflowSession: DocumentReflowSession?
    private var transitionOverlay: UIView?
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
    private var reflow = ReaderReflowState()
    private var reflowAnchor: ReadingAnchor?
    private var installedGeneration: UUID?
    private var finished = false
    private var lastJump: UUID?
    private var adjusting = false
    private lazy var findInteraction = UIFindInteraction(sessionDelegate: self)
    private lazy var findSession = ReaderFindSession { [weak self] matches, current, scroll in
        self?.displayFindResults(matches, current: current, scroll: scroll)
        self?.findInteraction.updateResultCount()
    }
    private var findRequest = 0
    private var presentedFindRequest = 0
    private let unobscuredViewport = UILayoutGuide()
    private var currentFindRect: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        alwaysBounceVertical = true
        contentInsetAdjustmentBehavior = .automatic
        topEdgeEffect.style = .soft
        addSubview(content)
        addInteraction(findInteraction)
        // Keep painting through the keyboard safe area, but let Auto Layout
        // track the keyboard/accessory boundary for scrolling and indicators.
        addLayoutGuide(unobscuredViewport)
        NSLayoutConstraint.activate([
            unobscuredViewport.leadingAnchor.constraint(equalTo: frameLayoutGuide.leadingAnchor),
            unobscuredViewport.widthAnchor.constraint(equalToConstant: 0),
            unobscuredViewport.topAnchor.constraint(equalTo: frameLayoutGuide.topAnchor),
            unobscuredViewport.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor)
        ])
        openingIndicator.hidesWhenStopped = true
        openingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(openingIndicator)
        NSLayoutConstraint.activate([
            openingIndicator.centerXAnchor.constraint(equalTo: frameLayoutGuide.centerXAnchor),
            openingIndicator.centerYAnchor.constraint(equalTo: frameLayoutGuide.centerYAnchor)
        ])
        openingIndicator.startAnimating()
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
            generation = UUID()
            reflowSession = DocumentReflowSession(document, style: style, scrollableTables: true)
            rebuildIfNeeded()
        }
        jumpIfNeeded()
    }

    override var canBecomeFirstResponder: Bool { true }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let backgroundColor { window?.backgroundColor = backgroundColor }
    }

    override func layoutSubviews() {
        let wasAdjusting = adjusting
        adjusting = true
        super.layoutSubviews()
        rebuildIfNeeded()
        updateScrollExtent()
        updateKeyboardInset()
        adjusting = wasAdjusting
    }

    private func updateKeyboardInset() {
        let occluded = max(0, bounds.height - unobscuredViewport.layoutFrame.height)
        let automatic = adjustedContentInset.bottom - contentInset.bottom
        let inset = max(0, occluded - automatic)
        guard abs(contentInset.bottom - inset) > 0.5 else { return }
        contentInset.bottom = inset
        verticalScrollIndicatorInsets.bottom = inset
        if let currentFindRect {
            setTop(max(0, currentFindRect.minY - 24))
        }
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
        let size = CGSize(width: bounds.width, height: rendered.size.height)
        if contentSize != size { contentSize = size }
        content.frame = CGRect(origin: .zero, size: size)
    }

    private var topY: CGFloat { max(0, contentOffset.y + adjustedContentInset.top) }

    private func rebuildIfNeeded() {
        guard !finished, bounds.width.isFinite, bounds.width > 0, document != nil, style != nil else { return }
        reflow.request(width: bounds.width, generation: generation)
        guard layoutTask == nil, reflow.needsLayout else { return }
        // Do not cancel on width or style changes: synchronous typesetting cannot
        // stop midway. Drain the newest request after the current pipeline ends.
        layoutTask = Task { [weak self] in
            while let self, let request = self.reflow.begin(), let session = self.reflowSession {
                if self.reflowAnchor == nil {
                    self.reflowAnchor = self.rendered?.readingAnchor(atY: self.topY) ?? self.restoreAnchor
                }
                let worker = Task.detached(priority: .userInitiated) {
                    let interval = Self.signposter.beginInterval("Layout", id: Self.signposter.makeSignpostID())
                    defer { Self.signposter.endInterval("Layout", interval) }
                    try Task.checkCancellation()
                    let next = await session.render(width: request.width)
                    try Task.checkCancellation()
                    return next
                }
                do {
                    let next = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    guard !Task.isCancelled else { break }
                    guard self.reflow.accepts(request) else {
                        _ = self.reflow.complete(request)
                        continue
                    }
                    let rect = self.visibleRect(in: next, restoring: self.reflowAnchor)
                    let scale = max(1, self.traitCollection.displayScale)
                    // Prepaint only the viewport, off-main, before publishing.
                    // Painting and layout share one worker slot, even during drag.
                    let painter = Task.detached(priority: .userInitiated) {
                        let interval = Self.signposter.beginInterval(
                            "ViewportPaint", id: Self.signposter.makeSignpostID())
                        defer { Self.signposter.endInterval("ViewportPaint", interval) }
                        try Task.checkCancellation()
                        let image = ReaderPageView.preview(next, rect: rect, scale: scale)
                        try Task.checkCancellation()
                        return image
                    }
                    let preview = try await withTaskCancellationHandler {
                        try await painter.value
                    } onCancel: {
                        painter.cancel()
                    }
                    guard !Task.isCancelled else { break }
                    if self.reflow.complete(request) {
                        let appearanceChanged = self.installedGeneration != request.generation
                        self.installedGeneration = request.generation
                        self.install(
                            next, restoring: self.reflowAnchor, preview: preview, previewRect: rect,
                            animateReplacement: appearanceChanged)
                    }
                } catch {
                    _ = self.reflow.complete(request)
                    break
                }
            }
            self?.layoutTask = nil
        }
    }

    private func visibleRect(in next: RenderedDocument, restoring anchor: ReadingAnchor?) -> CGRect {
        let y = anchor.flatMap { next.y(for: $0) } ?? 0
        let minimum = -adjustedContentInset.top
        let maximum = max(minimum, next.size.height - bounds.height + adjustedContentInset.bottom)
        let offset = min(maximum, max(minimum, y - adjustedContentInset.top))
        return CGRect(x: 0, y: max(0, offset), width: next.size.width, height: bounds.height)
            .intersection(CGRect(origin: .zero, size: next.size))
    }

    private func install(
        _ next: RenderedDocument, restoring anchor: ReadingAnchor?, preview: ReaderPagePreview?, previewRect: CGRect,
        animateReplacement: Bool
    ) {
        let interval = Self.signposter.beginInterval("Install", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("Install", interval) }
        adjusting = true
        let firstLayout = rendered == nil
        let animate = !UIAccessibility.isReduceMotionEnabled && window != nil
        let widthChanged = rendered?.size.width != next.size.width
        let overlay =
            !firstLayout && animate && animateReplacement && !widthChanged
            ? content.resizableSnapshotView(from: bounds, afterScreenUpdates: false, withCapInsets: .zero) : nil
        transitionOverlay?.removeFromSuperview()
        transitionOverlay = overlay
        let nextPage = ReaderPageView(
            rendered: next, scale: max(1, traitCollection.displayScale), preview: preview, previewRect: previewRect)
        content.addSubview(nextPage)
        page?.clearSelection()
        page?.removeFromSuperview()
        rendered = next
        page = nextPage
        nextPage.onLink = { [weak self] url in self?.follow(url) }
        backgroundColor = UIColor(cgColor: next.backgroundColor)
        window?.backgroundColor = backgroundColor
        indicatorStyle = style?.theme.appearance == .dark ? .white : .black
        headings = outline.compactMap { item in next.rect(for: item).map { (item.id, $0.minY) } }
        updateScrollExtent()
        setTop(anchor.flatMap { next.y(for: $0) } ?? 0)
        viewport?.rendered = next
        adjusting = false
        jumpIfNeeded()
        findSession.install(next, scroll: false)
        presentFindIfNeeded()
        openingIndicator.stopAnimating()
        if firstLayout { becomeFirstResponder() }
        if let overlay {
            overlay.frame = bounds
            overlay.isUserInteractionEnabled = false
            overlay.accessibilityElementsHidden = true
            content.addSubview(overlay)
            UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                overlay.alpha = 0
            } completion: { [weak self] _ in
                overlay.removeFromSuperview()
                if self?.transitionOverlay === overlay { self?.transitionOverlay = nil }
            }
        } else if firstLayout, animate {
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
        reflowAnchor = rendered.readingAnchor(atY: max(0, rect.minY - headingTopInset))
        adjusting = true
        setTop(max(0, rect.minY - headingTopInset), animated: !UIAccessibility.isReduceMotionEnabled)
        adjusting = false
        reportPosition()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !adjusting else { return }
        reflowAnchor = rendered?.readingAnchor(atY: topY)
        reportPosition()
    }
    private func reportPosition() {
        guard window != nil, let rendered else { return }
        let y = topY
        let heading = headings.last { $0.1 <= y + headingTopInset }?.0 ?? headings.first?.0
        viewport?.moved(anchor: reflowAnchor ?? rendered.readingAnchor(atY: y), heading: heading)
    }
    func finish() {
        finished = true
        reflow.stop()
        reflowSession = nil
        viewport?.flush()
        findInteraction.dismissFindNavigator()
        layoutTask?.cancel()
        transitionOverlay?.removeFromSuperview()
        transitionOverlay = nil
    }

    func requestFind(_ revision: Int) {
        findRequest = revision
        presentFindIfNeeded()
    }

    private func presentFindIfNeeded() {
        guard rendered != nil, window != nil, findRequest != presentedFindRequest else { return }
        presentedFindRequest = findRequest
        findInteraction.presentFindNavigator(showingReplace: false)
    }

    func findInteraction(_ interaction: UIFindInteraction, sessionFor view: UIView) -> UIFindSession? {
        guard let rendered else { return nil }
        findSession.install(rendered)
        return findSession
    }

    func findInteraction(_ interaction: UIFindInteraction, didBegin session: UIFindSession) {
        page?.clearSelection()
        findSession.begin()
    }

    func findInteraction(_ interaction: UIFindInteraction, didEnd session: UIFindSession) {
        findSession.end()
        // Let UIKit finish resigning its search field, then restore the reader's
        // responder chain so Command-F can start another session.
        Task { @MainActor [weak self] in
            guard let self, self.window != nil, !self.findInteraction.isFindNavigatorVisible else { return }
            self.becomeFirstResponder()
        }
    }

    private func displayFindResults(_ matches: [TextRange], current: Int?, scroll: Bool) {
        if let current, matches.indices.contains(current) {
            page?.reveal(matches[current])
        }
        page?.highlight(matches: matches, current: current)
        currentFindRect = current.flatMap { index in
            guard matches.indices.contains(index), let rendered else { return nil }
            return page?.selectionGeometry(for: matches[index]).first
                ?? rendered.selectionRects(for: matches[index]).first
        }
        guard scroll, let rect = currentFindRect else { return }
        reflowAnchor = rendered?.readingAnchor(atY: max(0, rect.minY - 24))
        setTop(max(0, rect.minY - 24), animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func follow(_ url: URL) {
        guard let rendered else { return }
        if let fragment = url.fragment, url.scheme == nil || (url.isFileURL && url.path == fileURL?.path) {
            // An unresolved same-document fragment is not an external URL.
            guard let rect = rendered.rect(forAnchor: fragment) else { return }
            reflowAnchor = rendered.readingAnchor(atY: max(0, rect.minY - 8))
            adjusting = true
            setTop(max(0, rect.minY - 8), animated: !UIAccessibility.isReduceMotionEnabled)
            adjusting = false
            reportPosition()
        } else {
            openLink?(url)
        }
    }
}

fileprivate struct ReaderPagePreview: Sendable {
    let image: CGImage?
    let tables: [Int: ReaderTablePreview]
}

fileprivate final class ReaderPageView: ReaderTextInputView {
    private let matchHighlights = CAShapeLayer()
    private let currentHighlight = CAShapeLayer()
    private var highlightedMatches: [TextRange] = []
    private var highlightedIndex: Int?
    private var tableScrollViews: [ReaderTableScrollView] = []
    init(rendered: RenderedDocument, scale: CGFloat, preview: ReaderPagePreview?, previewRect: CGRect) {
        super.init(rendered: rendered)
        layer.anchorPoint = .zero
        layer.position = .zero
        backgroundColor = UIColor(cgColor: rendered.backgroundColor)
        if let image = preview?.image {
            let seed = CALayer()
            seed.frame = previewRect
            seed.contents = image
            seed.contentsScale = scale
            layer.addSublayer(seed)
        }
        let tiles = ReaderTileLayer(rendered: rendered)
        tiles.frame = bounds
        tiles.contentsScale = scale
        tiles.tileSize = CGSize(width: 512, height: 512)
        layer.addSublayer(tiles)
        for table in rendered.tables where table.isScrollable {
            let scroll = ReaderTableScrollView(
                rendered: rendered, table: table, scale: scale, preview: preview?.tables[table.id])
            scroll.onScroll = { [weak self] in self?.paintHighlights() }
            scroll.onBeginDragging = { [weak self] in self?.clearSelection() }
            tableScrollViews.append(scroll)
            addSubview(scroll)
        }
        matchHighlights.fillColor = UIColor.systemYellow.withAlphaComponent(0.3).cgColor
        currentHighlight.fillColor = UIColor.systemOrange.withAlphaComponent(0.45).cgColor
        layer.addSublayer(matchHighlights)
        layer.addSublayer(currentHighlight)
        isAccessibilityElement = true
        accessibilityLabel = rendered.text(in: rendered.documentRange)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func highlight(matches: [TextRange], current: Int?) {
        guard matches != highlightedMatches || current != highlightedIndex else { return }
        highlightedMatches = matches
        highlightedIndex = current
        paintHighlights()
    }

    private func paintHighlights() {
        let others = CGMutablePath()
        let active = CGMutablePath()
        for (index, range) in highlightedMatches.enumerated() {
            for rect in selectionGeometry(for: range) {
                (index == highlightedIndex ? active : others).addRect(rect)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        matchHighlights.path = others
        currentHighlight.path = active
        CATransaction.commit()
    }

    override func documentPoint(_ point: CGPoint) -> CGPoint {
        guard let scroll = tableScrollViews.first(where: { $0.frame.contains(point) }) else { return point }
        return CGPoint(x: point.x + scroll.contentOffset.x, y: point.y)
    }

    override func viewRect(_ rect: CGRect, clipped: Bool = false) -> CGRect {
        guard
            let scroll = tableScrollViews.first(where: {
                rect.midY >= $0.frame.minY && rect.midY <= $0.frame.maxY
            })
        else { return rect }
        let shifted = rect.offsetBy(dx: -scroll.contentOffset.x, dy: 0)
        return clipped ? shifted.intersection(scroll.frame) : shifted
    }

    func reveal(_ range: TextRange) {
        guard let rect = rendered.selectionRects(for: range).first,
            let scroll = tableScrollViews.first(where: {
                rect.midY >= $0.frame.minY && rect.midY <= $0.frame.maxY
            })
        else { return }
        let left = rect.minX - scroll.frame.minX
        let right = rect.maxX - scroll.frame.minX
        let offset = max(
            0,
            min(
                scroll.contentSize.width - scroll.bounds.width,
                min(left, max(scroll.contentOffset.x, right - scroll.bounds.width))))
        scroll.setContentOffset(CGPoint(x: offset, y: 0), animated: false)
    }

    nonisolated static func preview(_ rendered: RenderedDocument, rect: CGRect, scale: CGFloat) -> ReaderPagePreview? {
        guard !rect.isNull, !rect.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            rendered.draw(in: context.cgContext, rect: rect, excludingScrollableTables: true)
        }.cgImage
        var tables: [Int: ReaderTablePreview] = [:]
        for table in rendered.tables where table.isScrollable {
            let visible = rect.intersection(table.frame)
            guard !visible.isNull, !visible.isEmpty else { continue }
            let local = visible.offsetBy(dx: -table.frame.minX, dy: -table.frame.minY)
            let seed = UIGraphicsImageRenderer(size: local.size, format: format).image { context in
                context.cgContext.translateBy(x: -local.minX, y: -local.minY)
                rendered.drawTable(at: table.id, in: context.cgContext, rect: local)
            }.cgImage
            if let seed { tables[table.id] = ReaderTablePreview(image: seed, rect: local) }
        }
        return ReaderPagePreview(image: image, tables: tables)
    }
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
    override func draw(in context: CGContext) {
        rendered?.draw(in: context, rect: context.boundingBoxOfClipPath, excludingScrollableTables: true)
    }
}
