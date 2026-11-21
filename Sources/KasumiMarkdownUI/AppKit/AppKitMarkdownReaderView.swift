#if os(macOS)
import AppKit
import KasumiMarkdown
import os

/// A read-only Markdown viewport backed by immutable, progressively refined layouts.
@MainActor public final class MarkdownReaderView: NSView, NSUserInterfaceValidations {
    public var style = RenderStyle() {
        didSet { if style != oldValue { invalidateLayout() } }
    }
    public var isActive = true {
        didSet {
            guard isActive != oldValue else { return }
            if isActive {
                requestLayout()
            } else {
                dismissFind()
                canvas.endDrag()
                cancelWork()
                find.finder.cancelFindIndicator()
            }
        }
    }
    public var onPositionChange: ((ReadingAnchor, String?) -> Void)?
    public var onOpenLink: ((URL) -> Void)?
    public var onFindPresentationChange: ((Bool) -> Void)?
    public var onFindResultChange: ((FindResult) -> Void)?

    private let scrollView = ReaderVerticalScrollView()
    let canvas = ReaderCanvas()
    let find = ReaderNativeFind()
    private var document: MarkdownDocument?
    private var documentURL: URL?
    private var installedDocument: UUID?
    private var generation = UUID()
    private var installedGeneration: UUID?
    private var session: DocumentReflowSession?
    private var state = ReaderReflowState()
    private var anchor = ReaderReflowAnchorState()
    private var pendingReveal: Reveal?
    private var layoutTask: Task<Void, Never>?
    private var warmup: Task<Void, Never>?
    private var warmupID = UUID()
    private var adjusting = false
    private var previousViewport = CGRect.zero
    private var installedHeight: CGFloat = 0
    private var sectionPositions: [(y: CGFloat, id: String)] = []
    private var outline: [OutlineItem] = []
    private var lastPosition: (ReadingAnchor, String?)?
    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }
    private var sessionScale: CGFloat = 0
    private var configuration: MarkdownRemoteImages?
    private var resourceRevision = 0
    private var imageResources = ReaderImageResources(nil)
    private var imageTask: Task<Void, Never>?
    private var imageWorker: (region: ReaderImageRegion, task: Task<ReaderResourceUpdate, Never>)?
    private weak var imageSnapshot: RenderedDocument?
    private var visibleImages: [ReaderImageRegion] = []
    private var pendingImages: ArraySlice<ReaderImageRegion> = []
    private var tableViews: [Int: ReaderTableScrollView] = [:]
    private(set) var tableOffsets: [Int: CGFloat] = [:]
    private(set) var rendered: RenderedDocument?
    private var customFind = ProgrammaticFind()
    private var highlightIndex: ReaderHighlightIndex?

    private let signposter = OSSignposter(subsystem: "com.samuelhe.Kasumi.MarkdownReader", category: "Reflow")
    private var installations = 0
    private var layoutMilliseconds: Double?
    private var warmupMilliseconds: Double?
    package var readerPreparesForScrolling = true {
        didSet {
            if readerPreparesForScrolling { scheduleWarmup() } else { cancelWarmup() }
        }
    }
    package var onReaderLayout: (() -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        canvas.owner = self
        find.owner = self
        scrollView.owner = self
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = canvas
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        NotificationCenter.default.addObserver(
            self, selector: #selector(userWillScroll), name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView)
        addSubview(scrollView)
        find.finder.client = find
        find.finder.findBarContainer = find
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("Use init(frame:) instead") }

    deinit {
        layoutTask?.cancel()
        warmup?.cancel()
        imageTask?.cancel()
        imageWorker?.task.cancel()
    }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    @objc func copy(_ sender: Any?) { canvas.copy(sender) }
    public override func selectAll(_ sender: Any?) { canvas.selectAll(sender) }
    public override func performTextFinderAction(_ sender: Any?) { canvas.performTextFinderAction(sender) }
    public func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        canvas.validateUserInterfaceItem(item)
    }

    public override func layout() {
        super.layout()
        viewportChanged()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            dismissFind()
            canvas.endDrag()
            cancelWork()
        } else {
            if sessionScale != scale { invalidateLayout() }
            requestLayout()
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if sessionScale != scale { invalidateLayout() }
    }

    /// Install new content. An explicit anchor takes precedence over the initial top.
    public func setDocument(_ document: MarkdownDocument, url: URL? = nil, restoring anchor: ReadingAnchor? = nil) {
        documentURL = url
        if document.readerIdentity == self.document?.readerIdentity {
            if let anchor { scroll(to: anchor, animated: false) }
            return
        }
        cancelWork()
        session = nil
        adjusting = true
        find.noteStringWillChange()
        self.document = document
        outline = document.outline
        imageResources = ReaderImageResources(configuration)
        installedDocument = nil
        installedGeneration = nil
        rendered = nil
        sectionPositions = []
        lastPosition = nil
        installations = 0
        layoutMilliseconds = nil
        anchorStateReset(restoring: anchor)
        canvas.replaceDocument()
        customFind.clear()
        highlightIndex = nil
        tableOffsets.removeAll()
        removeTableViews()
        updateCanvasFrame(size: .zero)
        adjusting = false
        restartSession()
        onFindResultChange?(customFind.result)
    }

    /// Invalidate geometry after resources such as system fonts become available.
    public func invalidateLayout() { restartSession() }

    public func setRemoteImages(_ configuration: MarkdownRemoteImages?, revision: Int = 0) {
        guard self.configuration?.id != configuration?.id || resourceRevision != revision else { return }
        self.configuration = configuration
        resourceRevision = revision
        imageResources = ReaderImageResources(configuration)
        // Do not leave pixels from a revoked provider visible during replacement.
        if self.rendered?.hasReaderImages == true {
            rendered = nil
            canvas.preview = nil
            canvas.endDrag()
            canvas.invalidateLinkCursors()
            canvas.needsDisplay = true
            removeTableViews()
        }
        restartSession()
    }

    public func scroll(to anchor: ReadingAnchor, animated: Bool = true) {
        reveal(.anchor(anchor), animated: animated)
    }

    public func scroll(toAnchorID id: String, animated: Bool = true) {
        reveal(.heading(id), animated: animated)
    }

    private func anchorStateReset(restoring restored: ReadingAnchor?) {
        anchor = ReaderReflowAnchorState()
        if let restored { anchor.navigate(to: restored) }
        pendingReveal = restored.map { Reveal(target: .anchor($0)) }
    }

    private func restartSession() {
        guard let document else { return }
        anchor.captureIfNeeded(in: rendered, atY: viewport.minY, restoring: nil)
        cancelWork()
        generation = UUID()
        sessionScale = scale
        session = DocumentReflowSession(
            document, style: style, scrollableTables: true, readerDisplayScale: sessionScale,
            readerResources: imageResources, preparesLocalImageLayout: true)
        requestLayout()
    }

    private func cancelWork() {
        state.stop()
        cancelWarmup()
        warmupMilliseconds = nil
        imageWorker?.task.cancel()
        imageSnapshot = nil
        visibleImages.removeAll()
        pendingImages = []
        // Do not cancel the single publisher. Let its active render drain;
        // the stopped state and generation reject any stale completion.
    }

    var viewport: CGRect { scrollView.contentView.bounds }
    var nativeFindBarContainer: any NSTextFinderBarContainer { scrollView }
    private var canLayout: Bool { isActive && window != nil }

    @objc private func boundsChanged() { viewportChanged() }

    private func viewportChanged() {
        guard !adjusting else { return }
        let now = viewport
        guard now != previousViewport else { return }
        let sizeChanged = now.size != previousViewport.size
        previousViewport = now
        cancelWarmup()
        if !sizeChanged, rendered != nil, pendingReveal == nil {
            anchor.moved(in: rendered, atY: max(0, now.minY))
        }
        updateTables()
        canvas.invalidateLinkCursors()
        requestLayout()
        findBarVisibilityChanged()
        publishPosition()
    }

    private func requestLayout() {
        guard canLayout, session != nil else { return }
        let viewport = viewport
        guard viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0 else { return }
        updateImages()
        if rendered?.size.width != viewport.width {
            cancelWarmup()
            warmupMilliseconds = nil
        }
        let overscan = viewport.insetBy(dx: 0, dy: -viewport.height * 0.75)
        if installedGeneration == generation, let rendered, rendered.size.width == viewport.width,
            installedHeight == viewport.height, pendingReveal == nil,
            !rendered.needsLayout(in: overscan), let installed = state.installed
        {
            state.request(width: installed.width, generation: generation, anchor: installed.anchor, height: installed.height)
        } else {
            anchor.captureIfNeeded(in: rendered, atY: max(0, viewport.minY), restoring: nil)
            state.request(width: viewport.width, generation: generation, anchor: anchor.value, height: viewport.height)
        }
        guard layoutTask == nil, state.needsLayout else {
            scheduleWarmup()
            return
        }
        cancelWarmup()
        layoutTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.canLayout, let session = self.session, let request = self.state.begin() {
                let start = ContinuousClock.now
                let layout = self.signposter.beginInterval("Layout", id: self.signposter.makeSignpostID())
                let next = await session.render(width: request.width, viewportHeight: request.height, anchor: request.anchor)
                self.signposter.endInterval("Layout", layout)
                let rect = self.paintRect(next, width: request.width, height: request.height)
                guard self.state.accepts(request, coversDesiredViewport: !next.needsLayout(in: rect)) else {
                    _ = self.state.complete(request)
                    continue
                }
                let scale = self.scale
                let paint = self.signposter.beginInterval("ViewportPaint", id: self.signposter.makeSignpostID())
                let preview = await Task.detached(priority: .userInitiated) {
                    ReaderViewportBitmap.paint(next, rect: rect, scale: scale, excludingScrollableTables: true)
                }.value
                self.signposter.endInterval("ViewportPaint", paint)
                let liveRect = self.paintRect(next, width: request.width, height: request.height)
                if self.state.complete(request, coversDesiredViewport: !next.needsLayout(in: liveRect)), self.canLayout {
                    let interval = self.signposter.beginInterval("Install", id: self.signposter.makeSignpostID())
                    let previousFind = self.install(
                        next, preview: preview, top: liveRect.isNull ? 0 : liveRect.minY, height: request.height)
                    self.signposter.endInterval("Install", interval)
                    self.layoutMilliseconds = Self.milliseconds(since: start)
                    self.didInstall(previousFind: previousFind)
                }
            }
            self?.layoutTask = nil
            if self?.state.needsLayout == true { self?.requestLayout() } else { self?.scheduleWarmup() }
        }
    }

    private func paintRect(_ next: RenderedDocument, width: CGFloat, height: CGFloat) -> CGRect {
        let semanticTop = anchor.value.flatMap { next.y(for: $0) } ?? 0
        let top = pendingReveal.flatMap { revealGeometry($0.target, in: next)?.top } ?? semanticTop
        let visible = CGRect(x: 0, y: max(0, min(max(0, next.size.height - height), top)), width: width, height: height)
        return visible.intersection(CGRect(origin: .zero, size: next.size))
    }

    private func install(
        _ next: RenderedDocument, preview: ReaderViewportBitmap?, top: CGFloat, height: CGFloat
    ) -> FindResult {
        adjusting = true
        find.finder.cancelFindIndicator()
        rendered = next
        installedGeneration = generation
        installedHeight = height
        sectionPositions = outline.compactMap { item in
            next.readingAnchor(forAnchor: item.id).flatMap { next.y(for: $0) }.map { ($0, item.id) }
        }.sorted { $0.y < $1.y }
        canvas.preview = preview
        updateCanvasFrame(size: next.size)
        scrollDirectly(top: top)
        if installedDocument != document?.readerIdentity, let identity = document?.readerIdentity {
            anchor.didInstall(next, revision: identity, atY: viewport.minY)
            find.installString(next.readerSemanticText)
            installedDocument = identity
        }
        if let reveal = pendingReveal, let geometry = revealGeometry(reveal.target, in: next) {
            if let rect = geometry.horizontalTarget { revealHorizontally(rect) }
            let visible = viewport.intersection(CGRect(origin: .zero, size: next.size))
            if next.needsLayout(in: visible), anchor.value != geometry.anchor {
                anchor.navigate(to: geometry.anchor)
            } else {
                pendingReveal = nil
                anchor.moved(in: next, atY: viewport.minY)
            }
        } else {
            pendingReveal = nil // A missing fragment is not a persistent scroll request.
        }
        previousViewport = viewport
        updateTables(refresh: true)
        let previousFind = customFind.result
        customFind.install(next)
        highlightIndex = ReaderHighlightIndex(customFind.ranges, in: next)
        canvas.needsDisplay = true
        installations += 1
        adjusting = false
        updateImages()
        return previousFind
    }

    private func didInstall(previousFind: FindResult) {
        if pendingReveal != nil || installedHeight != viewport.height || rendered?.size.width != viewport.width {
            requestLayout()
        }
        if previousFind != customFind.result { customFindDidChange(reveal: previousFind.currentIndex == nil) }
        if find.presentationPending, canPresentFind { _ = presentFind() }
        canvas.invalidateLinkCursors()
        NSAccessibility.post(element: canvas, notification: .layoutChanged)
        publishPosition()
        onReaderLayout?()
    }

    private func updateCanvasFrame(size: CGSize) {
        let height = viewport.height
        canvas.frame = CGRect(x: 0, y: 0, width: max(viewport.width, size.width), height: max(height, size.height))
        if size == .zero { scrollDirectly(top: 0) }
    }

    private func cancelWarmup() {
        warmupID = UUID()
        warmup?.cancel()
        warmup = nil
    }

    private func scheduleWarmup() {
        guard readerPreparesForScrolling, canLayout, warmup == nil, layoutTask == nil, !state.needsLayout,
            installedGeneration == generation, rendered?.hasEstimatedGeometry == true, let session
        else { return }
        let expected = generation
        let width = viewport.width
        let id = UUID()
        warmupID = id
        warmup = Task(priority: .utility) { [weak self] in
            defer { if self?.warmupID == id { self?.warmup = nil } }
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard let self, self.canLayout, self.generation == expected, self.layoutTask == nil,
                    self.viewport.width == width
                else { return }
                let start = ContinuousClock.now
                guard let full = try await session.prepareForScrolling(width: width) else { return }
                try Task.checkCancellation()
                let height = self.viewport.height
                let rect = self.paintRect(full, width: width, height: height)
                let scale = self.scale
                let preview = await Task.detached(priority: .utility) {
                    ReaderViewportBitmap.paint(full, rect: rect, scale: scale, excludingScrollableTables: true)
                }.value
                try Task.checkCancellation()
                guard self.canLayout, self.generation == expected, self.layoutTask == nil, !self.state.needsLayout,
                    self.viewport.size == CGSize(width: width, height: height)
                else { return }
                let previousFind = self.install(full, preview: preview, top: rect.isNull ? 0 : rect.minY, height: height)
                self.warmupMilliseconds = Self.milliseconds(since: start)
                self.didInstall(previousFind: previousFind)
            } catch is CancellationError {
                // Cancelled idle work retains completed actor preparation at this width.
            } catch {
                self?.signposter.emitEvent("IdlePreparationFailed")
            }
        }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    }

    private func updateImages() {
        guard canLayout, installedGeneration == generation, let rendered, rendered.hasReaderImages else {
            imageWorker?.task.cancel()
            imageSnapshot = nil
            pendingImages = []
            visibleImages.removeAll()
            return
        }
        let regions = rendered.readerImageRegions(in: viewport.insetBy(dx: 0, dy: -viewport.height * 0.25), tableOffsets: tableOffsets)
        let sameSnapshot = imageSnapshot === rendered
        guard !sameSnapshot || visibleImages != regions else { return }
        let previous = sameSnapshot ? visibleImages : []
        imageSnapshot = rendered
        visibleImages = regions
        if let imageWorker, !sameSnapshot || !regions.contains(where: { $0.sharesRaster(with: imageWorker.region) }) {
            imageWorker.task.cancel()
        }
        pendingImages = regions.filter { region in
            if !rendered.hasReaderImageResult(for: region) { return true }
            if !previous.contains(region) { invalidateImage(region) }
            return false
        }[...]
        guard imageTask == nil, !pendingImages.isEmpty else { return }
        imageTask = Task { [weak self] in
            while !Task.isCancelled, let snapshot = self?.imageSnapshot, let region = self?.pendingImages.popFirst() {
                guard !snapshot.hasReaderImageResult(for: region) else { continue }
                let expected = self?.generation
                let worker = Task.detached(priority: .userInitiated) { await snapshot.prepareReaderResource(region) }
                self?.imageWorker = (region, worker)
                let result = await worker.value
                guard let self else { return }
                self.imageWorker = nil
                guard !Task.isCancelled, self.generation == expected, self.canLayout,
                    self.installedGeneration == expected
                else { continue }
                switch result {
                case .none: break
                case .pixels:
                    for visible in self.visibleImages where visible.sharesRaster(with: region) { self.invalidateImage(visible) }
                case .geometry:
                    self.restartSession()
                }
            }
            self?.imageTask = nil
        }
    }

    private func invalidateImage(_ region: ReaderImageRegion) {
        if let id = region.tableID { tableViews[id]?.tableCanvas.setNeedsDisplay(region.rect.insetBy(dx: -1, dy: -1)) }
        else { canvas.invalidateImage(in: region.rect) }
    }

    /// Whether native Find may be requested. First presentation waits for layout.
    public var canPresentFind: Bool { isActive && document != nil }
    public var isFindPresented: Bool { find.isFindBarVisible }

    @discardableResult public func presentFind() -> Bool {
        guard canPresentFind else { return false }
        if isFindPresented { return true }
        guard canLayout, rendered != nil, installedGeneration == generation else {
            find.presentationPending = true
            return true
        }
        find.presentationPending = false
        let finder = find.finder
        guard finder.validateAction(.showFindInterface) else { return false }
        clearFind()
        window?.makeFirstResponder(canvas)
        finder.performAction(.showFindInterface)
        return isFindPresented
    }

    public func dismissFind() {
        find.presentationPending = false
        if isFindPresented { find.finder.performAction(.hideFindInterface) }
        if case .nativeFindMatch? = pendingReveal?.target { userWillScroll() }
        if isFindPresented { find.isFindBarVisible = false }
        find.clearSelection()
    }

    public func setFindQuery(_ query: String, options: SearchOptions = []) {
        dismissFind()
        if case .findMatch? = pendingReveal?.target { userWillScroll() }
        guard !query.isEmpty else { clearFind(); return }
        customFind.setQuery(query, options: options, in: installedGeneration == generation ? rendered : nil)
        customFindDidChange(reveal: true)
    }

    public func moveToFindMatch(_ direction: FindDirection) {
        guard !isFindPresented, !find.presentationPending else { return }
        customFind.move(direction)
        customFindDidChange(reveal: true)
    }

    public func clearFind() {
        let before = customFind.result
        customFind.clear()
        highlightIndex = nil
        if case .findMatch? = pendingReveal?.target { userWillScroll() }
        setHighlightsNeedDisplay()
        if before != customFind.result { onFindResultChange?(customFind.result) }
    }

    private func customFindDidChange(reveal: Bool) {
        highlightIndex = rendered.flatMap { ReaderHighlightIndex(customFind.ranges, in: $0) }
        if reveal, let rendered, let index = customFind.currentIndex,
            let range = rendered.readerSemanticRange(for: customFind.ranges[index])
        {
            self.reveal(.findMatch(range), animated: false)
        }
        setHighlightsNeedDisplay()
        onFindResultChange?(customFind.result)
    }

    func findBarVisibilityChanged() {
        guard isFindPresented != reportedFindVisibility else { return }
        reportedFindVisibility = isFindPresented
        if isFindPresented {
            clearFind()
        } else {
            if case .nativeFindMatch? = pendingReveal?.target { userWillScroll() }
            find.clearSelection()
        }
        onFindPresentationChange?(isFindPresented)
    }

    private var reportedFindVisibility = false

    func validateFindAction(_ action: NSTextFinder.Action) -> Bool {
        if action == .showFindInterface { return canPresentFind }
        return rendered != nil && isActive && find.finder.validateAction(action)
    }

    func performFindAction(_ action: NSTextFinder.Action) {
        if action == .showFindInterface { _ = presentFind(); return }
        if action == .hideFindInterface { dismissFind(); return }
        guard validateFindAction(action) else { return }
        clearFind()
        find.finder.performAction(action)
    }

    package func finish() { isActive = false }

    private enum RevealTarget {
        case anchor(ReadingAnchor)
        case heading(String)
        case range(NSRange)
        case findMatch(NSRange)
        case nativeFindMatch(NSRange)
    }

    private struct Reveal {
        let target: RevealTarget
    }

    func revealText(_ range: NSRange) { reveal(.range(range), animated: false) }
    func revealNativeFindMatch(_ range: NSRange) { reveal(.nativeFindMatch(range), animated: false) }

    private func reveal(_ target: RevealTarget, animated: Bool) {
        guard document != nil else { return }
        guard canLayout, installedGeneration == generation, let rendered,
            let geometry = revealGeometry(target, in: rendered)
        else {
            if installedGeneration != generation || rendered == nil || !canLayout {
                pendingReveal = Reveal(target: target)
                if case .anchor(let destination) = target { anchor.navigate(to: destination) }
                requestLayout()
            }
            return
        }
        let top = max(0, min(max(0, rendered.size.height - viewport.height), geometry.top))
        let rect = CGRect(origin: CGPoint(x: 0, y: top), size: viewport.size)
            .intersection(CGRect(origin: .zero, size: rendered.size))
        if rendered.needsLayout(in: rect) {
            pendingReveal = Reveal(target: target)
            anchor.navigate(to: geometry.anchor)
            requestLayout()
            return
        }
        pendingReveal = nil
        if let horizontalTarget = geometry.horizontalTarget { revealHorizontally(horizontalTarget) }
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, abs(top - viewport.minY) > 0.5 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.allowsImplicitAnimation = true
                scrollView.contentView.animator().setBoundsOrigin(CGPoint(x: 0, y: top))
            }
        } else {
            scrollDirectly(top: top)
            viewportChanged()
        }
    }

    private func revealGeometry(
        _ target: RevealTarget, in rendered: RenderedDocument
    ) -> (anchor: ReadingAnchor, top: CGFloat, horizontalTarget: CGRect?)? {
        switch target {
        case .anchor(let anchor):
            return rendered.y(for: anchor).map { (anchor, $0, nil) }
        case .heading(let id):
            guard let anchor = rendered.readingAnchor(forAnchor: id), let y = rendered.y(for: anchor) else { return nil }
            return (anchor, y - 12, nil)
        case .range(let range), .findMatch(let range), .nativeFindMatch(let range):
            guard let selection = rendered.readerTextRange(for: range),
                let anchor = rendered.readingAnchor(at: selection.lowerBound)
            else { return nil }
            let caret = rendered.caretRect(for: selection.lowerBound)
            let endCaret = rendered.caretRect(for: selection.upperBound)
            let line = caret.minY == endCaret.minY ? caret.union(endCaret) : caret
            let top = line.minY < viewport.minY + 6 ? line.minY - 12
                : line.maxY > viewport.maxY - 6 ? line.maxY - viewport.height + 12
                : viewport.minY
            return (anchor, top, line)
        }
    }

    private func scrollDirectly(top: CGFloat) {
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: max(0, top)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc func userWillScroll() {
        guard pendingReveal != nil else { return }
        pendingReveal = nil
        anchor.moved(in: rendered, atY: viewport.minY)
        requestLayout()
    }

    func activateLink(_ url: URL) {
        if let fragment = url.fragment, url.scheme == nil || (url.isFileURL && url.path == documentURL?.path) {
            scroll(toAnchorID: fragment)
        } else {
            onOpenLink?(url)
        }
    }

    private func publishPosition() {
        guard isActive, installedGeneration == generation, let rendered else { return }
        let top = max(0, viewport.minY)
        let reading = rendered.readingAnchor(atY: top)
        var lower = 0
        var upper = sectionPositions.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if sectionPositions[middle].y <= top + 12.5 { lower = middle + 1 } else { upper = middle }
        }
        let section = lower > 0 ? sectionPositions[lower - 1].id : nil
        guard lastPosition?.0 != reading || lastPosition?.1 != section else { return }
        lastPosition = (reading, section)
        onPositionChange?(reading, section)
    }

    func table(at point: CGPoint) -> RenderedTable? {
        rendered?.tables.first { $0.isScrollable && $0.frame.contains(point) }
    }

    func semanticPoint(_ point: CGPoint) -> CGPoint {
        guard let table = table(at: point) else { return point }
        return CGPoint(x: point.x + (tableOffsets[table.id] ?? 0), y: point.y)
    }

    func scrollableTable(near point: CGPoint) -> RenderedTable? {
        scrollableTable(atY: point.y).flatMap { table in
            (table.frame.minX - 30 ... table.frame.maxX + 30).contains(point.x) ? table : nil
        }
    }

    private func scrollableTable(atY y: CGFloat) -> RenderedTable? {
        rendered?.tables.first { $0.isScrollable && y >= $0.frame.minY && y < $0.frame.maxY }
    }

    func visibleSelectionRect(_ rect: CGRect) -> CGRect {
        guard let table = scrollableTable(atY: rect.midY) else { return rect }
        return rect.offsetBy(dx: -(tableOffsets[table.id] ?? 0), dy: 0).intersection(table.frame)
    }

    private func revealHorizontally(_ rect: CGRect) {
        guard let table = scrollableTable(atY: rect.midY) else { return }
        let current = tableOffsets[table.id] ?? 0
        let leading = rect.minX - table.frame.minX
        let trailing = rect.maxX - table.frame.minX
        let target = leading < current || rect.width > table.frame.width ? leading - 10
            : trailing > current + table.frame.width ? trailing - table.frame.width + 10
            : current
        setTableOffset(target, for: table)
        tableViews[table.id]?.applyOffset(tableOffsets[table.id] ?? 0)
    }

    private func updateTables(refresh: Bool = false) {
        guard let rendered else { return }
        let visible = viewport.insetBy(dx: 0, dy: -viewport.height * 0.75)
        var retained: Set<Int> = []
        for table in rendered.tables where table.isScrollable && table.frame.intersects(visible) {
            retained.insert(table.id)
            if !refresh, tableViews[table.id] != nil { continue }
            setTableOffset(tableOffsets[table.id] ?? 0, for: table)
            let view = tableViews[table.id] ?? ReaderTableScrollView(frame: .zero)
            if view.superview == nil {
                view.owner = self
                tableViews[table.id] = view
                canvas.addSubview(view, positioned: .below, relativeTo: nil)
            }
            view.install(table, offset: tableOffsets[table.id] ?? 0)
        }
        for id in tableViews.keys.filter({ !retained.contains($0) && $0 != canvas.draggedTableID }) {
            tableViews.removeValue(forKey: id)?.removeFromSuperview()
        }
    }

    private func removeTableViews() {
        for view in tableViews.values { view.removeFromSuperview() }
        tableViews.removeAll()
    }

    private func setTableOffset(_ offset: CGFloat, for table: RenderedTable) {
        let clamped = min(max(0, table.contentWidth - table.frame.width), max(0, offset))
        if clamped == 0 { tableOffsets.removeValue(forKey: table.id) } else { tableOffsets[table.id] = clamped }
    }

    func tableOffsetChanged(_ offset: CGFloat, table: RenderedTable) {
        setTableOffset(offset, for: table)
        guard !adjusting else { return }
        find.finder.cancelFindIndicator()
        updateImages()
        canvas.invalidateLinkCursors()
    }

    func scrollVertically(with event: NSEvent) { scrollView.scrollWheel(with: event) }

    func scrollForDrag(to point: CGPoint) -> Bool {
        var moved = false
        let oldTop = viewport.minY
        let delta = Self.dragDelta(point.y, from: viewport.minY, to: viewport.maxY)
        if delta != 0 {
            scrollDirectly(top: min(max(0, canvas.bounds.height - viewport.height), oldTop + delta))
            moved = oldTop != viewport.minY
            if moved { viewportChanged() }
        }
        if let table = scrollableTable(near: point), let tableView = tableViews[table.id] {
            let delta = Self.dragDelta(point.x, from: table.frame.minX, to: table.frame.maxX)
            if delta != 0 {
                let old = tableOffsets[table.id] ?? 0
                tableView.applyOffset(min(max(0, old + delta), table.contentWidth - table.frame.width))
                moved = moved || (tableOffsets[table.id] ?? 0) != old
            }
        }
        return moved
    }

    private static func dragDelta(_ value: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        let margin: CGFloat = 16
        if value < start + margin { return -min(75, (start + margin - value) * 0.6) }
        if value > end - margin { return min(75, (value - end + margin) * 0.6) }
        return 0
    }

    func setHighlightsNeedDisplay() {
        canvas.setNeedsDisplay(viewport)
        for table in tableViews.values { table.tableCanvas.setNeedsDisplay(table.tableCanvas.visibleRect) }
    }

    func drawHighlights(in context: CGContext, dirtyRect: CGRect, table: RenderedTable? = nil) {
        guard let rendered else { return }
        let selection = find.selection ?? canvas.selection
        guard (selection?.length ?? 0) > 0 || !customFind.ranges.isEmpty else { return }
        let documentRect = table.map { dirtyRect.offsetBy(dx: $0.frame.minX, dy: $0.frame.minY) } ?? dirtyRect
        guard let visible = rendered.textRange(intersectingVerticalRange: documentRect.minY..<documentRect.maxY) else { return }
        let color = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.5).cgColor
        func paint(_ match: KasumiMarkdown.TextRange, color: CGColor) {
            guard match.lowerBound < visible.upperBound, match.upperBound > visible.lowerBound else { return }
            let clippedRange = KasumiMarkdown.TextRange(
                max(match.lowerBound, visible.lowerBound), min(match.upperBound, visible.upperBound))
            context.setFillColor(color)
            for rect in rendered.selectionRects(for: clippedRange) where rect.intersects(documentRect) {
                if let table {
                    context.fill(rect.offsetBy(dx: -table.frame.minX, dy: -table.frame.minY))
                } else if scrollableTable(atY: rect.midY) == nil {
                    context.fill(rect)
                }
            }
        }
        if let selection = find.selection ?? canvas.selection, let range = rendered.readerTextRange(for: selection) {
            paint(range, color: color)
        }
        guard let highlightIndex else { return }
        let normal = NSColor.systemYellow.withAlphaComponent(0.34).cgColor
        let current = NSColor.systemOrange.withAlphaComponent(0.55).cgColor
        for index in highlightIndex.candidates(in: rendered, verticalRange: documentRect.minY..<documentRect.maxY) {
            paint(customFind.ranges[index], color: index == customFind.currentIndex ? current : normal)
        }
    }

    package var readerViewportDiagnostics: ReaderViewportDiagnostics {
        let rect = viewport.intersection(CGRect(origin: .zero, size: rendered?.size ?? .zero))
        return ReaderViewportDiagnostics(
            documentSize: rendered?.size, viewport: rect, viewportHeight: viewport.height,
            isLayingOut: layoutTask != nil, installations: installations, layoutMilliseconds: layoutMilliseconds,
            idlePreparationMilliseconds: warmupMilliseconds, isFullyMeasured: rendered?.hasEstimatedGeometry == false,
            isViewportMeasured: rendered.map { !$0.needsLayout(in: rect) } ?? false,
            hasCurrentImageQueue: imageSnapshot === rendered && !visibleImages.isEmpty)
    }

    package func scrollReaderViewport(toY top: CGFloat) {
        userWillScroll()
        scrollDirectly(top: top)
        viewportChanged()
    }

    package func captureReaderViewport() -> NSBitmapImageRep? {
        let rect = viewport.intersection(canvas.bounds)
        guard !rect.isEmpty, let image = canvas.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        canvas.cacheDisplay(in: rect, to: image)
        return image
    }
}

package struct ReaderViewportDiagnostics {
    package let documentSize: CGSize?
    package let viewport: CGRect
    package let viewportHeight: CGFloat
    package let isLayingOut: Bool
    package let installations: Int
    package let layoutMilliseconds: Double?
    package let idlePreparationMilliseconds: Double?
    package let isFullyMeasured: Bool
    package let isViewportMeasured: Bool
    package let hasCurrentImageQueue: Bool
}
#endif
