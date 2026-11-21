#if os(macOS)
    import AppKit
    import KasumiMarkdown
    import KasumiMarkdownUI
    import UniformTypeIdentifiers

    @MainActor private final class LabRootView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }

    @MainActor final class LabController: NSViewController {
        let reader = MarkdownReaderView(frame: .zero)
        private let samples = NSPopUpButton()
        private let counts = NSPopUpButton()
        private let status = NSTextField(labelWithString: "Preparing…")
        private let details = NSTextField(labelWithString: "Native AppKit reader · Find off")
        private var loading: Task<Void, Never>?
        private var loadID = UUID()
        private var sourceURL: URL?

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
            reader.style = RenderStyle(fontSize: 18, widthLimit: nil)
            reader.readerPreparesForScrolling = ProcessInfo.processInfo.environment["KASUMI_REFLOW_IDLE_WARMUP"] != "0"
            reader.onOpenLink = { NSWorkspace.shared.open($0) }
            reader.onReaderLayout = { [weak self] in self?.updateStatus() }
            reader.onFindPresentationChange = { [weak self] _ in self?.updateStatus() }
            for child in [bar, reader, status, details] {
                child.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(child)
            }
            NSLayoutConstraint.activate([
                bar.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
                bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                bar.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
                reader.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 10),
                reader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                reader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                reader.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
                status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
                details.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 4),
                details.leadingAnchor.constraint(equalTo: status.leadingAnchor),
                details.trailingAnchor.constraint(equalTo: status.trailingAnchor),
                details.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
            ])
        }

        private func updateStatus() {
            let snapshot = reader.readerViewportDiagnostics
            if let size = snapshot.documentSize, let ms = snapshot.layoutMilliseconds {
                status.stringValue = String(
                    format: "%.0f pt × %.0f pt · %.2f ms layout + prepaint + install · snapshot %d",
                    size.width, snapshot.viewportHeight, ms, snapshot.installations)
            }
            let measurement = snapshot.isFullyMeasured ? "Entire document measured" : "Viewport reflow"
            details.stringValue = "Native AppKit reader · \(measurement) · Find \(reader.isFindPresented ? "on" : "off")"
        }

        @objc private func reloadSample() {
            sourceURL = nil
            reload()
        }
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
            loadID = UUID()
            let expected = loadID
            reader.isActive = false
            sourceURL = url
            view.window?.title =
                "Kasumi Reflow Lab — " + (url?.lastPathComponent ?? samples.titleOfSelectedItem ?? "Sample")
            status.stringValue = "Preparing \(url?.lastPathComponent ?? samples.titleOfSelectedItem ?? "sample")…"
            loading = Task { [weak self] in
                do {
                    let document = try await Task.detached(priority: .userInitiated) {
                        let source: String
                        if let markdown {
                            source = markdown
                        } else if let url {
                            source = try String(contentsOf: url, encoding: .utf8)
                        } else {
                            throw CocoaError(.fileNoSuchFile)
                        }
                        return MarkdownDocument(markdown: source, baseURL: url?.deletingLastPathComponent())
                    }.value
                    guard let self, !Task.isCancelled, self.loadID == expected else { return }
                    self.reader.setDocument(document, url: url)
                    self.reader.isActive = true
                } catch {
                    guard let self, self.loadID == expected else { return }
                    self.status.stringValue = "Could not open document: \(error.localizedDescription)"
                }
            }
        }

        func scrollingCheck(to output: URL, fast: Bool = false) async throws {
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            var rows: [[String: Any]] = []
            let stepPoints: CGFloat = fast ? 480 : 80
            let interval = fast ? 8 : 16
            for count in [50_000, 200_000] {
                load(markdown: LabSample.mixed.markdown(characters: count))
                for _ in 0..<1500 {
                    let snapshot = reader.readerViewportDiagnostics
                    if snapshot.documentSize != nil, !snapshot.isLayingOut, reader.isActive { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                let initial = reader.readerViewportDiagnostics
                guard let initialSize = initial.documentSize, reader.isActive else { throw CocoaError(.coderReadCorrupt) }
                let initialInstalls = initial.installations
                var uncovered = 0
                var samples = 0
                var missingSamples: [[String: Any]] = []
                var gapStart: ContinuousClock.Instant?
                var maximumGap: Double = 0
                func sample() {
                    samples += 1
                    let snapshot = reader.readerViewportDiagnostics
                    let viewport = snapshot.viewport
                    let missing = !snapshot.isViewportMeasured
                    if missing {
                        uncovered += 1
                        missingSamples.append([
                            "sample": samples, "top": viewport.minY, "installations": snapshot.installations - initialInstalls,
                            "snapshotWidth": snapshot.documentSize?.width ?? 0, "viewportWidth": viewport.width,
                            "fullyMeasured": snapshot.isFullyMeasured
                        ])
                        if gapStart == nil { gapStart = .now }
                        if fast, missingSamples.count == 1, let image = reader.captureReaderViewport() {
                            let path = output.deletingPathExtension().appendingPathExtension("\(count)-missing.png")
                            try? image.representation(using: .png, properties: [:])?.write(to: path)
                        }
                    } else if let start = gapStart {
                        let elapsed = start.duration(to: .now).components
                        maximumGap = max(
                            maximumGap, Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
                        gapStart = nil
                    }
                }
                if fast { try await Task.sleep(for: .seconds(3)) }
                // Drive the public AppKit reader while its detached work runs.
                // This samples coverage; it does not emulate trackpad inertia.
                let beforeTraversal = reader.readerViewportDiagnostics
                let fullyMeasuredAtStart = beforeTraversal.isFullyMeasured
                let documentHeight = beforeTraversal.documentSize?.height ?? initialSize.height
                let steps = fast ? Int(ceil(documentHeight / stepPoints)) : 100
                for step in (0..<steps).map({ $0 }) + (0..<steps).reversed().map({ $0 }) {
                    let top = min(max(0, documentHeight - beforeTraversal.viewportHeight), CGFloat(step) * stepPoints)
                    reader.scrollReaderViewport(toY: top)
                    sample()
                    try await Task.sleep(for: .milliseconds(interval))
                }
                for _ in 0..<1000 {
                    sample()
                    if !reader.readerViewportDiagnostics.isLayingOut { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                let final = reader.readerViewportDiagnostics
                let settled = final.isViewportMeasured
                rows.append([
                    "nominalCharacters": count, "samples": samples, "uncoveredSamples": uncovered,
                    "fullyMeasuredBeforeTraversal": fullyMeasuredAtStart,
                    "idlePreparationMs": final.idlePreparationMilliseconds ?? -1,
                    "maximumCoverageGapMs": maximumGap, "installations": final.installations - initialInstalls,
                    "settledViewportMeasured": settled, "missingSamples": missingSamples
                ])
                guard settled, final.installations > initialInstalls else { throw CocoaError(.coderReadCorrupt) }
            }
            let result: [String: Any] = [
                "schema": 1, "processMemory": try BenchmarkMemory.read(),
                "hostState": [
                    "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
                    "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled
                ], "stepPoints": stepPoints, "requestedStepIntervalMs": interval,
                "idleBeforeTraversalSeconds": fast ? 3 : 0,
                "notes":
                    "Offscreen public AppKit reader and real asynchronous layout/prepaint/publication. Coverage metadata sampled after each step; not FPS or pixel evidence for every displayed frame.",
                "results": rows
            ]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }

        func smokeCheck(to output: URL) async throws {
            counts.selectItem(at: 0)
            load(markdown: LabSample.chinese.markdown(characters: 10000))
            let initial = try await waitForLayout()
            guard let size = initial.documentSize else { throw CocoaError(.coderReadCorrupt) }
            let target = min(size.height - initial.viewportHeight, size.height * 0.45)
            reader.scrollReaderViewport(toY: target)
            for _ in 0..<1000 {
                if !reader.readerViewportDiagnostics.isLayingOut { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let current = reader.readerViewportDiagnostics
            let covered = current.isViewportMeasured
            let bitmap = reader.captureReaderViewport()
            var result: [String: Any] = [
                "initialWidth": size.width, "scrollTop": current.viewport.minY, "installations": current.installations,
                "viewportMeasured": covered, "bitmapCreated": bitmap != nil
            ]
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let capture = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: capture)
                try capture.representation(using: .png, properties: [:])?.write(
                    to: output.deletingPathExtension().appendingPathExtension("png"))
            }
            guard covered, bitmap != nil, current.viewport.minY > 0, current.installations >= 2 else {
                throw CocoaError(.coderReadCorrupt)
            }
            try await checkProgrammaticFind()
            result["programmaticFindNavigated"] = true

            if ProcessInfo.processInfo.environment["KASUMI_REFLOW_IDLE_WARMUP"] != "0" {
                let svg =
                    #"<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"><rect width="80" height="40" fill="red"/></svg>"#
                let image = Data(svg.utf8).base64EncodedString()
                load(
                    markdown: "![Sample](data:image/svg+xml;base64,\(image))\n\n"
                        + LabSample.chinese.markdown(characters: 10000))
                for _ in 0..<1000 {
                    let snapshot = reader.readerViewportDiagnostics
                    if reader.isActive, snapshot.idlePreparationMilliseconds != nil { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                let snapshot = reader.readerViewportDiagnostics
                guard reader.isActive, snapshot.idlePreparationMilliseconds != nil, snapshot.isFullyMeasured,
                    snapshot.hasCurrentImageQueue
                else {
                    throw CocoaError(
                        .coderReadCorrupt,
                        userInfo: [
                            NSDebugDescriptionErrorKey: "Idle layout did not refresh the visible-image queue"
                        ])
                }
                result["idleImageQueueRefreshed"] = true
            }
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        }

        private func waitForLayout() async throws -> ReaderViewportDiagnostics {
            for _ in 0..<1000 {
                let snapshot = reader.readerViewportDiagnostics
                if reader.isActive, snapshot.documentSize != nil, !snapshot.isLayingOut { return snapshot }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw CocoaError(.coderReadCorrupt)
        }

        private func checkProgrammaticFind() async throws {
            var result: FindResult?
            reader.onFindResultChange = { result = $0 }
            defer { reader.clearFind(); reader.onFindResultChange = nil }
            reader.setFindQuery("Paragraph ")
            guard result?.count == 20, result?.currentIndex == 0 else { throw CocoaError(.coderReadCorrupt) }
            let first = try await waitForLayout().viewport.minY
            reader.moveToFindMatch(.next)
            guard result?.currentIndex == 1 else { throw CocoaError(.coderReadCorrupt) }
            reader.moveToFindMatch(.previous)
            reader.moveToFindMatch(.previous)
            guard result?.currentIndex == 19 else { throw CocoaError(.coderReadCorrupt) }
            let last = try await waitForLayout().viewport.minY
            guard last > first else { throw CocoaError(.coderReadCorrupt) }
        }

        func interactionCheck(to output: URL) async throws {
            load(markdown: LabSample.chinese.markdown(characters: 10_000))
            _ = try await waitForLayout()
            try await checkProgrammaticFind()
            var events: [Bool] = []
            var result: FindResult?
            reader.onFindPresentationChange = { events.append($0) }
            reader.onFindResultChange = { result = $0 }
            defer { reader.onFindPresentationChange = nil; reader.onFindResultChange = nil }
            reader.setFindQuery("Paragraph ")
            guard result?.count == 20, reader.presentFind(), reader.isFindPresented, result?.count == 0 else {
                throw CocoaError(.coderReadCorrupt)
            }
            reader.dismissFind()
            guard !reader.isFindPresented, events == [true, false] else { throw CocoaError(.coderReadCorrupt) }
            guard reader.presentFind(), reader.isFindPresented else { throw CocoaError(.coderReadCorrupt) }
            reader.setFindQuery("Paragraph ")
            guard !reader.isFindPresented, events == [true, false, true, false], result?.count == 20 else {
                throw CocoaError(.coderReadCorrupt)
            }
            let record: [String: Any] = ["nativeFindVisibility": events, "programmaticFindNavigated": true]
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: output)
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
            appMenu.addItem(
                withTitle: "Quit Reflow Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.submenu = appMenu
            let edit = NSMenu(title: "Edit")
            edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            edit.addItem(withTitle: "Select All", action: #selector(NSStandardKeyBindingResponding.selectAll(_:)), keyEquivalent: "a")
            edit.addItem(.separator())
            let findItems: [(String, String, NSTextFinder.Action)] = [
                ("Find…", "f", .showFindInterface), ("Find Next", "g", .nextMatch),
                ("Find Previous", "G", .previousMatch)
            ]
            for (title, key, action) in findItems {
                let item = edit.addItem(
                    withTitle: title, action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: key)
                item.tag = action.rawValue
            }
            let editItem = NSMenuItem()
            editItem.submenu = edit
            menu.addItem(editItem)
            NSApp.mainMenu = menu
            let args = CommandLine.arguments.dropFirst()
            let controller = LabController()
            self.controller = controller
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 900, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            self.window = window
            window.title = "Kasumi Reflow Lab"
            window.minSize = CGSize(width: 480, height: 320)
            window.contentViewController = controller
            window.initialFirstResponder = controller.reader
            window.appearance = NSAppearance(named: .aqua)
            window.setContentSize(CGSize(width: 900, height: 800))
            window.center()
            window.layoutIfNeeded()
            controller.view.layoutSubtreeIfNeeded()
            if args.first == "--interaction-check", let path = args.dropFirst().first {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                Task {
                    do {
                        try await controller.interactionCheck(to: URL(fileURLWithPath: path))
                        NSApp.terminate(nil)
                    } catch {
                        fputs("Reflow Lab interaction check failed: \(error)\n", stderr)
                        exit(1)
                    }
                }
                return
            }
            if args.first == "--smoke-check" || args.first == "--scroll-check" || args.first == "--fast-scroll-check",
                let path = args.dropFirst().first
            {
                Task {
                    do {
                        if args.first == "--scroll-check" || args.first == "--fast-scroll-check" {
                            try await controller.scrollingCheck(
                                to: URL(fileURLWithPath: path), fast: args.first == "--fast-scroll-check")
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
                if let path = args.first {
                    controller.load(markdown: nil, url: URL(fileURLWithPath: path))
                } else {
                    controller.load(markdown: LabSample.chinese.markdown(characters: 50000))
                }
            }
        }
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    }

    let app = NSApplication.shared
    app.setActivationPolicy(
        CommandLine.arguments.contains("--smoke-check") || CommandLine.arguments.contains("--scroll-check")
            || CommandLine.arguments.contains("--fast-scroll-check") ? .prohibited : .regular)
    let delegate = LabDelegate()
    app.delegate = delegate
    app.run()
#else
    import Foundation
    fputs("KasumiReflowLab requires macOS.\n", stderr)
#endif
