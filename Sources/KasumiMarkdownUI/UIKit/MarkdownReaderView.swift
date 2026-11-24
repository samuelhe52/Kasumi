#if os(iOS)
import KasumiMarkdown
import UIKit
import os

/// A selectable, reflowing Markdown viewport backed by native scrolling.
@MainActor public final class MarkdownReaderView: UIView {
    private let scrollView = ReaderScrollView(frame: .zero)

    public override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(scrollView)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Replaces the document. A replacement at the same URL preserves position
    /// unless an explicit anchor is supplied.
    public func setDocument(_ document: MarkdownDocument, url: URL? = nil, restoring anchor: ReadingAnchor? = nil) {
        scrollView.setDocument(document, url: url, restoring: anchor)
    }

    public var style: RenderStyle {
        get { scrollView.style }
        set { scrollView.setStyle(newValue) }
    }

    /// Pauses background work and input while false, and fades the reader out.
    /// The scroll position is kept.
    public var isActive: Bool {
        get { scrollView.isActive }
        set {
            guard newValue != scrollView.isActive else { return }
            isUserInteractionEnabled = newValue
            accessibilityElementsHidden = !newValue
            scrollView.setActive(newValue)
            let opacity: CGFloat = newValue ? 1 : 0
            if UIAccessibility.isReduceMotionEnabled || window == nil {
                layer.removeAnimation(forKey: "opacity")
                alpha = opacity
            } else {
                UIView.animate(
                    withDuration: 0.24, delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
                ) { self.alpha = opacity }
            }
        }
    }

    /// Rebuilds layout after external font or layout inputs change.
    public func invalidateLayout() { scrollView.invalidateReaderLayout() }

    public func scroll(to anchor: ReadingAnchor, animated: Bool = true) {
        scrollView.navigate(to: .position(anchor), animated: animated)
    }

    public func scroll(toAnchorID id: String, animated: Bool = true) {
        scrollView.navigate(to: .anchor(id, inset: scrollView.headingTopInset), animated: animated)
    }

    package var topSourceLine: Int? { scrollView.topSourceLine }

    package func scroll(toSourceLine line: Int, animated: Bool) {
        scrollView.navigate(to: .sourceLine(line), animated: animated)
    }

    /// Reports the reading anchor and the outline ID of the current section, or nil before the first heading.
    public var onPositionChange: ((ReadingAnchor, String?) -> Void)? {
        get { scrollView.onPositionChange }
        set { scrollView.onPositionChange = newValue }
    }

    /// Receives every link that doesn't point into the current document.
    public var onOpenLink: ((URL) -> Void)? {
        get { scrollView.onOpenLink }
        set { scrollView.onOpenLink = newValue }
    }

    public var onFindPresentationChange: ((Bool) -> Void)? {
        get { scrollView.onFindPresentationChange }
        set { scrollView.onFindPresentationChange = newValue }
    }

    public var canPresentFind: Bool { scrollView.canPresentFind }
    public var isFindPresented: Bool { scrollView.isFindPresented }

    /// Returns whether the request was accepted. While a document is still opening,
    /// the panel appears once the first screen is laid out.
    @discardableResult public func presentFind() -> Bool { scrollView.presentFind() }
    public func dismissFind() { scrollView.dismissFind() }

    public func setFindQuery(_ query: String, options: SearchOptions = []) {
        scrollView.setFindQuery(query, options: options)
    }

    public func moveToFindMatch(_ direction: FindDirection) { scrollView.moveToFindMatch(direction) }
    public func clearFind() { scrollView.clearFind() }

    public var onFindResultChange: ((FindResult) -> Void)? {
        get { scrollView.onFindResultChange }
        set { scrollView.onFindResultChange = newValue }
    }

    /// Sets an opt-in remote image provider. Changing the revision discards
    /// cached resolutions associated with the previous revision.
    public func setRemoteImages(_ configuration: MarkdownRemoteImages?, revision: Int = 0) {
        scrollView.setRemoteImages(configuration, revision: revision)
    }

    /// Adds a control to code blocks. The factory is called for each code block and
    /// returns a control framed in document coordinates, or nil to skip that block.
    public var codeBlockControl: ((RenderedCodeBlock) -> UIControl?)? {
        get { scrollView.codeBlockControl }
        set { scrollView.setCodeBlockControl(newValue, refresh: true) }
    }

    package var animatesDocumentChanges: Bool {
        get { scrollView.animatesDocumentChanges }
        set { scrollView.animatesDocumentChanges = newValue }
    }

    package func finish() { scrollView.finish() }
}

private final class ReaderScrollView: UIScrollView, UIScrollViewDelegate {
    nonisolated private static let signposter = OSSignposter(subsystem: "com.samuelhe.Kasumi", category: "ReaderReflow")
    let headingTopInset: CGFloat = 15
    private let findTopInset: CGFloat = 120

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
    private(set) var style = RenderStyle()
    private var remoteImages: MarkdownRemoteImages?
    private var imageRevision = 0
    private var imageResources: ReaderImageResources?
    private var displayScale: CGFloat = 1
    private let preparesLocalImages =
        ProcessInfo.processInfo.environment["KASUMI_READER_IMAGE_IDLE_PREPARATION"] == "1"
    private var headings: [(String, CGFloat)] = []
    private var fileURL: URL?
    private var installedFileURL: URL?
    var onPositionChange: ((ReadingAnchor, String?) -> Void)?
    var onOpenLink: ((URL) -> Void)?
    var onFindPresentationChange: ((Bool) -> Void)?
    var onFindResultChange: ((FindResult) -> Void)?
    private(set) var codeBlockControl: ((RenderedCodeBlock) -> UIControl?)?
    private var layoutTask: Task<Void, Never>?
    private let images = ReaderViewportImages()
    private var scrollWarmup: Task<Void, Never>?
    private var scrollWarmupID = UUID()
    private var generation = UUID()
    private var reflow = ReaderReflowState()
    private var reflowAnchor = ReaderReflowAnchorState()
    private var installedGeneration: UUID?
    private var installedRevision: UUID?
    private var finished = false
    private(set) var isActive = true
    var animatesDocumentChanges = false
    private var animateAppearanceReplacement = false
    private var adjusting = false
    private var scrollDiagnostics: ReaderScrollDiagnostics?
    private var nativeFind: (any ReaderFindNavigator)?
    private var wantsFind = false
    private var findPresentationTask: Task<Void, Never>?
    private var didReportFind = false
    private var systemFindActive = false
    private var programmaticFind = ProgrammaticFind()
    private var wantsProgrammaticReveal = false
    private var reportedFindResult = FindResult(count: 0, currentIndex: nil)
    private let unobscuredViewport = UILayoutGuide()
    private var currentFindRect: CGRect?
    private var currentFindAnchor: ReadingAnchor?

    enum ScrollTarget {
        case position(ReadingAnchor)
        case anchor(String, inset: CGFloat)
        case sourceLine(Int)
    }
    private enum PendingReveal {
        case target(ScrollTarget)
        case find
    }
    private var pendingNavigation: (target: ScrollTarget, animated: Bool)?
    private var pendingReveal: PendingReveal?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        alwaysBounceVertical = true
        contentInsetAdjustmentBehavior = .automatic
        if #available(iOS 26.0, *) { topEdgeEffect.style = .soft }
        addSubview(content)
        if #available(iOS 16.0, *) {
            nativeFind = UIKitReaderFind(
                view: self,
                snapshot: { [weak self] in self?.findSnapshot },
                update: { [weak self] matches, current, scroll in
                    guard let self, self.systemFindActive else { return }
                    self.displayFindResults(matches, current: current, scroll: scroll)
                },
                begin: { [weak self] in self?.didBeginNativeFind() },
                end: { [weak self] in self?.didEndNativeFind() })
        }
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
        accessibilityLabel = String(localized: "Document", bundle: .module)
        accessibilityIdentifier = "reader-surface"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        layoutTask?.cancel()
        scrollWarmup?.cancel()
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        if page?.containsCodeControl(view) == true { return true }
        return super.touchesShouldCancel(in: view)
    }

    func setDocument(_ document: MarkdownDocument, url: URL?, restoring anchor: ReadingAnchor?) {
        guard self.document?.readerIdentity != document.readerIdentity || fileURL != url else {
            if let anchor { navigate(to: .position(anchor), animated: false) }
            return
        }
        if fileURL == nil || fileURL != url {
            imageResources = nil
            reflowAnchor = ReaderReflowAnchorState()
            pendingReveal = nil
            if self.document != nil {
                pendingNavigation = nil
                suspendFind()
            }
        }
        if let anchor {
            reflowAnchor.navigate(to: anchor)
            pendingReveal = nil
            if rendered != nil { pendingNavigation = (.position(anchor), false) }
        }
        if rendered == nil {
            setPaper()
            openingIndicator.startAnimating()
        }
        self.document = document
        fileURL = url
        revision = UUID()
        invalidateSession(animate: animatesDocumentChanges)
    }

    func setStyle(_ style: RenderStyle) {
        guard self.style != style else { return }
        self.style = style
        if rendered == nil { setPaper() }
        invalidateReaderLayout()
    }

    func invalidateReaderLayout() { invalidateSession(animate: true) }

    func setRemoteImages(_ configuration: MarkdownRemoteImages?, revision: Int) {
        guard remoteImages?.id != configuration?.id || imageRevision != revision else { return }
        if remoteImages != nil, rendered?.hasReaderImages == true {
            // A new policy must not leave the previous provider's tiles visible.
            page?.isHidden = true
            transitionOverlay?.removeFromSuperview()
            transitionOverlay = nil
        }
        remoteImages = configuration
        imageRevision = revision
        imageResources = nil
        invalidateSession(animate: false)
    }

    func setCodeBlockControl(_ factory: ((RenderedCodeBlock) -> UIControl?)?, refresh: Bool) {
        codeBlockControl = factory
        if refresh { page?.installCodeControls(factory) }
    }

    private func invalidateSession(animate: Bool) {
        images.stop()
        cancelScrollWarmup()
        reflow.stop()
        reflowSession = nil
        // Retire requests immediately, even when a caller updates the style and
        // document together before the next UIKit layout pass starts a session.
        if installedGeneration == generation { animateAppearanceReplacement = false }
        generation = UUID()
        animateAppearanceReplacement = animateAppearanceReplacement || animate
        setNeedsLayout()
    }

    override var canBecomeFirstResponder: Bool { isActive && !finished && nativeFind != nil }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !finished else { return }
        if scrollDiagnostics == nil {
            scrollDiagnostics = ReaderScrollDiagnostics.make { [weak self] in
                guard let self, self.window != nil, self.isActive, !self.finished else { return nil }
                let visible = CGRect(x: 0, y: self.topY, width: self.bounds.width, height: self.bounds.height)
                return ReaderScrollDiagnostics.Viewport(
                    top: self.topY, width: self.bounds.width, height: self.bounds.height,
                    active: self.isDragging || self.isDecelerating || self.isTracking,
                    measured: self.rendered.map { !$0.needsLayout(in: visible) } ?? false,
                    fullyMeasured: self.rendered?.hasEstimatedGeometry == false)
            }
        }
        setNeedsLayout()
        updateImageViewport()
        scheduleScrollWarmup()
        presentFindIfNeeded()
    }

    override func layoutSubviews() {
        let wasAdjusting = adjusting
        adjusting = true
        super.layoutSubviews()
        let scale = max(1, traitCollection.displayScale)
        if scale != displayScale {
            displayScale = scale
            invalidateSession(animate: false)
        }
        rebuildIfNeeded()
        updateScrollExtent()
        updateKeyboardInset()
        updateHighlightViewport()
        adjusting = wasAdjusting
        if isActive, installedRevision == revision {
            if let pendingNavigation {
                navigate(to: pendingNavigation.target, animated: pendingNavigation.animated)
            }
            if wantsProgrammaticReveal { displayProgrammaticFind() }
        }
        updateImageViewport()
        updateLinkAccessibility()
        presentFindIfNeeded()
    }

    private func updateKeyboardInset() {
        let occluded = max(0, bounds.height - unobscuredViewport.layoutFrame.height)
        let automatic = adjustedContentInset.bottom - contentInset.bottom
        let inset = max(0, occluded - automatic)
        guard abs(contentInset.bottom - inset) > 0.5 else { return }
        contentInset.bottom = inset
        verticalScrollIndicatorInsets.bottom = inset
        if systemFindActive, let currentFindRect {
            setTop(max(0, currentFindRect.minY - findTopInset), trackingAnchor: true)
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
            reportPosition()
            images.stop()
            cancelScrollWarmup()
            reflow.stop()
            layoutTask?.cancel()
            suspendFind()
            scrollDiagnostics?.finish()
            scrollDiagnostics = nil
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

    var topSourceLine: Int? {
        guard installedRevision == revision else { return nil }
        return rendered?.readerSourceLine(atY: topY)
    }

    private func rebuildIfNeeded() {
        guard isActive, !finished, window != nil, bounds.width.isFinite, bounds.width > 0,
            bounds.height.isFinite, bounds.height > 0, let document
        else { return }
        if reflowSession == nil {
            let resources = imageResources ?? ReaderImageResources(remoteImages)
            imageResources = resources
            reflowSession = DocumentReflowSession(
                document, style: style, scrollableTables: true, readerDisplayScale: displayScale,
                readerResources: resources, preparesLocalImageLayout: preparesLocalImages)
        }
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
            if canCaptureInstalledPosition {
                reflowAnchor.captureIfNeeded(in: rendered, atY: topY, restoring: nil)
            }
            reflow.request(
                width: bounds.width, generation: generation, anchor: reflowAnchor.value, height: bounds.height)
        }
        guard layoutTask == nil, reflow.needsLayout else { return }
        // Do not cancel on width or style changes: synchronous typesetting cannot
        // stop midway. Drain the newest request after the current pipeline ends.
        layoutTask = Task { [weak self] in
            while !Task.isCancelled, let self, self.isActive, !self.finished, self.window != nil,
                let session = self.reflowSession, let revision = self.revision, let request = self.reflow.begin()
            {
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
                    try Task.checkCancellation()
                    let rect = self.visibleRect(in: next, restoring: self.reflowAnchor.value)
                    let coversViewport = !next.needsLayout(in: rect)
                    guard self.reflow.accepts(request, coversDesiredViewport: coversViewport) else {
                        _ = self.reflow.complete(request)
                        continue
                    }
                    let scale = self.displayScale
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
                    try Task.checkCancellation()
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
            if Task.isCancelled { self?.rebuildIfNeeded() }
            self?.scheduleScrollWarmup()
        }
    }

    private var canCaptureInstalledPosition: Bool {
        installedRevision == revision || (fileURL != nil && installedFileURL == fileURL)
    }

    private func cancelScrollWarmup() {
        scrollWarmupID = UUID()
        scrollWarmup?.cancel()
        scrollWarmup = nil
    }

    private func scheduleScrollWarmup() {
        guard scrollWarmup == nil, rendered?.hasEstimatedGeometry == true,
            isActive, !finished, window != nil, installedGeneration == generation, installedRevision == revision,
            let session = reflowSession, let revision
        else { return }
        let generation = self.generation
        let width = bounds.width
        let id = UUID()
        scrollWarmupID = id
        scrollWarmup = Task(priority: .utility) { [weak self] in
            defer { if self?.scrollWarmupID == id { self?.scrollWarmup = nil } }
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                guard let self, self.isActive, !self.finished, !self.isDragging, !self.isDecelerating,
                    self.layoutTask == nil, self.generation == generation, self.bounds.width == width
                else { return }
                guard let next = try await session.prepareForScrolling(width: width) else { return }
                try Task.checkCancellation()
                let rect = self.visibleRect(in: next, restoring: self.reflowAnchor.value)
                let scale = self.displayScale
                let offsets = self.page?.tableOffsets ?? [:]
                let preview = await Task.detached(priority: .utility) {
                    ReaderPageView.preview(next, rect: rect, scale: scale, tableOffsets: offsets)
                }.value
                try Task.checkCancellation()
                guard self.isActive, !self.finished, !self.isDragging, !self.isDecelerating,
                    self.generation == generation, self.bounds.width == width,
                    self.layoutTask == nil, !self.reflow.needsLayout
                else { return }
                self.install(
                    next, revision: revision, restoring: self.reflowAnchor.value,
                    preview: preview, previewRect: rect, animateReplacement: false)
            } catch is CancellationError {} catch { /* Foreground refinement remains available. */  }
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
        let selection = installedRevision == revision ? page?.selectionInput.selectionOffsets : nil
        let selectionTableID = page?.selectionTableID
        let hadTextFocus = page?.selectionInput.isFirstResponder == true
        let sameContent = installedRevision == revision
        let tableOffsets = sameContent ? page?.tableOffsets ?? [:] : [:]
        installedRevision = revision
        installedFileURL = fileURL
        let animate = !UIAccessibility.isReduceMotionEnabled && window != nil
        let widthChanged = rendered?.size.width != next.size.width
        let overlay =
            !firstLayout && animate && (animateReplacement || widthChanged)
            ? content.resizableSnapshotView(from: bounds, afterScreenUpdates: false, withCapInsets: .zero) : nil
        transitionOverlay?.removeFromSuperview()
        transitionOverlay = overlay
        let nextPage: ReaderPageView
        if sameContent, !animateReplacement, !widthChanged, let page {
            page.refine(
                next, scale: displayScale, preview: preview, previewRect: previewRect,
                codeBlockControl: codeBlockControl)
            nextPage = page
        } else {
            nextPage = ReaderPageView(
                rendered: next, scale: displayScale, preview: preview, previewRect: previewRect,
                codeBlockControl: codeBlockControl, tableOffsets: tableOffsets)
            content.addSubview(nextPage)
            page?.clearReaderSelection()
            page?.removeFromSuperview()
            if let selection { nextPage.restoreReaderSelection(selection, tableID: selectionTableID) }
        }
        rendered = next
        page = nextPage
        nextPage.isHidden = false
        nextPage.onLink = { [weak self] url in self?.follow(url) }
        nextPage.onTap = { [weak self] in self?.becomeFirstResponder() }
        nextPage.onTableScroll = { [weak self] in
            self?.updateImageViewport()
            self?.updateLinkAccessibility()
        }
        backgroundColor = UIColor(cgColor: next.backgroundColor)
        indicatorStyle = style.theme.appearance == .dark ? .white : .black
        headings = document?.outline.compactMap { item in next.readerAnchorY(for: item.id).map { (item.id, $0) } } ?? []
        updateScrollExtent()
        setTop(anchor.flatMap { next.y(for: $0) } ?? 0, preservingMomentum: true)
        reflowAnchor.didInstall(next, revision: revision, atY: topY)
        adjusting = false
        if let pendingNavigation {
            navigate(to: pendingNavigation.target, animated: pendingNavigation.animated)
        }
        findSnapshotDidChange(next)
        revealPendingTarget()
        presentFindIfNeeded()
        openingIndicator.stopAnimating()
        updateImageViewport()
        updateLinkAccessibility()
        if selection != nil && hadTextFocus { nextPage.selectionInput.becomeFirstResponder() }
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

    private func setPaper() {
        guard let c = style.theme.document["paper"] else { return }
        backgroundColor = UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    private func setTop(
        _ y: CGFloat, animated: Bool = false, trackingAnchor: Bool = false, preservingMomentum: Bool = false
    ) {
        let minimum = -adjustedContentInset.top
        let maximum = max(minimum, contentSize.height - bounds.height + adjustedContentInset.bottom)
        let offset = min(maximum, max(minimum, y - adjustedContentInset.top))
        if trackingAnchor {
            pendingReveal = nil
            reflowAnchor.moved(in: rendered, atY: max(0, offset + adjustedContentInset.top))
        }
        let target = CGPoint(x: 0, y: offset)
        if preservingMomentum {
            // The property setter adjusts the running deceleration. The animated
            // overload cancels it even with animated: false and the same offset.
            contentOffset = target
        } else {
            setContentOffset(target, animated: animated)
        }
        updateHighlightViewport()
        updateImageViewport()
        updateLinkAccessibility()
        if trackingAnchor && !animated {
            reflowAnchor.moved(in: rendered, atY: topY)
        }
    }

    func navigate(to target: ScrollTarget, animated: Bool) {
        guard !finished else { return }
        guard isActive, installedRevision == revision, let rendered else {
            pendingNavigation = (target, animated)
            if case .position(let anchor) = target {
                reflowAnchor.navigate(to: anchor)
                rebuildIfNeeded()
            }
            return
        }
        pendingNavigation = nil
        guard let destination = destination(for: target, in: rendered) else { return }
        let approximate = rendered.needsLayout(in: destination.rect.insetBy(dx: 0, dy: -1))
        adjusting = true
        setTop(
            max(0, destination.rect.minY - destination.inset),
            animated: animated && !approximate && !UIAccessibility.isReduceMotionEnabled, trackingAnchor: true)
        adjusting = false
        updateImageViewport()
        updateLinkAccessibility()
        if approximate, let anchor = destination.anchor {
            reflowAnchor.navigate(to: anchor)
            pendingReveal = .target(target)
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
        guard !adjusting, isActive, !finished else { return }
        updateImageViewport()
        updateLinkAccessibility()
        cancelScrollWarmup()
        if isDragging || isDecelerating { pendingReveal = nil }
        if canCaptureInstalledPosition && pendingNavigation == nil {
            reflowAnchor.moved(in: rendered, atY: topY)
        }
        reportPosition()
        rebuildIfNeeded()
        scheduleScrollWarmup()
    }
    private func updateHighlightViewport() {
        guard let page else { return }
        page.updateHighlightViewport(page.convert(bounds, from: self))
    }
    private func updateLinkAccessibility() {
        guard !adjusting, isActive, let page else { return }
        page.updateLinkAccessibility(in: page.convert(bounds, from: self))
    }

    private func updateImageViewport() {
        guard !adjusting, !finished, isActive, window != nil, installedRevision == revision,
            installedGeneration == generation, let page, let rendered
        else { return }
        images.update(
            rendered, in: page.convert(bounds, from: self), overscan: min(128, bounds.height * 0.25),
            tableOffsets: page.tableOffsets, invalidate: { [weak self] in self?.page?.invalidateImage($0) },
            relayout: { [weak self] in self?.invalidateSession(animate: false) })
    }

    private func reportPosition() {
        guard !finished, window != nil, installedRevision == revision, let rendered else { return }
        let y = topY
        let heading = headings.last { $0.1 <= y + headingTopInset }?.0 ?? headings.first?.0
        onPositionChange?(reflowAnchor.value ?? rendered.readingAnchor(atY: y), heading)
    }

    func finish() {
        guard !finished else { return }
        reportPosition()
        finished = true
        images.stop()
        cancelScrollWarmup()
        scrollDiagnostics?.finish()
        scrollDiagnostics = nil
        reflow.stop()
        reflowSession = nil
        dismissFind()
        layoutTask?.cancel()
        transitionOverlay?.removeFromSuperview()
        transitionOverlay = nil
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            setNeedsLayout()
            scheduleScrollWarmup()
        } else {
            images.stop()
            cancelScrollWarmup()
            reflow.stop()
            layoutTask?.cancel()
            reportPosition()
        }
        guard !active else { return }
        // UIKit may query the SwiftUI responder graph while dismissing Find.
        Task { @MainActor [weak self] in
            guard let self, !self.isActive, !self.finished else { return }
            self.suspendFind()
            self.page?.selectionInput.resignFirstResponder()
            self.resignFirstResponder()
        }
    }

    private var currentSnapshot: RenderedDocument? {
        !finished && installedRevision == revision ? rendered : nil
    }
    private var findSnapshot: RenderedDocument? { isActive ? currentSnapshot : nil }
    var canPresentFind: Bool { nativeFind != nil && isActive && !finished && document != nil }
    var isFindPresented: Bool { nativeFind?.isPresented == true }

    func presentFind() -> Bool {
        guard canPresentFind else { return false }
        if !isFindPresented {
            wantsFind = true
            presentFindIfNeeded()
        }
        return true
    }

    func dismissFind() {
        wantsFind = false
        suspendFind()
    }

    private func suspendFind() {
        findPresentationTask?.cancel()
        findPresentationTask = nil
        nativeFind?.dismiss()
    }

    private func presentFindIfNeeded() {
        guard wantsFind, findSnapshot != nil, window != nil, findPresentationTask == nil else { return }
        findPresentationTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.findPresentationTask = nil
            guard self.wantsFind, self.findSnapshot != nil, self.window != nil else { return }
            self.wantsFind = false
            self.becomeFirstResponder()
            self.nativeFind?.present()
        }
    }

    private func didBeginNativeFind() {
        systemFindActive = true
        page?.clearReaderSelection()
        programmaticFind.clear()
        wantsProgrammaticReveal = false
        publishFindResult()
        displayFindResults([], current: nil, scroll: false)
        reportFindPresentation(true)
    }

    private func didEndNativeFind() {
        if systemFindActive { displayFindResults([], current: nil, scroll: false) }
        systemFindActive = false
        reportFindPresentation(false)
        // Let UIKit finish resigning its search field, without taking focus back from the host.
        Task { @MainActor [weak self] in
            guard let self, self.canPresentFind, let window = self.window, window.isKeyWindow, !self.isFindPresented,
                !Self.containsFirstResponder(window)
            else { return }
            self.becomeFirstResponder()
        }
    }

    private static func containsFirstResponder(_ view: UIView) -> Bool {
        if view.isFirstResponder || (view.next as? UIViewController)?.isFirstResponder == true { return true }
        return view.subviews.contains(where: containsFirstResponder)
    }

    private func reportFindPresentation(_ presented: Bool) {
        guard didReportFind != presented else { return }
        didReportFind = presented
        onFindPresentationChange?(presented)
    }

    func setFindQuery(_ query: String, options: SearchOptions) {
        systemFindActive = false
        dismissFind()
        wantsProgrammaticReveal = !query.isEmpty
        programmaticFind.setQuery(query, options: options, in: currentSnapshot)
        displayProgrammaticFind()
    }

    func moveToFindMatch(_ direction: FindDirection) {
        guard !systemFindActive else { return }
        programmaticFind.move(direction)
        wantsProgrammaticReveal = true
        displayProgrammaticFind()
    }

    func clearFind() {
        programmaticFind.clear()
        wantsProgrammaticReveal = false
        if systemFindActive { publishFindResult() } else { displayProgrammaticFind() }
    }

    private func findSnapshotDidChange(_ rendered: RenderedDocument) {
        nativeFind?.install(rendered)
        if !systemFindActive {
            programmaticFind.install(rendered)
            displayProgrammaticFind()
        }
    }

    private func publishFindResult() {
        let result = programmaticFind.result
        guard result != reportedFindResult else { return }
        reportedFindResult = result
        onFindResultChange?(result)
    }

    private func displayProgrammaticFind() {
        let reveal = findSnapshot != nil && wantsProgrammaticReveal
        if reveal { wantsProgrammaticReveal = false }
        if installedRevision == revision {
            displayFindResults(programmaticFind.ranges, current: programmaticFind.currentIndex, scroll: reveal)
        }
        publishFindResult()
    }

    private func displayFindResults(_ matches: [TextRange], current: Int?, scroll: Bool) {
        let refiningFindMatch = if case .find = pendingReveal { true } else { false }
        if scroll || refiningFindMatch, let current, matches.indices.contains(current) {
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
            max(0, rect.minY - (systemFindActive ? findTopInset : headingTopInset)),
            animated: !approximate && !UIAccessibility.isReduceMotionEnabled,
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
        guard isActive, installedFileURL == fileURL else { return }
        if let fragment = readerDocumentFragment(in: url, documentURL: fileURL) {
            // An unresolved same-document fragment is not an external URL.
            navigate(to: .anchor(fragment, inset: 8), animated: true)
        } else {
            onOpenLink?(url)
        }
    }

    private func destination(
        for target: ScrollTarget, in rendered: RenderedDocument
    ) -> (rect: CGRect, inset: CGFloat, anchor: ReadingAnchor?)? {
        switch target {
        case .position(let anchor):
            guard let y = rendered.y(for: anchor) else { return nil }
            return (CGRect(x: 0, y: y, width: rendered.size.width, height: 1), 0, anchor)
        case .anchor(let id, let inset):
            guard let rect = rendered.rect(forAnchor: id) else { return nil }
            return (rect, inset, rendered.readingAnchor(forAnchor: id))
        case .sourceLine(let line):
            guard let y = rendered.readerSourceTop(for: line) else { return nil }
            return (CGRect(x: 0, y: y, width: rendered.size.width, height: 1), 0, rendered.readingAnchor(atY: y))
        }
    }

    private func revealPendingTarget() {
        guard let pendingReveal, let rendered else { return }
        let rect: CGRect?
        let inset: CGFloat
        switch pendingReveal {
        case .target(let target):
            let destination = destination(for: target, in: rendered)
            rect = destination?.rect
            inset = destination?.inset ?? 0
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
    private weak var selectionTable: ReaderTableScrollView?
    var selectionTableID: Int? { selectionTable?.tableID }
    var selectionInput: ReaderTextInputView { selectionTable?.textInput ?? self }
    var onLink: ((URL) -> Void)?
    var onTap: (() -> Void)?
    var onTableScroll: (() -> Void)?
    private var seedLayer: CALayer?
    private var tileLayer: ReaderTileLayer?
    private var codeControls: [UIControl] = []
    private lazy var textElement = UIAccessibilityElement(accessibilityContainer: self)
    private var accessibilityViewport = CGRect.null
    private var linkWindow = CGRect.null
    private var cachedAccessibilityElements: [Any]?
    var tableOffsets: [Int: CGFloat] {
        var offsets: [Int: CGFloat] = [:]
        for table in tableScrollViews where table.contentOffset.x != 0 {
            offsets[table.tableID] = table.contentOffset.x
        }
        return offsets
    }

    init(
        rendered: RenderedDocument, scale: CGFloat, preview: ReaderPagePreview?, previewRect: CGRect,
        codeBlockControl: ((RenderedCodeBlock) -> UIControl?)?, tableOffsets: [Int: CGFloat] = [:]
    ) {
        super.init(rendered: rendered)
        onBeginSelection = { [weak self] in self?.changeSelectionTable(to: nil) }
        onDocumentTap = { [weak self] point in self?.handleTap(at: point) }
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
        updateAccessibleText()
        installCodeControls(codeBlockControl)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refine(
        _ next: RenderedDocument, scale: CGFloat, preview: ReaderPagePreview?, previewRect: CGRect,
        codeBlockControl: ((RenderedCodeBlock) -> UIControl?)?
    ) {
        highlightIndex = nil
        highlightWindow = .null
        frame.size = next.size
        replaceRendered(next)
        installDrawingLayers(scale: scale, preview: preview, previewRect: previewRect)
        installTables(scale: scale, preview: preview)
        updateAccessibleText()
        installCodeControls(codeBlockControl)
    }

    /// Viewport refinement moves code blocks as estimated heights become exact.
    func installCodeControls(_ factory: ((RenderedCodeBlock) -> UIControl?)?) {
        for control in codeControls { control.removeFromSuperview() }
        codeControls = factory.map { rendered.codeBlocks.compactMap($0) } ?? []
        for control in codeControls { addSubview(control) }
        textElement.accessibilityCustomActions = codeControls.flatMap { $0.accessibilityCustomActions ?? [] }
        cachedAccessibilityElements = nil
    }

    func containsCodeControl(_ view: UIView) -> Bool {
        codeControls.contains { view === $0 || view.isDescendant(of: $0) }
    }

    private func updateAccessibleText() {
        isAccessibilityElement = false
        textElement.accessibilityLabel = rendered.readerSemanticText
        textElement.accessibilityTraits = .staticText
        textElement.accessibilityFrameInContainerSpace = bounds
        linkWindow = .null
        cachedAccessibilityElements = nil
    }

    func updateLinkAccessibility(in viewport: CGRect) { accessibilityViewport = viewport }

    override var accessibilityElements: [Any]? {
        get {
            // Geometry is queried when UIKit needs the accessibility tree, not
            // synchronously on every native scroll or table drag callback.
            let visible = accessibilityViewport.intersection(bounds)
            if let cachedAccessibilityElements, visible.isNull || linkWindow.contains(visible) {
                return cachedAccessibilityElements
            }
            var elements: [NSObject] = [textElement]
            elements += tableScrollViews
            elements += codeControls
            linkWindow = visible.insetBy(dx: 0, dy: -max(128, visible.height * 0.5)).intersection(bounds)
            if !linkWindow.isNull, !linkWindow.isEmpty {
                for link in rendered.readerLinks(in: linkWindow, tableOffsets: tableOffsets) {
                    let element = ReaderLinkAccessibilityElement(container: self, url: link.url)
                    element.accessibilityFrameInContainerSpace = link.rect
                    element.activate = { [weak self] in self?.onLink?(link.url) }
                    elements.append(element)
                }
            }
            cachedAccessibilityElements = elements
            return elements
        }
        set {
            cachedAccessibilityElements = newValue
            linkWindow = accessibilityViewport.intersection(bounds)
        }
    }

    func restoreReaderSelection(_ offsets: (Int, Int), tableID: Int?) {
        selectionTable = tableScrollViews.first { $0.tableID == tableID }
        selectionInput.restoreSelection(offsets)
    }

    func clearReaderSelection() {
        selectionInput.clearSelection()
        selectionTable = nil
    }

    private func changeSelectionTable(to table: ReaderTableScrollView?) {
        guard selectionTable !== table else { return }
        clearReaderSelection()
        selectionTable = table
    }

    private func handleTap(at point: CGPoint) {
        let hadSelection = selectionInput.hasSelection
        if hadSelection { clearReaderSelection() }
        onTap?()
        if !hadSelection, let url = rendered.link(at: point) { onLink?(url) }
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
                scroll.onScroll = { [weak self] in
                    self?.linkWindow = .null
                    self?.paintHighlights()
                    self?.onTableScroll?()
                }
                scroll.onBeginDragging = { [weak self, weak scroll] in
                    // Keep a table-local selection attached to its text while it scrolls.
                    guard let self, self.selectionTable !== scroll else { return }
                    self.clearReaderSelection()
                }
                scroll.textInput.onBeginSelection = { [weak self, weak scroll] in
                    self?.changeSelectionTable(to: scroll)
                }
                scroll.textInput.onDocumentTap = { [weak self] point in self?.handleTap(at: point) }
                addSubview(scroll)
            }
            next.append(scroll)
        }
        for obsolete in existing.values { obsolete.removeFromSuperview() }
        tableScrollViews = next
    }

    func invalidateImage(_ region: ReaderImageRegion) {
        let rect = region.rect.insetBy(dx: -1, dy: -1)
        if let id = region.tableID {
            tableScrollViews.first { $0.tableID == id }?.invalidateImage(in: rect)
        } else {
            tileLayer?.setNeedsDisplay(rect)
        }
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

private final class ReaderLinkAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Void)?

    init(container: UIView, url: URL) {
        super.init(accessibilityContainer: container)
        accessibilityLabel = url.absoluteString
        accessibilityTraits = .link
    }

    override func accessibilityActivate() -> Bool {
        guard let activate else { return false }
        activate()
        return true
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
#endif
