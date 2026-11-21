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
}
#endif
