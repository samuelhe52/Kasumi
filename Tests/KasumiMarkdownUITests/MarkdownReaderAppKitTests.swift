#if os(macOS)
import AppKit
import KasumiMarkdown
import Testing

@testable import KasumiMarkdownUI

@MainActor @Suite(.serialized) struct MarkdownReaderAppKitTests {
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
