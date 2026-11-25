#if os(macOS)
import AppKit
import KasumiMarkdown
import Testing

@testable import KasumiMarkdownUI

@MainActor @Suite(.serialized) struct MarkdownReaderAppKitTests {
    @Test(arguments: [true, false])
    func widthChangesReflowInTheSameLayoutPassOrKeepTheCanvasAligned(inTime: Bool) async throws {
        let (reader, window) = try await reader(
            markdown: "# A heading\n\nA short paragraph.", size: CGSize(width: 360, height: 300))
        defer { window.contentView = nil }
        reader.resizeLayoutBudget = inTime ? .seconds(10) : .zero
        let initial = try #require(reader.rendered)

        for width: CGFloat in [520, 300] {
            let before = reader.rendered
            resize(reader, in: window, to: CGSize(width: width, height: 300))
            #expect(reader.viewport.width == width)
            #expect(reader.canvas.frame.width == width)
            if inTime {
                #expect(reader.rendered?.size.width == width)
            } else {
                #expect(reader.rendered === before)
                #expect(await eventually { reader.rendered?.size.width == width })
            }
        }
        #expect(await eventually { !reader.readerViewportDiagnostics.isLayingOut })
        #expect(reader.rendered !== initial)
    }

    @Test func heightChangesReturnToTheReadingPlace() async throws {
        let markdown = (0..<40).map { "Paragraph \($0) with some text." }.joined(separator: "\n\n")
        let (reader, window) = try await reader(markdown: markdown, size: CGSize(width: 360, height: 300))
        defer { window.contentView = nil }
        let initial = try #require(reader.rendered)
        let bottom = initial.size.height - 300
        reader.scrollReaderViewport(toY: bottom)
        try #require(await eventually { !reader.readerViewportDiagnostics.isLayingOut })
        let place = reader.viewport.minY

        resize(reader, in: window, to: CGSize(width: 360, height: 500))
        #expect(abs(reader.viewport.minY - (initial.size.height - 500)) < 1)
        resize(reader, in: window, to: CGSize(width: 360, height: 300))
        #expect(await eventually { abs(reader.viewport.minY - place) < 1 })
    }

    private func reader(markdown: String, size: CGSize) async throws -> (MarkdownReaderView, NSWindow) {
        _ = NSApplication.shared
        let frame = CGRect(origin: .zero, size: size)
        let reader = MarkdownReaderView(frame: frame)
        reader.readerPreparesForScrolling = false
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = reader
        try #require(reader.canvas.enclosingScrollView).scrollerStyle = .overlay
        reader.setDocument(MarkdownDocument(markdown: markdown))
        try #require(
            await eventually {
                reader.rendered?.size.width == size.width && !reader.readerViewportDiagnostics.isLayingOut
            })
        return (reader, window)
    }

    private func resize(_ reader: MarkdownReaderView, in window: NSWindow, to size: CGSize) {
        window.setContentSize(size)
        reader.layoutSubtreeIfNeeded()
    }

    @Test func routesOnlyCurrentDocumentFragmentsInternally() throws {
        let reader = MarkdownReaderView(frame: .zero)
        let file = try #require(URL(string: "file:///tmp/notes.md"))
        reader.setDocument(MarkdownDocument(markdown: "# Intro"), url: file)
        var opened: [URL] = []
        reader.onOpenLink = { opened.append($0) }

        for target in ["#intro", "file://localhost/tmp/./notes.md#intro"] {
            reader.activateLink(try #require(URL(string: target)))
        }
        let external = try ["chapter.md#intro", "?view=other#intro", "file://other-host/tmp/notes.md#intro",
                            "file:///tmp/notes.md?view=other#intro"].map { try #require(URL(string: $0)) }
        for target in external { reader.activateLink(target) }
        #expect(opened == external)
    }

    @Test(arguments: [false, true])
    func selectionPaintsBelowColoredGlyphsOnThePageAndInScrollableTables(dark: Bool) async throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 350, height: 320)
        let reader = MarkdownReaderView(frame: frame)
        reader.readerPreparesForScrolling = false
        reader.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let text = try #require(DocumentColor(hex: dark ? "#E8D29D" : "#3B214A"))
        let paper = try #require(DocumentColor(hex: dark ? "#202720" : "#FEF8E8"))
        let theme = DocumentTheme(
            id: "selection-test", name: "Selection Test", appearance: dark ? .dark : .light,
            document: ["text": text, "heading": text, "paper": paper])
        reader.style = RenderStyle(theme: theme, fontSize: 32, insets: .zero)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = reader
        reader.setDocument(MarkdownDocument(markdown: """
            MMMM

            | HHHH | A very long column | Larger column |
            |---|---|---|
            | A | A very long description | Another long description |
            """))
        try #require(await eventually { reader.rendered?.tables.first?.isScrollable == true })
        let rendered = try #require(reader.rendered)
        let table = try #require(rendered.tables.first)
        window.contentView = nil
        for (token, table) in [("MMMM", nil), ("HHHH", table as RenderedTable?)] {
            reader.canvas.setSelection(reader.canvas.semanticString.range(of: token))
            let offset = table?.frame.origin ?? .zero
            let area = table.map { CGRect(x: 0, y: 0, width: $0.contentWidth, height: $0.frame.height) } ?? frame
            let highlights = reader.highlights(in: area, table: table)
            let highlight = try #require(highlights.first)
            #expect(highlight.color.alpha == 1)
            let rect = try #require(highlight.rects.first)
                .offsetBy(dx: -offset.x, dy: -offset.y).insetBy(dx: 2, dy: 2).integral
            let plain = try pixelsInReaderRect(rect) { context in
                if let table { rendered.drawTable(at: table.id, in: context, rect: rect) }
                else { rendered.draw(in: context, rect: rect) }
            }
            let selected = try pixelsInReaderRect(rect) { context in
                if let table { rendered.drawTable(at: table.id, in: context, rect: rect, highlights: highlights) }
                else { rendered.draw(in: context, rect: rect, excludingScrollableTables: true, highlights: highlights) }
            }
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let color = try #require(
                highlight.color.converted(to: space, intent: .defaultIntent, options: nil)?.components)
            let expected = color.prefix(3).map { Int(($0 * 255).rounded()) }
            let rgb = [text.red, text.green, text.blue].map { Int(($0 * 255).rounded()) }
            func equals(_ image: [UInt8], at i: Int, _ color: [Int]) -> Bool {
                (0..<3).allSatisfy { abs(Int(image[i + $0]) - color[$0]) <= 1 }
            }
            let indices = stride(from: 0, to: plain.count, by: 4)
            #expect(indices.filter { equals(selected, at: $0, expected) }.count > 30)
            #expect(indices.filter { equals(plain, at: $0, rgb) && equals(selected, at: $0, rgb) }.count > 20)
        }
    }

    private func pixelsInReaderRect(_ rect: CGRect, draw: (CGContext) -> Void) throws -> [UInt8] {
        let width = Int(rect.width)
        let height = Int(rect.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -rect.minX, y: -rect.minY)
            draw(context)
        }
        return pixels
    }

    @Test(arguments: [false, true]) func queuedFindSurvivesSuspensionUnlessDismissed(dismiss: Bool) async throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 360, height: 300)
        let reader = MarkdownReaderView(frame: frame)
        reader.setDocument(MarkdownDocument(markdown: "# Notes\n\nFind me."))
        try #require(reader.presentFind())
        #expect(!reader.isFindPresented)
        reader.isActive = false
        if dismiss { reader.dismissFind() }

        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = reader
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        var installed = false
        reader.onPositionChange = { _, _ in installed = true }
        reader.isActive = true
        for _ in 0..<300 where !installed {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try #require(installed)
        #expect(reader.isFindPresented == !dismiss)
        reader.dismissFind()
        #expect(!reader.isFindPresented)
    }

    @Test func visibleEmbeddedImageFinishesWhileRemoteProviderIsSuspended() async throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 360, height: 300)
        let reader = MarkdownReaderView(frame: frame)
        reader.readerPreparesForScrolling = false
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = reader
        window.makeKeyAndOrderFront(nil)
        let gate = ImageGate()
        defer {
            window.orderOut(nil)
            gate.release()
        }
        reader.setRemoteImages(MarkdownRemoteImages { _ in await gate.suspend(); return nil })
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><rect width="40" height="40" fill="red"/></svg>"#
        let image = Data(svg.utf8).base64EncodedString()
        reader.setDocument(MarkdownDocument(markdown: """
            <img src="https://example.invalid/slow" alt="Slow" width="40" height="40">

            <img src="data:image/svg+xml;base64,\(image)" alt="Embedded" width="40" height="40">
            """))
        try #require(await eventually { gate.isSuspended })
        #expect(await eventually {
            guard let snapshot = reader.rendered,
                let embedded = snapshot.readerImageRegions(in: reader.viewport).first(where: { !$0.isRemote })
            else { return false }
            return snapshot.hasReaderImageResult(for: embedded)
        })
    }

    @Test func sameFileEditsReuseRemoteImageCache() async throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 360, height: 300)
        let reader = MarkdownReaderView(frame: frame)
        reader.readerPreparesForScrolling = false
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = reader
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await checkSameFileRemoteImageCache(reader) { reader.rendered?.size.height ?? 0 }
    }

    @Test func reportsTheSectionAfterRefiningALateHeading() async throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 360, height: 300)
        let reader = MarkdownReaderView(frame: frame)
        reader.readerPreparesForScrolling = false
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = reader
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        var section: String?
        reader.onPositionChange = { _, id in section = id }
        let markdown = (0..<1000).map { "## Section \($0)\n\nParagraph for section \($0)." }.joined(separator: "\n\n")
        reader.setDocument(MarkdownDocument(markdown: markdown))
        try #require(await eventually { reader.readerViewportDiagnostics.isViewportMeasured })
        reader.scroll(toAnchorID: "section-777", animated: false)
        #expect(await eventually { section == "section-777" && reader.readerViewportDiagnostics.isViewportMeasured })
    }

    @Test(arguments: [false, true]) func clampedHeadingStaysCurrentUntilTheViewportMoves(animated: Bool) async throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 360, height: 300)
        let reader = MarkdownReaderView(frame: frame)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = reader
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        var section: String?
        reader.onPositionChange = { _, id in section = id }
        let body = String(repeating: "\n\nA paragraph.", count: 20)
        reader.setDocument(MarkdownDocument(markdown: "# A\(body)\n\n# C\n\nShort.\n\n# D\n\nEnd."))
        try #require(await eventually { reader.readerViewportDiagnostics.isFullyMeasured })
        reader.scroll(toAnchorID: "d", animated: animated)
        #expect(await eventually { section == "d" })
        let end = reader.viewport.minY
        let heading = try #require(reader.rendered?.readerAnchorY(for: "d"))
        #expect(heading > end + 50)
        reader.scroll(toAnchorID: "c", animated: false)
        #expect(section == "c")
        #expect(abs(reader.viewport.minY - end) < 1)
        reader.scroll(toAnchorID: "d", animated: false)
        #expect(section == "d")
        let line = try #require(reader.topSourceLine)
        #expect(line > 40)
        reader.scroll(toSourceLine: line - 2, animated: false)
        #expect(section == "c" && reader.topSourceLine == line - 2)
        reader.scroll(toSourceLine: line - 1, animated: false)
        #expect(section == "d")
        reader.scroll(toAnchorID: "#c", animated: false)
        #expect(section == "c")
        // A finished older animation must not replace a newer destination.
        reader.scroll(toAnchorID: "a", animated: false)
        reader.scroll(toAnchorID: "c", animated: true)
        try await Task.sleep(for: .milliseconds(60))
        reader.scroll(toAnchorID: "d", animated: false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(section == "d")
        reader.scroll(toAnchorID: "missing", animated: animated)
        #expect(reader.topSourceLine == line)
        reader.style.fontSize = 60
        #expect(await eventually {
            guard let y = reader.rendered?.readerAnchorY(for: "d"), y > reader.viewport.maxY else { return false }
            return section != "d" && (reader.topSourceLine ?? line) < line
        })
        reader.style.fontSize = nil
        try #require(await eventually {
            reader.readerViewportDiagnostics.isFullyMeasured && reader.rendered?.readerAnchorY(for: "d") == heading
        })
        reader.scroll(toAnchorID: "d", animated: false)
        #expect(section == "d")
        reader.scrollReaderViewport(toY: end - 5)
        #expect(section == "a")
    }

    @Test(arguments: [false, true]) func sameFileReloadRestoresPositionUnlessOverridden(explicit: Bool) async throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 360, height: 300)
        let reader = MarkdownReaderView(frame: frame)
        reader.readerPreparesForScrolling = false
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = reader
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        let url = URL(fileURLWithPath: "/tmp/reflow-reload.md")
        let paragraphs = (0..<24).map { "Paragraph number \($0) for the same-file reload." }.joined(separator: "\n\n")
        let markdown = "# Start\n\n\(paragraphs)\n\n# Middle\n\n\(paragraphs)\n\n# End\n\n\(paragraphs)"
        reader.setDocument(MarkdownDocument(markdown: markdown), url: url)
        try #require(await eventually { reader.readerViewportDiagnostics.isViewportMeasured })
        reader.scroll(toAnchorID: "middle", animated: false)
        try #require(await eventually {
            guard let y = reader.rendered?.readerAnchorY(for: "middle") else { return false }
            return abs(reader.viewport.minY - y) < 20 && reader.readerViewportDiagnostics.isViewportMeasured
        })

        let updated = MarkdownDocument(markdown: "A paragraph inserted above every heading.\n\n" + markdown)
        let restore = explicit
            ? try #require(RenderedDocument(updated, width: 360, style: .init()).readingAnchor(forAnchor: "end"))
            : nil
        reader.setDocument(updated, url: url, restoring: restore)
        let heading = explicit ? "end" : "middle"
        #expect(await eventually {
            guard let y = reader.rendered?.readerAnchorY(for: heading) else { return false }
            return abs(reader.viewport.minY - y) < 20 && reader.readerViewportDiagnostics.isViewportMeasured
        })
    }

    @Test func teardownSavesVisiblePositionWhileStyleReflowIsPending() async throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 360, height: 300)
        let reader = MarkdownReaderView(frame: frame)
        reader.readerPreparesForScrolling = false
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = reader
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let body = String(repeating: "\n\nParagraph after the heading.", count: 30)
        reader.setDocument(MarkdownDocument(markdown: "# Start\n\nIntroduction.\n\n# Later" + body))
        try #require(await eventually { reader.readerViewportDiagnostics.isViewportMeasured })
        let visibleLayout = try #require(reader.rendered)
        let later = try #require(visibleLayout.readerAnchorY(for: "later"))
        var saved: ReadingAnchor?
        var section: String?
        reader.onPositionChange = { saved = $0; section = $1 }
        reader.style.fontSize = 24
        reader.scrollReaderViewport(toY: later + 8)
        reader.finish()
        #expect(reader.rendered === visibleLayout)
        #expect(section == "later")
        #expect(saved == visibleLayout.readingAnchor(atY: reader.viewport.minY))
    }

    @Test func newlyVisibleRemoteImageGetsTheNextSlotWithoutMembershipChanging() async throws {
        let gate = PriorityGate()
        let queue = ReaderViewportImages()
        defer {
            queue.stop()
            gate.releaseAll()
        }
        let names = ["overscan", "a", "b", "c", "d", "entering"]
        let markdown = names.map { name in
            "<img src=\"https://example.invalid/\(name)\" alt=\"\(name)\" width=\"40\" height=\"40\">"
        }.joined(separator: "\n\n")
        let resources = ReaderImageResources(MarkdownRemoteImages { url in
            await gate.wait(url.lastPathComponent)
            return nil
        })
        let snapshot = await DocumentReflowSession(
            MarkdownDocument(markdown: markdown), style: .init(), readerDisplayScale: 1, readerResources: resources
        ).render(width: 320)
        let regions = snapshot.readerImageRegions(in: CGRect(origin: .zero, size: snapshot.size))
        try #require(regions.count == 6)
        let top = regions[0].rect.maxY + 1
        let bottom = regions[5].rect.minY - 1
        let viewport = CGRect(x: 0, y: top, width: snapshot.size.width, height: bottom - top)
        let scrolled = viewport.offsetBy(dx: 0, dy: 10)
        let overscan: CGFloat = 80
        try #require(snapshot.readerImageRegions(in: viewport) == Array(regions[1...4]))
        try #require(snapshot.readerImageRegions(in: scrolled).last == regions[5])
        try #require(snapshot.readerImageRegions(in: viewport.insetBy(dx: 0, dy: -overscan)) == regions)
        try #require(snapshot.readerImageRegions(in: scrolled.insetBy(dx: 0, dy: -overscan)) == regions)

        queue.update(snapshot, in: viewport, overscan: overscan, tableOffsets: [:], invalidate: { _ in }, relayout: {})
        try #require(await eventually { gate.started.count == 4 })
        #expect(Set(gate.started) == Set(names[1...4]))
        queue.update(snapshot, in: scrolled, overscan: overscan, tableOffsets: [:], invalidate: { _ in }, relayout: {})
        gate.release(gate.started[0])
        try #require(await eventually { gate.started.count == 5 })
        #expect(gate.started.last == "entering")
    }

    @MainActor private final class PriorityGate {
        private(set) var started: [String] = []
        private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
        private var released = false

        func wait(_ name: String) async {
            started.append(name)
            if !released { await withCheckedContinuation { waiting[name] = $0 } }
        }

        func release(_ name: String) { waiting.removeValue(forKey: name)?.resume() }

        func releaseAll() {
            released = true
            for continuation in waiting.values { continuation.resume() }
            waiting.removeAll()
        }
    }

    @Test func legacyTableScrollerKeepsItsNativeHitAreaOverTheFullTableViewport() throws {
        let style = RenderStyle(insets: .zero)
        let rendered = RenderedDocument(
            MarkdownDocument(markdown: """
                | First column | Second column | Third column |
                |---|---|---|
                | Longer description | Another description | Final paragraph |
                """),
            width: 205, style: style, scrollableTables: true)
        let table = try #require(rendered.tables.first)
        try #require(table.isScrollable)
        let view = ReaderTableScrollView(frame: .zero)
        let parent = NSView(frame: CGRect(origin: .zero, size: rendered.size))
        parent.addSubview(view)
        view.scrollerStyle = .legacy
        view.install(table, offset: 0)
        view.tile()
        #expect(abs(view.contentView.bounds.height - table.frame.height) <= 1)
        let scroller = try #require(view.horizontalScroller)
        #expect(type(of: scroller) == NSScroller.self)
        let knob = scroller.rect(for: .knob)
        try #require(!knob.isEmpty)
        let point = scroller.convert(CGPoint(x: knob.midX, y: knob.midY), to: parent)
        #expect(view.hitTest(point) === scroller)
        #expect(scroller.accessibilityRole() == .scrollBar)
    }

    @Test func changingScrollerClassKeepsLayoutAndScrollOffsets() async throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 245, height: 200)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        let reader = MarkdownReaderView(frame: frame)
        reader.style = RenderStyle(insets: .zero)
        reader.readerPreparesForScrolling = false
        window.contentView = reader
        defer { window.contentView = nil }

        let table = """
            | First column | Second column | Third column |
            |---|---|---|
            | Longer description | Another description | Final paragraph |
            """
        let paragraphs = Array(repeating: "A paragraph between tables.", count: 25).joined(separator: "\n\n")
        reader.setDocument(MarkdownDocument(markdown: "# Start\n\n\(table)\n\n\(paragraphs)\n\n\(table)"))
        try #require(await eventually { reader.rendered?.tables.first?.isScrollable == true })
        let scrollView = try #require(reader.subviews.first as? NSScrollView)
        func displayedTables() -> [ReaderTableScrollView] {
            reader.canvas.subviews.compactMap { $0 as? ReaderTableScrollView }
        }
        let existingTable = try #require(displayedTables().first)
        #expect(displayedTables().count == 1)
        #expect(scrollView.verticalScroller.map { type(of: $0) == NSScroller.self } == true)
        reader.scrollReaderViewport(toY: 20)
        existingTable.applyOffset(24)
        try #require(await eventually { !reader.readerViewportDiagnostics.isLayingOut })

        let layout = try #require(reader.rendered)
        let origin = reader.viewport.origin
        let offset = existingTable.contentView.bounds.minX
        let offsets = reader.tableOffsets
        #expect(origin.y > 0)
        #expect(offset > 0)
        #expect(offsets.values.contains(offset))

        reader.scrollerClass = HookScroller.self
        let vertical = try #require(scrollView.verticalScroller as? HookScroller)
        let horizontal = try #require(existingTable.horizontalScroller as? HookScroller)
        reader.scrollerClass = HookScroller.self
        #expect(scrollView.verticalScroller === vertical)
        #expect(existingTable.horizontalScroller === horizontal)
        #expect(displayedTables().first === existingTable)
        #expect(reader.viewport.origin == origin)
        #expect(existingTable.contentView.bounds.minX == offset)
        #expect(reader.tableOffsets == offsets)
        #expect(reader.rendered === layout)
        #expect(!reader.readerViewportDiagnostics.isLayingOut)

        reader.scrollReaderViewport(toY: reader.canvas.frame.height - frame.height)
        let firstID = try #require(existingTable.tableCanvas.table?.id)
        try #require(await eventually {
            displayedTables().contains { $0.tableCanvas.table?.id != firstID }
        })
        let laterTable = try #require(displayedTables().first { $0.tableCanvas.table?.id != firstID })
        #expect(laterTable.horizontalScroller is HookScroller)
        reader.scrollerClass = NSScroller.self
        let nativeVertical = try #require(scrollView.verticalScroller)
        let nativeHorizontal = try #require(laterTable.horizontalScroller)
        #expect(type(of: nativeVertical) == NSScroller.self)
        #expect(type(of: nativeHorizontal) == NSScroller.self)
    }

    private final class HookScroller: NSScroller {
        override class var isCompatibleWithOverlayScrollers: Bool { true }
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    @MainActor private final class ImageGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        var isSuspended: Bool { continuation != nil }

        func suspend() async {
            if !released { await withCheckedContinuation { continuation = $0 } }
        }

        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }
}
#endif
