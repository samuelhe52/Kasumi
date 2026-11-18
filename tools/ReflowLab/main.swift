#if os(macOS)
import AppKit
import KasumiMarkdown
import UniformTypeIdentifiers
import os

@MainActor private final class LabRootView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

@MainActor final class LabController: NSViewController {
    let scroll = NSScrollView()
    let canvas = LabCanvas()
    private let samples = NSPopUpButton()
    private let counts = NSPopUpButton()
    private let status = NSTextField(labelWithString: "Preparing…")
    private let details = NSTextField(labelWithString: "Shared reflow engine · Native Mac harness · Find off")
    private var session: DocumentReflowSession?
    private var rendered: RenderedDocument?
    private var state = ReaderReflowState()
    private var anchor = ReaderReflowAnchorState()
    private var revision = UUID()
    private var task: Task<Void, Never>?
    private var loading: Task<Void, Never>?
    private var imageTask: Task<Void, Never>?
    private var imageDecode: (region: ReaderImageRegion, worker: Task<Bool, Never>)?
    private weak var imageSnapshot: RenderedDocument?
    private var visibleImages: [ReaderImageRegion] = []
    private var pendingImages: ArraySlice<ReaderImageRegion> = []
    private var warmup: Task<Void, Never>?
    private var warmupID = UUID()
    private var warmupMilliseconds: Double?
    private var adjusting = false
    private var sourceURL: URL?
    private var installedHeight: CGFloat = 0
    private var installations = 0
    private let signposter = OSSignposter(subsystem: "com.samuelhe.Kasumi.ReflowLab", category: "Reflow")

    override func loadView() {
        view = LabRootView()
        samples.addItems(withTitles: LabSample.allCases.map(\.rawValue))
        counts.addItems(withTitles: ["10,000", "50,000", "200,000"])
        counts.selectItem(at: 1)
        samples.target = self
        samples.action = #selector(reloadSample)
        counts.target = self
        counts.action = #selector(reloadSample)
        let reload = NSButton(title: "Reload", target: self, action: #selector(reload))
        let open = NSButton(title: "Open…", target: self, action: #selector(openFile))
        let bar = NSStackView(views: [samples, counts, reload, open])
        bar.orientation = .horizontal
        bar.spacing = 10
        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        status.lineBreakMode = .byTruncatingTail
        details.font = .systemFont(ofSize: 11)
        details.textColor = .secondaryLabelColor
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.documentView = canvas
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        for child in [bar, scroll, status, details] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            details.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 4),
            details.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            details.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            details.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        request()
    }

    @objc private func reloadSample() { sourceURL = nil; reload() }
    @objc private func reload() {
        let sample = LabSample.allCases[samples.indexOfSelectedItem]
        let count = [10000, 50000, 200000][counts.indexOfSelectedItem]
        load(markdown: sourceURL == nil ? sample.markdown(characters: count) : nil, url: sourceURL)
    }
    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.load(markdown: nil, url: url)
        }
    }

    func load(markdown: String?, url: URL? = nil) {
        _ = view
        loading?.cancel()
        imageDecode?.worker.cancel()
        imageSnapshot = nil
        visibleImages = []
        pendingImages = []
        cancelWarmup()
        warmupMilliseconds = nil
        details.stringValue = "Shared reflow engine · Native Mac harness · Find off"
        state.stop()
        revision = UUID()
        let expected = revision
        session = nil
        rendered = nil
        anchor = ReaderReflowAnchorState()
        sourceURL = url
        view.window?.title = "Kasumi Reflow Lab — " + (url?.lastPathComponent ?? samples.titleOfSelectedItem ?? "Sample")
        canvas.rendered = nil
        canvas.preview = nil
        canvas.needsDisplay = true
        status.stringValue = "Preparing \(url?.lastPathComponent ?? samples.titleOfSelectedItem ?? "sample")…"
        loading = Task { [weak self] in
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    let source: String
                    if let markdown { source = markdown }
                    else if let url { source = try String(contentsOf: url, encoding: .utf8) }
                    else { throw CocoaError(.fileNoSuchFile) }
                    return MarkdownDocument(markdown: source, baseURL: url?.deletingLastPathComponent())
                }.value
                guard let self, !Task.isCancelled, self.revision == expected else { return }
                self.session = DocumentReflowSession(
                    document, style: RenderStyle(fontSize: 18, widthLimit: nil),
                    readerDisplayScale: self.view.window?.backingScaleFactor ?? 2,
                    preparesLocalImageLayout: true)
                self.request()
            } catch {
                guard let self, self.revision == expected else { return }
                self.status.stringValue = "Could not open document: \(error.localizedDescription)"
            }
        }
    }

    @objc private func scrolled() {
        guard !adjusting else { return }
        cancelWarmup()
        anchor.moved(in: rendered, atY: max(0, scroll.contentView.bounds.minY))
        request()
        scheduleWarmup()
    }

    private func request() {
        guard session != nil else { return }
        let viewport = scroll.contentView.bounds
        guard viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0 else { return }
        updateImages(in: viewport)
        if rendered?.size.width != viewport.width {
            cancelWarmup()
            warmupMilliseconds = nil
            details.stringValue = "Shared reflow engine · Native Mac harness · Find off"
        }
        let visible = viewport.insetBy(dx: 0, dy: -viewport.height * 0.75)
        if let rendered, rendered.size.width == viewport.width, installedHeight == viewport.height,
            !rendered.needsLayout(in: visible), let installed = state.installed
        {
            state.request(width: installed.width, generation: installed.generation, anchor: installed.anchor, height: installed.height)
        } else {
            anchor.captureIfNeeded(in: rendered, atY: max(0, viewport.minY), restoring: nil)
            state.request(width: viewport.width, generation: revision, anchor: anchor.value, height: viewport.height)
        }
        guard task == nil, state.needsLayout else { return }
        task = Task { [weak self] in
            while let self, let request = self.state.begin(), let session = self.session {
                let begin = ContinuousClock.now
                let interval = self.signposter.beginInterval("Layout", id: self.signposter.makeSignpostID())
                let next = await session.render(width: request.width, viewportHeight: request.height, anchor: request.anchor)
                self.signposter.endInterval("Layout", interval)
                let top = max(0, min(max(0, next.size.height - request.height), self.anchor.value.flatMap { next.y(for: $0) } ?? 0))
                let rect = CGRect(x: 0, y: top, width: request.width, height: request.height)
                    .intersection(CGRect(origin: .zero, size: next.size))
                guard self.state.accepts(request, coversDesiredViewport: !next.needsLayout(in: rect)) else {
                    _ = self.state.complete(request)
                    continue
                }
                let scale = self.view.window?.backingScaleFactor ?? 2
                let paintInterval = self.signposter.beginInterval("ViewportPaint", id: self.signposter.makeSignpostID())
                let preview = await Task.detached(priority: .userInitiated) { LabPreview.paint(next, rect: rect, scale: scale) }.value
                self.signposter.endInterval("ViewportPaint", paintInterval)
                let liveTop = max(0, min(max(0, next.size.height - request.height), self.anchor.value.flatMap { next.y(for: $0) } ?? top))
                let liveRect = CGRect(x: 0, y: liveTop, width: request.width, height: request.height)
                    .intersection(CGRect(origin: .zero, size: next.size))
                if self.state.complete(request, coversDesiredViewport: !next.needsLayout(in: liveRect)) {
                    let install = self.signposter.beginInterval("Install", id: self.signposter.makeSignpostID())
                    self.adjusting = true
                    self.rendered = next
                    self.canvas.rendered = next
                    self.canvas.preview = preview
                    self.canvas.frame = CGRect(x: 0, y: 0, width: request.width, height: max(request.height, next.size.height))
                    self.scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, min(max(0, next.size.height - self.scroll.contentView.bounds.height), liveTop))))
                    self.scroll.reflectScrolledClipView(self.scroll.contentView)
                    self.anchor.didInstall(next, revision: self.revision, atY: self.scroll.contentView.bounds.minY)
                    self.installedHeight = request.height
                    self.canvas.needsDisplay = true
                    self.installations += 1
                    self.adjusting = false
                    self.updateImages(in: self.scroll.contentView.bounds)
                    self.signposter.endInterval("Install", install)
                    let elapsed = begin.duration(to: .now).components
                    let ms = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                    self.status.stringValue = String(format: "%.0f pt × %.0f pt · %.2f ms layout + prepaint + install · snapshot %d", request.width, request.height, ms, self.installations)
                }
            }
            self?.task = nil
            // A document may have changed while the old synchronous render drained.
            if self?.session != nil, self?.state.needsLayout == true { self?.request() }
            else { self?.scheduleWarmup() }
        }
    }

    private func updateImages(in viewport: CGRect) {
        guard let rendered, rendered.hasReaderImages else { return }
        let regions = rendered.readerImageRegions(in: viewport)
        let sameSnapshot = imageSnapshot === rendered
        guard !sameSnapshot || visibleImages != regions else { return }
        let previous = sameSnapshot ? visibleImages : []
        imageSnapshot = rendered
        visibleImages = regions
        if let imageDecode, !regions.contains(where: { $0.sharesRaster(with: imageDecode.region) }) {
            imageDecode.worker.cancel()
        }
        pendingImages = regions.filter { region in
            if !rendered.hasReaderImageResult(for: region) { return true }
            if !previous.contains(region) { canvas.invalidateImage(in: region.rect) }
            return false
        }[...]
        guard imageTask == nil, !pendingImages.isEmpty else { return }
        imageTask = Task { [weak self] in
            while let snapshot = self?.imageSnapshot, let region = self?.pendingImages.popFirst() {
                let worker = Task.detached(priority: .userInitiated) {
                    await snapshot.prepareReaderImage(region)
                }
                self?.imageDecode = (region, worker)
                let changed = await worker.value
                self?.imageDecode = nil
                if changed, let self {
                    for visible in self.visibleImages where visible.sharesRaster(with: region) {
                        self.canvas.invalidateImage(in: visible.rect)
                    }
                }
            }
            self?.imageTask = nil
        }
    }

    private func cancelWarmup() {
        warmupID = UUID()
        warmup?.cancel()
        warmup = nil
    }

    private func scheduleWarmup() {
        guard ProcessInfo.processInfo.environment["KASUMI_REFLOW_IDLE_WARMUP"] != "0",
            warmup == nil, rendered?.hasEstimatedGeometry == true, let session else { return }
        let expected = revision
        let width = scroll.contentView.bounds.width
        let id = UUID()
        warmupID = id
        warmup = Task(priority: .utility) { [weak self] in
            defer { if self?.warmupID == id { self?.warmup = nil } }
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard let self, self.revision == expected, self.task == nil,
                    self.scroll.contentView.bounds.width == width else { return }
                let start = ContinuousClock.now
                guard let full = try await session.prepareForScrolling(width: width) else { return }
                try Task.checkCancellation()
                let top = max(0, min(max(0, full.size.height - self.scroll.contentView.bounds.height),
                    self.anchor.value.flatMap { full.y(for: $0) } ?? 0))
                let rect = CGRect(x: 0, y: top, width: width, height: self.scroll.contentView.bounds.height)
                    .intersection(CGRect(origin: .zero, size: full.size))
                let scale = self.view.window?.backingScaleFactor ?? 2
                let preview = await Task.detached(priority: .utility) { LabPreview.paint(full, rect: rect, scale: scale) }.value
                try Task.checkCancellation()
                guard self.revision == expected, self.task == nil, !self.state.needsLayout,
                    self.scroll.contentView.bounds.width == width else { return }
                self.adjusting = true
                self.rendered = full
                self.canvas.rendered = full
                self.canvas.preview = preview
                self.canvas.frame = CGRect(x: 0, y: 0, width: width,
                    height: max(self.scroll.contentView.bounds.height, full.size.height))
                self.scroll.contentView.scroll(to: CGPoint(x: 0, y: top))
                self.scroll.reflectScrolledClipView(self.scroll.contentView)
                self.canvas.needsDisplay = true
                self.installations += 1
                self.adjusting = false
                self.updateImages(in: self.scroll.contentView.bounds)
                let elapsed = start.duration(to: .now).components
                self.warmupMilliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                self.details.stringValue = "Shared reflow engine · Entire document measured · Find off"
            } catch is CancellationError {} catch { self?.details.stringValue = "Idle preparation failed: \(error)" }
        }
    }

    func scrollingCheck(to output: URL, fast: Bool = false) async throws {
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        var rows: [[String: Any]] = []
        let stepPoints: CGFloat = fast ? 480 : 80
        let interval = fast ? 8 : 16
        for count in [50_000, 200_000] {
            load(markdown: LabSample.mixed.markdown(characters: count))
            for _ in 0..<1500 {
                if rendered != nil, task == nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard let initial = rendered else { throw CocoaError(.coderReadCorrupt) }
            let initialInstalls = installations
            var uncovered = 0
            var samples = 0
            var missingSamples: [[String: Any]] = []
            var gapStart: ContinuousClock.Instant?
            var maximumGap: Double = 0
            func sample() {
                samples += 1
                let viewport = scroll.contentView.bounds
                    .intersection(CGRect(origin: .zero, size: rendered?.size ?? .zero))
                let missing = rendered?.needsLayout(in: viewport) ?? true
                if missing {
                    uncovered += 1
                    missingSamples.append(["sample": samples, "top": viewport.minY, "installations": installations - initialInstalls,
                        "snapshotWidth": rendered?.size.width ?? 0, "viewportWidth": viewport.width,
                        "fullyMeasured": rendered?.hasEstimatedGeometry == false])
                    if gapStart == nil { gapStart = .now }
                    if fast, missingSamples.count == 1, let rendered,
                        let capture = LabPreview.paint(rendered, rect: viewport, scale: 1) {
                        let image = NSBitmapImageRep(cgImage: capture.image)
                        let path = output.deletingPathExtension().appendingPathExtension("\(count)-missing.png")
                        try? image.representation(using: .png, properties: [:])?.write(to: path)
                    }
                } else if let start = gapStart {
                    let elapsed = start.duration(to: .now).components
                    maximumGap = max(maximumGap, Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
                    gapStart = nil
                }
            }
            if fast { try await Task.sleep(for: .seconds(3)) }
            // Drive the real AppKit controller/scheduler while its detached work
            // runs. This samples coverage; it does not emulate trackpad inertia.
            let fullyMeasuredAtStart = rendered?.hasEstimatedGeometry == false
            let documentHeight = rendered?.size.height ?? initial.size.height
            let steps = fast ? Int(ceil(documentHeight / stepPoints)) : 100
            for step in (0..<steps).map({ $0 }) + (0..<steps).reversed().map({ $0 }) {
                let top = min(max(0, documentHeight - scroll.contentView.bounds.height), CGFloat(step) * stepPoints)
                scroll.contentView.scroll(to: CGPoint(x: 0, y: top))
                scroll.reflectScrolledClipView(scroll.contentView)
                scrolled()
                sample()
                try await Task.sleep(for: .milliseconds(interval))
            }
            for _ in 0..<1000 {
                sample()
                if task == nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let viewport = scroll.contentView.bounds
                .intersection(CGRect(origin: .zero, size: rendered?.size ?? .zero))
            let settled = rendered.map { !$0.needsLayout(in: viewport) } ?? false
            rows.append([
                "nominalCharacters": count, "samples": samples, "uncoveredSamples": uncovered,
                "fullyMeasuredBeforeTraversal": fullyMeasuredAtStart, "idlePreparationMs": warmupMilliseconds ?? -1,
                "maximumCoverageGapMs": maximumGap, "installations": installations - initialInstalls,
                "settledViewportMeasured": settled, "missingSamples": missingSamples
            ])
            guard settled, installations > initialInstalls else { throw CocoaError(.coderReadCorrupt) }
        }
        let result: [String: Any] = [
            "schema": 1, "processMemory": try BenchmarkMemory.read(), "hostState": ["thermalState": ProcessInfo.processInfo.thermalState.rawValue, "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled], "stepPoints": stepPoints, "requestedStepIntervalMs": interval, "idleBeforeTraversalSeconds": fast ? 3 : 0,
            "notes": "Offscreen AppKit scroll controller and real asynchronous layout/prepaint/publication. Coverage metadata sampled after each step; not FPS or pixel evidence for every displayed frame.",
            "results": rows
        ]
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }

    func smokeCheck(to output: URL) async throws {
        counts.selectItem(at: 0)
        load(markdown: LabSample.chinese.markdown(characters: 10000))
        for _ in 0..<1000 {
            if rendered != nil, task == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let initial = rendered else { throw CocoaError(.coderReadCorrupt) }
        let initialWidth = initial.size.width
        let target = min(initial.size.height - scroll.contentView.bounds.height, initial.size.height * 0.45)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: target))
        scroll.reflectScrolledClipView(scroll.contentView)
        scrolled()
        for _ in 0..<1000 {
            if task == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let current = rendered else { throw CocoaError(.coderReadCorrupt) }
        let viewport = scroll.contentView.bounds.intersection(CGRect(origin: .zero, size: current.size))
        let covered = !current.needsLayout(in: viewport)
        let bitmap = LabPreview.paint(current, rect: viewport, scale: 1)
        var result: [String: Any] = [
            "initialWidth": initialWidth, "scrollTop": viewport.minY, "installations": installations,
            "viewportMeasured": covered, "bitmapCreated": bitmap != nil
        ]
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let capture = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: capture)
            try capture.representation(using: .png, properties: [:])?.write(to: output.deletingPathExtension().appendingPathExtension("png"))
        }
        guard covered, bitmap != nil, viewport.minY > 0, installations >= 2 else { throw CocoaError(.coderReadCorrupt) }

        if ProcessInfo.processInfo.environment["KASUMI_REFLOW_IDLE_WARMUP"] != "0" {
            let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"><rect width="80" height="40" fill="red"/></svg>"#
            let image = Data(svg.utf8).base64EncodedString()
            load(markdown: "![Sample](data:image/svg+xml;base64,\(image))\n\n"
                + LabSample.chinese.markdown(characters: 10000))
            for _ in 0..<1000 {
                if warmupMilliseconds != nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard warmupMilliseconds != nil, let rendered, !rendered.hasEstimatedGeometry,
                imageSnapshot === rendered, !visibleImages.isEmpty
            else {
                throw CocoaError(.coderReadCorrupt, userInfo: [
                    NSDebugDescriptionErrorKey: "Idle layout did not refresh the visible-image queue"
                ])
            }
            result["idleImageQueueRefreshed"] = true
        }
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }
}

@MainActor final class LabDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: LabController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Reflow Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        NSApp.mainMenu = menu
        let args = CommandLine.arguments.dropFirst()
        let controller = LabController()
        self.controller = controller
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        self.window = window
        window.title = "Kasumi Reflow Lab"
        window.minSize = CGSize(width: 480, height: 320)
        window.contentViewController = controller
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(CGSize(width: 900, height: 800))
        window.center()
        window.layoutIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        if (args.first == "--smoke-check" || args.first == "--scroll-check" || args.first == "--fast-scroll-check"), let path = args.dropFirst().first {
            Task {
                do {
                    if args.first == "--scroll-check" || args.first == "--fast-scroll-check" {
                        try await controller.scrollingCheck(to: URL(fileURLWithPath: path), fast: args.first == "--fast-scroll-check")
                    } else {
                        try await controller.smokeCheck(to: URL(fileURLWithPath: path))
                    }
                    NSApp.terminate(nil)
                } catch {
                    fputs("Reflow Lab smoke check failed: \(error)\n", stderr)
                    exit(1)
                }
            }
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let path = args.first { controller.load(markdown: nil, url: URL(fileURLWithPath: path)) }
            else { controller.load(markdown: LabSample.chinese.markdown(characters: 50000)) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(CommandLine.arguments.contains("--smoke-check") || CommandLine.arguments.contains("--scroll-check") || CommandLine.arguments.contains("--fast-scroll-check") ? .prohibited : .regular)
let delegate = LabDelegate()
app.delegate = delegate
app.run()
#else
import Foundation
fputs("KasumiReflowLab requires macOS.\n", stderr)
#endif
