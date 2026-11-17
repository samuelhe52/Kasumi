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
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openLink: (URL) -> Void

    func makeUIView(context: Context) -> ReaderScrollView {
        let view = ReaderScrollView()
        view.alpha = isActive ? 1 : 0
        return view
    }
    func updateUIView(_ view: ReaderScrollView, context: Context) {
        ReaderPaneTransition.update(view, visible: isActive, reduceMotion: reduceMotion)
        view.setActive(isActive)
        guard isActive else { return }
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
    private var scrollWarmup: Task<Void, Never>?
    private var scrollWarmupID = UUID()
    private var generation = UUID()
    private var reflow = ReaderReflowState()
    private var reflowAnchor = ReaderReflowAnchorState()
    private var installedGeneration: UUID?
    private var installedRevision: UUID?
    private var finished = false
    private var isActive = true
    private var animateAppearanceReplacement = true
    private var lastJump: UUID?
    private var adjusting = false
    private var scrollDiagnostics: ReaderScrollDiagnostics?
    private lazy var findInteraction = UIFindInteraction(sessionDelegate: self)
    private lazy var findSession = ReaderFindSession { [weak self] matches, current, scroll in
        self?.displayFindResults(matches, current: current, scroll: scroll)
        self?.findInteraction.updateResultCount()
    }
    private var findRequest = 0
    private var presentedFindRequest = 0
    private var findPresentationTask: Task<Void, Never>?
    private let unobscuredViewport = UILayoutGuide()
    private var currentFindRect: CGRect?
    private var currentFindAnchor: ReadingAnchor?
    private enum PendingReveal {
        case anchor(String, CGFloat)
        case find
    }
    private var pendingReveal: PendingReveal?

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
        scrollDiagnostics = ReaderScrollDiagnostics.make { [weak self] in
            guard let self, self.window != nil, self.isActive, !self.finished else { return nil }
            let visible = CGRect(x: 0, y: self.topY, width: self.bounds.width, height: self.bounds.height)
            return ReaderScrollDiagnostics.Viewport(
                top: self.topY, width: self.bounds.width, height: self.bounds.height,
                active: self.isDragging || self.isDecelerating || self.isTracking,
                measured: self.rendered.map { !$0.needsLayout(in: visible) } ?? false)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { layoutTask?.cancel(); scrollWarmup?.cancel() }

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
        let appearanceChanged = self.style != style || self.fontRevision != fontRevision
        let changed = self.revision != revision || appearanceChanged
        if changed { animateAppearanceReplacement = appearanceChanged }
        self.fontRevision = fontRevision
        self.document = document
        self.outline = outline
        self.revision = revision
        self.style = style
        if changed {
            cancelScrollWarmup()
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
        scheduleScrollWarmup()
    }

    override func layoutSubviews() {
        let wasAdjusting = adjusting
        adjusting = true
        super.layoutSubviews()
        rebuildIfNeeded()
        updateScrollExtent()
        updateKeyboardInset()
        updateHighlightViewport()
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
            setTop(max(0, currentFindRect.minY - 24), trackingAnchor: true)
            if rendered?.needsLayout(in: currentFindRect.insetBy(dx: 0, dy: -1)) == true,
                let currentFindAnchor
            {
                reflowAnchor.navigate(to: currentFindAnchor)
                pendingReveal = .find
            }
            reportPosition()
            rebuildIfNeeded()
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            cancelScrollWarmup()
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
        guard isActive, !finished, bounds.width.isFinite, bounds.width > 0, bounds.height.isFinite, bounds.height > 0,
            document != nil, style != nil
        else { return }
        if rendered?.size.width != bounds.width { cancelScrollWarmup() }
        // Refill while most of the one-screen layout buffer still remains;
        // waiting until only a quarter-screen remains cannot absorb paint tails.
        let visible = CGRect(x: 0, y: topY, width: bounds.width, height: bounds.height)
            .insetBy(dx: 0, dy: -bounds.height * 0.75)
        if pendingReveal == nil, let installed = reflow.installed, installed.width == bounds.width,
            installed.generation == generation, rendered?.needsLayout(in: visible) == false
        {
            // Return to an already covered viewport, including while obsolete
            // work runs. Do not turn every scroll callback into a render request.
            reflow.request(
                width: installed.width, generation: installed.generation, anchor: installed.anchor,
                height: installed.height)
        } else {
            reflowAnchor.captureIfNeeded(in: rendered, atY: topY, restoring: restoreAnchor)
            reflow.request(
                width: bounds.width, generation: generation, anchor: reflowAnchor.value, height: bounds.height)
        }
        guard layoutTask == nil, reflow.needsLayout else { return }
        // Do not cancel on width or style changes: synchronous typesetting cannot
        // stop midway. Drain the newest request after the current pipeline ends.
        layoutTask = Task { [weak self] in
            while let self, self.isActive, !self.finished, let request = self.reflow.begin(), let session = self.reflowSession,
                let revision = self.revision
            {
                self.reflowAnchor.captureIfNeeded(in: self.rendered, atY: self.topY, restoring: self.restoreAnchor)
                let worker = Task.detached(priority: .userInitiated) {
                    let interval = Self.signposter.beginInterval("Layout", id: Self.signposter.makeSignpostID())
                    defer { Self.signposter.endInterval("Layout", interval) }
                    try Task.checkCancellation()
                    let next = await session.render(
                        width: request.width, viewportHeight: request.height, anchor: request.anchor)
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
                    let rect = self.visibleRect(in: next, restoring: self.reflowAnchor.value)
                    let coversViewport = !next.needsLayout(in: rect)
                    guard self.reflow.accepts(request, coversDesiredViewport: coversViewport) else {
                        _ = self.reflow.complete(request)
                        continue
                    }
                    let scale = max(1, self.traitCollection.displayScale)
                    let tableOffsets = self.installedRevision == revision ? self.page?.tableOffsets ?? [:] : [:]
                    // Prepaint only the viewport, off-main, before publishing.
                    // Painting and layout share one worker slot, even during drag.
                    let painter = Task.detached(priority: .userInitiated) {
                        let interval = Self.signposter.beginInterval(
                            "ViewportPaint", id: Self.signposter.makeSignpostID())
                        defer { Self.signposter.endInterval("ViewportPaint", interval) }
                        try Task.checkCancellation()
                        let image = ReaderPageView.preview(next, rect: rect, scale: scale, tableOffsets: tableOffsets)
                        try Task.checkCancellation()
                        return image
                    }
                    let preview = try await withTaskCancellationHandler {
                        try await painter.value
                    } onCancel: {
                        painter.cancel()
                    }
                    guard !Task.isCancelled else { break }
                    let liveRect = self.visibleRect(in: next, restoring: self.reflowAnchor.value)
                    if self.reflow.complete(request, coversDesiredViewport: !next.needsLayout(in: liveRect)) {
                        let appearanceChanged = self.installedGeneration != request.generation
                        self.installedGeneration = request.generation
                        self.install(
                            next, revision: revision, restoring: self.reflowAnchor.value, preview: preview,
                            previewRect: rect,
                            animateReplacement: appearanceChanged && self.animateAppearanceReplacement)
                    }
                } catch {
                    _ = self.reflow.complete(request)
                    break
                }
            }
            self?.layoutTask = nil
            self?.scheduleScrollWarmup()
        }
    }

    private func cancelScrollWarmup() {
        scrollWarmupID = UUID()
        scrollWarmup?.cancel()
        scrollWarmup = nil
    }

    private func scheduleScrollWarmup() {
        guard scrollWarmup == nil, rendered?.hasEstimatedGeometry == true,
            isActive, !finished, window != nil, let session = reflowSession, let revision else { return }
        let generation = self.generation
        let width = bounds.width
        let id = UUID()
        scrollWarmupID = id
        scrollWarmup = Task(priority: .utility) { [weak self] in
            defer { if self?.scrollWarmupID == id { self?.scrollWarmup = nil } }
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard let self, self.isActive, !self.finished, !self.isDragging, !self.isDecelerating,
                    self.layoutTask == nil, self.generation == generation, self.bounds.width == width else { return }
                guard let next = try await session.prepareForScrolling(width: width) else { return }
                try Task.checkCancellation()
                let rect = self.visibleRect(in: next, restoring: self.reflowAnchor.value)
                let scale = max(1, self.traitCollection.displayScale)
                let offsets = self.page?.tableOffsets ?? [:]
                let preview = await Task.detached(priority: .utility) {
                    ReaderPageView.preview(next, rect: rect, scale: scale, tableOffsets: offsets)
                }.value
                try Task.checkCancellation()
                guard self.isActive, !self.finished, !self.isDragging, !self.isDecelerating,
                    self.generation == generation, self.bounds.width == width,
                    self.layoutTask == nil, !self.reflow.needsLayout else { return }
                self.install(next, revision: revision, restoring: self.reflowAnchor.value,
                    preview: preview, previewRect: rect, animateReplacement: false)
            } catch is CancellationError {} catch { /* Foreground refinement remains available. */ }
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
        _ next: RenderedDocument, revision: UUID, restoring anchor: ReadingAnchor?, preview: ReaderPagePreview?,
        previewRect: CGRect,
        animateReplacement: Bool
    ) {
        let interval = Self.signposter.beginInterval("Install", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("Install", interval) }
        adjusting = true
        let firstLayout = rendered == nil
        let selection = installedRevision == revision ? page?.selectionOffsets : nil
        let hadTextFocus = page?.isFirstResponder == true
        let sameContent = installedRevision == revision
        let tableOffsets = sameContent ? page?.tableOffsets ?? [:] : [:]
        installedRevision = revision
        let animate = !UIAccessibility.isReduceMotionEnabled && window != nil
        let widthChanged = rendered?.size.width != next.size.width
        let overlay =
            !firstLayout && animate && animateReplacement && !widthChanged
            ? content.resizableSnapshotView(from: bounds, afterScreenUpdates: false, withCapInsets: .zero) : nil
        transitionOverlay?.removeFromSuperview()
        transitionOverlay = overlay
        let nextPage: ReaderPageView
        if sameContent, !animateReplacement, !widthChanged, let page {
            page.refine(next, scale: max(1, traitCollection.displayScale), preview: preview, previewRect: previewRect)
            nextPage = page
        } else {
            nextPage = ReaderPageView(
                rendered: next, scale: max(1, traitCollection.displayScale), preview: preview, previewRect: previewRect,
                tableOffsets: tableOffsets)
            content.addSubview(nextPage)
            page?.clearSelection()
            page?.removeFromSuperview()
        }
        rendered = next
        page = nextPage
        if let selection { nextPage.restoreSelection(selection) }
        nextPage.onLink = { [weak self] url in self?.follow(url) }
        backgroundColor = UIColor(cgColor: next.backgroundColor)
        window?.backgroundColor = backgroundColor
        indicatorStyle = style?.theme.appearance == .dark ? .white : .black
        headings = outline.compactMap { item in next.rect(for: item).map { (item.id, $0.minY) } }
        updateScrollExtent()
        setTop(anchor.flatMap { next.y(for: $0) } ?? 0)
        reflowAnchor.didInstall(next, revision: revision, atY: topY)
        viewport?.rendered = next
        adjusting = false
        jumpIfNeeded()
        findSession.install(next, scroll: false)
        revealPendingTarget()
        presentFindIfNeeded()
        openingIndicator.stopAnimating()
        if firstLayout { becomeFirstResponder() }
        if selection != nil && hadTextFocus { nextPage.becomeFirstResponder() }
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

    private func setTop(_ y: CGFloat, animated: Bool = false, trackingAnchor: Bool = false) {
        let minimum = -adjustedContentInset.top
        let maximum = max(minimum, contentSize.height - bounds.height + adjustedContentInset.bottom)
        let offset = min(maximum, max(minimum, y - adjustedContentInset.top))
        if trackingAnchor {
            pendingReveal = nil
            reflowAnchor.moved(in: rendered, atY: max(0, offset + adjustedContentInset.top))
        }
        setContentOffset(CGPoint(x: 0, y: offset), animated: animated)
        updateHighlightViewport()
        if trackingAnchor && !animated {
            reflowAnchor.moved(in: rendered, atY: topY)
        }
    }

    private func jumpIfNeeded() {
        guard let viewport, lastJump != viewport.jumpRevision, let id = viewport.jumpID,
            let rendered, let rect = rendered.rect(forAnchor: id)
        else { return }
        lastJump = viewport.jumpRevision
        let approximate = rendered.needsLayout(in: rect.insetBy(dx: 0, dy: -1))
        adjusting = true
        setTop(
            max(0, rect.minY - headingTopInset), animated: !approximate && !UIAccessibility.isReduceMotionEnabled,
            trackingAnchor: true)
        adjusting = false
        if approximate, let anchor = rendered.readingAnchor(forAnchor: id) {
            reflowAnchor.navigate(to: anchor)
            pendingReveal = .anchor(id, headingTopInset)
        }
        reportPosition()
        rebuildIfNeeded()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { cancelScrollWarmup() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { scheduleScrollWarmup() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { scheduleScrollWarmup() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { scheduleScrollWarmup() }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateHighlightViewport()
        guard !adjusting else { return }
        cancelScrollWarmup()
        if isDragging || isDecelerating { pendingReveal = nil }
        reflowAnchor.moved(in: rendered, atY: topY)
        reportPosition()
        rebuildIfNeeded()
        scheduleScrollWarmup()
    }
    private func updateHighlightViewport() {
        guard let page else { return }
        page.updateHighlightViewport(page.convert(bounds, from: self))
    }
    private func reportPosition() {
        guard window != nil, let rendered else { return }
        let y = topY
        let heading = headings.last { $0.1 <= y + headingTopInset }?.0 ?? headings.first?.0
        viewport?.moved(anchor: reflowAnchor.value ?? rendered.readingAnchor(atY: y), heading: heading)
    }
    func finish() {
        cancelScrollWarmup()
        scrollDiagnostics?.finish()
        scrollDiagnostics = nil
        findPresentationTask?.cancel()
        finished = true
        reflow.stop()
        reflowSession = nil
        viewport?.flush()
        findInteraction.dismissFindNavigator()
        layoutTask?.cancel()
        transitionOverlay?.removeFromSuperview()
        transitionOverlay = nil
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        // A hidden preview skips layout; catch up on a size change meanwhile.
        if active { setNeedsLayout(); scheduleScrollWarmup() }
        if !active {
            cancelScrollWarmup()
            reflow.stop()
            reportPosition()
            findPresentationTask?.cancel()
            findPresentationTask = nil
            // Responder changes can ask SwiftUI for its responder graph. Do not
            // make that reentrant while updateUIView is evaluating that graph.
            Task { @MainActor [weak self] in
                guard let self, !self.isActive else { return }
                self.findInteraction.dismissFindNavigator()
                self.resignFirstResponder()
            }
        }
    }

    func requestFind(_ revision: Int) {
        findRequest = revision
        presentFindIfNeeded()
    }

    private func presentFindIfNeeded() {
        guard isActive, rendered != nil, window != nil, findRequest != presentedFindRequest,
            findPresentationTask == nil else { return }
        findPresentationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.findPresentationTask = nil
            guard !Task.isCancelled, self.isActive, self.window != nil,
                self.findRequest != self.presentedFindRequest else { return }
            self.presentedFindRequest = self.findRequest
            self.findInteraction.presentFindNavigator(showingReplace: false)
        }
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
            guard let self, self.isActive, self.window != nil, !self.findInteraction.isFindNavigatorVisible else { return }
            self.becomeFirstResponder()
        }
    }

    private func displayFindResults(_ matches: [TextRange], current: Int?, scroll: Bool) {
        if scroll, let current, matches.indices.contains(current) {
            page?.reveal(matches[current])
        }
        page?.highlight(matches: matches, current: current)
        currentFindRect = current.flatMap { index in
            guard matches.indices.contains(index), let rendered else { return nil }
            return page?.selectionGeometry(for: matches[index]).first
                ?? rendered.selectionRects(for: matches[index]).first
        }
        currentFindAnchor = current.flatMap { index in
            guard matches.indices.contains(index) else { return nil }
            return rendered?.readingAnchor(at: matches[index].lowerBound)
        }
        if current == nil, case .find = pendingReveal { pendingReveal = nil }
        guard scroll, let rect = currentFindRect else { return }
        let approximate = rendered?.needsLayout(in: rect.insetBy(dx: 0, dy: -1)) == true
        setTop(
            max(0, rect.minY - 24), animated: !approximate && !UIAccessibility.isReduceMotionEnabled,
            trackingAnchor: true)
        if approximate, let current, matches.indices.contains(current),
            let anchor = rendered?.readingAnchor(at: matches[current].lowerBound)
        {
            reflowAnchor.navigate(to: anchor)
            pendingReveal = .find
        }
        rebuildIfNeeded()
    }

    private func follow(_ url: URL) {
        guard let rendered else { return }
        if let fragment = url.fragment, url.scheme == nil || (url.isFileURL && url.path == fileURL?.path) {
            // An unresolved same-document fragment is not an external URL.
            guard let rect = rendered.rect(forAnchor: fragment) else { return }
            let approximate = rendered.needsLayout(in: rect.insetBy(dx: 0, dy: -1))
            adjusting = true
            setTop(
                max(0, rect.minY - 8), animated: !approximate && !UIAccessibility.isReduceMotionEnabled,
                trackingAnchor: true)
            adjusting = false
            if approximate, let anchor = rendered.readingAnchor(forAnchor: fragment) {
                reflowAnchor.navigate(to: anchor)
                pendingReveal = .anchor(fragment, 8)
            }
            reportPosition()
            rebuildIfNeeded()
        } else {
            openLink?(url)
        }
    }

    private func revealPendingTarget() {
        guard let pendingReveal, let rendered else { return }
        let rect: CGRect?
        let inset: CGFloat
        switch pendingReveal {
        case .anchor(let id, let topInset):
            rect = rendered.rect(forAnchor: id)
            inset = topInset
        case .find:
            rect = currentFindRect
            inset = 24
        }
        guard let rect else {
            self.pendingReveal = nil
            return
        }
        guard !rendered.needsLayout(in: rect.insetBy(dx: 0, dy: -1)) else { return }
        self.pendingReveal = nil
        let wasAdjusting = adjusting
        adjusting = true
        setTop(max(0, rect.minY - inset), trackingAnchor: true)
        adjusting = wasAdjusting
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
    private var highlightIndex: ReaderHighlightIndex?
    private var highlightWindow = CGRect.null
    private var tableScrollViews: [ReaderTableScrollView] = []
    private var seedLayer: CALayer?
    private var tileLayer: ReaderTileLayer?
    var tableOffsets: [Int: CGFloat] {
        Dictionary(uniqueKeysWithValues: tableScrollViews.map { ($0.tableID, $0.contentOffset.x) })
    }

    init(
        rendered: RenderedDocument, scale: CGFloat, preview: ReaderPagePreview?, previewRect: CGRect,
        tableOffsets: [Int: CGFloat] = [:]
    ) {
        super.init(rendered: rendered)
        layer.anchorPoint = .zero
        layer.position = .zero
        backgroundColor = UIColor(cgColor: rendered.backgroundColor)
        installDrawingLayers(scale: scale, preview: preview, previewRect: previewRect)
        installTables(scale: scale, preview: preview)
        for scroll in tableScrollViews {
            let x = min(
                max(0, tableOffsets[scroll.tableID] ?? 0), max(0, scroll.contentSize.width - scroll.bounds.width))
            scroll.setContentOffset(CGPoint(x: x, y: 0), animated: false)
        }
        matchHighlights.fillColor = UIColor.systemYellow.withAlphaComponent(0.3).cgColor
        currentHighlight.fillColor = UIColor.systemOrange.withAlphaComponent(0.45).cgColor
        layer.addSublayer(matchHighlights)
        layer.addSublayer(currentHighlight)
        isAccessibilityElement = true
        accessibilityLabel = rendered.text(in: rendered.documentRange)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refine(_ next: RenderedDocument, scale: CGFloat, preview: ReaderPagePreview?, previewRect: CGRect) {
        highlightIndex = nil
        highlightWindow = .null
        replaceRendered(next)
        installDrawingLayers(scale: scale, preview: preview, previewRect: previewRect)
        installTables(scale: scale, preview: preview)
    }

    private func installTables(scale: CGFloat, preview: ReaderPagePreview?) {
        var existing = Dictionary(uniqueKeysWithValues: tableScrollViews.map { ($0.tableID, $0) })
        var next: [ReaderTableScrollView] = []
        for table in rendered.tables where table.isScrollable {
            let scroll: ReaderTableScrollView
            if let retained = existing.removeValue(forKey: table.id) {
                retained.refine(rendered: rendered, table: table, scale: scale, preview: preview?.tables[table.id])
                scroll = retained
            } else {
                scroll = ReaderTableScrollView(
                    rendered: rendered, table: table, scale: scale, preview: preview?.tables[table.id])
                scroll.onScroll = { [weak self] in self?.paintHighlights() }
                scroll.onBeginDragging = { [weak self] in self?.clearSelection() }
                addSubview(scroll)
            }
            next.append(scroll)
        }
        for obsolete in existing.values { obsolete.removeFromSuperview() }
        tableScrollViews = next
    }

    private func installDrawingLayers(scale: CGFloat, preview: ReaderPagePreview?, previewRect: CGRect) {
        seedLayer?.removeFromSuperlayer()
        tileLayer?.removeFromSuperlayer()
        seedLayer = nil
        if let image = preview?.image {
            let seed = CALayer()
            seed.frame = previewRect
            seed.contents = image
            seed.contentsScale = scale
            layer.insertSublayer(seed, at: 0)
            seedLayer = seed
        }
        let tiles = ReaderTileLayer(rendered: rendered)
        tiles.frame = bounds
        tiles.contentsScale = scale
        tiles.tileSize = CGSize(width: 512, height: 512)
        layer.insertSublayer(tiles, at: seedLayer == nil ? 0 : 1)
        tileLayer = tiles
    }

    func highlight(matches: [TextRange], current: Int?) {
        let changed = matches != highlightedMatches
        guard changed || current != highlightedIndex else { return }
        if changed { highlightIndex = ReaderHighlightIndex(matches, in: rendered) }
        highlightedMatches = matches
        highlightedIndex = current
        paintHighlights()
    }

    func updateHighlightViewport(_ viewport: CGRect) {
        guard viewport.minY.isFinite, viewport.maxY.isFinite, viewport.height > 0 else { return }
        let visible = viewport.intersection(bounds)
        guard !visible.isNull, !visible.isEmpty else {
            if !highlightWindow.isNull {
                highlightWindow = .null
                paintHighlights()
            }
            return
        }
        if !highlightWindow.isNull, highlightWindow.minY <= visible.minY, highlightWindow.maxY >= visible.maxY {
            return
        }
        highlightWindow = visible.insetBy(dx: 0, dy: -max(128, visible.height * 0.5)).intersection(bounds)
        paintHighlights()
    }

    private func paintHighlights() {
        let others = CGMutablePath()
        let active = CGMutablePath()
        if !highlightWindow.isNull, !highlightedMatches.isEmpty, let highlightIndex {
            let candidates = highlightIndex.candidates(
                in: rendered, verticalRange: highlightWindow.minY..<highlightWindow.maxY)
            for index in candidates {
                for rect in selectionGeometry(for: highlightedMatches[index]) where rect.intersects(highlightWindow) {
                    (index == highlightedIndex ? active : others).addRect(rect)
                }
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

    nonisolated static func preview(
        _ rendered: RenderedDocument, rect: CGRect, scale: CGFloat, tableOffsets: [Int: CGFloat] = [:]
    ) -> ReaderPagePreview? {
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
            let x = min(max(0, tableOffsets[table.id] ?? 0), max(0, table.contentWidth - table.frame.width))
            let local = visible.offsetBy(dx: x - table.frame.minX, dy: -table.frame.minY)
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
