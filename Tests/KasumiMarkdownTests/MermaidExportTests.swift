import PDFKit
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

@Test func diagramsFitReadingMeasureAndRemainAtomicOnPDFPages() throws {
    let source = "pie title A wide legend\n\"A substantially wider category\" : 70\n\"Other\" : 30"
    let document = DocumentParser.parse("```mermaid\n\(source)\n```\n\nAfter diagram.")
    var priorSize: CGSize?
    for width: CGFloat in [240, 400, 800] {
        let layout = DocumentTypesetter.layout(document, width: width, style: Typography())
        var attachment: MermaidAttachment?
        layout.text.enumerateAttribute(.kasumiDiagram, in: NSRange(location: 0, length: layout.text.length)) {
            value, _, _ in
            attachment = value as? MermaidAttachment ?? attachment
        }
        let diagram = try #require(attachment)
        #expect(diagram.size.width <= width - 80 + 0.001)
        #expect(diagram.size.height > 0 && diagram.size.height.isFinite)
        if let priorSize {
            #expect(abs(diagram.size.width / diagram.size.height - priorSize.width / priorSize.height) < 0.0001)
        }
        priorSize = diagram.size
        let group = try #require(layout.paginationGroups.first)
        let pages = try DocumentPaginator.pages(for: layout, contentHeight: 150)
        #expect(pages.contains { $0.range.lowerBound <= group.lowerBound && $0.range.upperBound >= group.upperBound })
    }
}

@Test func diagramExportPaintsSelectableLabelsAndDiagnostics() throws {
    let doc = DocumentParser.parse("```mermaid\ngraph LR\nA[Start] --> B[Finish]\n```\n\n```mermaid\ngantt\nTask\n```")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mermaid-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    try DocumentExporter.writePDF(doc, style: Typography(), to: url)
    let data = try Data(contentsOf: url)
    let pdf = try #require(PDFDocument(data: data))
    let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    #expect(text.contains("Start") && text.contains("Finish"))
    #expect(!text.contains("A[Start]"))
    #expect(text.contains("unsupported diagram type"))
    #expect(text.contains("gantt") && text.contains("Task"))
}

@Test func diagramPreprocessingRetainsDiagnosticLineNumbers() throws {
    let source = "---\ntitle: A diagram\n---\ngraph LR\n%% internal comment\nA["
    #expect(throws: MermaidError.syntax(line: 6)) {
        try MermaidTypesetter.layout(source, size: 16, fontFamily: "Helvetica", dark: false)
    }
    #expect(throws: MermaidError.syntax(line: 5)) {
        try MermaidTypesetter.layout("\n\n%% prefix\ngraph LR\nA[", size: 16, fontFamily: "Helvetica", dark: false)
    }
    #expect(throws: MermaidError.syntax(line: 3)) {
        try MermaidTypesetter.layout(
            "\u{FEFF}\n%% prefix\n---\ntitle: A diagram\n---\ngraph LR\nA[", size: 16, fontFamily: "Helvetica",
            dark: false)
    }
}

@Test func mermaidLabelSelectionAndNodeLinksTrackScaledDiagrams() throws {
    let markdown = """
        Before diagram.

        ~~~mermaid
        flowchart TB
          A[Open guide] -->|Try this| B[Finish here]
          A --> C[Unsafe link]
          click A href "guide.html" "Tooltip"
          click B "#after-diagram"
          click C "javascript:alert(1)"
        ~~~

        ## After diagram
        """
    let document = MarkdownDocument(markdown: markdown, baseURL: URL(string: "https://example.com/help/"))
    for width in [200.0, 500.0] {
        let rendered = RenderedDocument(document, width: width, style: .init())
        let word = try #require(rendered.ranges(matching: "guide").first)
        let rect = try #require(rendered.selectionRects(for: word).first)
        let point = CGPoint(x: rect.midX, y: rect.midY)
        #expect(rendered.link(at: point)?.absoluteString == "https://example.com/help/guide.html")
        let position = rendered.position(closestTo: point)
        let selection = try #require(rendered.wordRange(at: position))
        #expect(rendered.text(in: selection) == "guide")
        let start = rendered.caretRect(for: word.lowerBound)
        let end = rendered.caretRect(for: word.upperBound)
        #expect(abs(start.minX - rect.minX) < 1 && abs(end.minX - rect.maxX) < 1)
        let edge = try #require(rendered.ranges(matching: "Try this").first)
        let edgeRect = try #require(rendered.selectionRects(for: edge).first)
        #expect(rendered.link(at: CGPoint(x: edgeRect.midX, y: edgeRect.midY)) == nil)
        let unsafe = try #require(rendered.ranges(matching: "Unsafe link").first)
        let unsafeRect = try #require(rendered.selectionRects(for: unsafe).first)
        #expect(rendered.link(at: CGPoint(x: unsafeRect.midX, y: unsafeRect.midY)) == nil)
        #expect(rendered.ranges(matching: "click A").isEmpty)
        #expect(rendered.selectionRects(for: rendered.documentRange).contains {
            $0.insetBy(dx: -0.01, dy: -0.01).contains(rect)
        })
    }
    var options = PDFExportOptions()
    options.paperSize = CGSize(width: 255, height: 135)
    options.margins = .init(top: 28, left: 30, bottom: 23, right: 38)
    options.pageNumbers = false
    let pdf = try #require(PDFDocument(data: DocumentExporter.pdfData(
        document.parsed, style: Typography(), options: options)))
    let pages = (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }
    let page = try #require(pages.first { $0.annotations.contains { $0.url?.path == "/help/guide.html" } })
    let node = try #require(page.annotations.first { $0.url?.path == "/help/guide.html" })
    #expect(page.selection(for: node.bounds)?.string?.contains("Open guide") == true)
    #expect(node.bounds.minY >= options.margins.bottom - 0.01)
    #expect(node.bounds.maxY <= options.paperSize.height - options.margins.top + 0.01)
    let internalLink = try #require(page.annotations.first { $0.type == "Link" && $0.url == nil })
    #expect(page.selection(for: internalLink.bounds)?.string?.contains("Finish here") == true)
    #expect(internalLink.destination?.page?.string?.contains("After diagram") == true)
    #expect(page.annotations.filter { $0.type == "Link" }.count == 2)
}

@Test func mermaidClassClickHrefUsesTheClassNode() throws {
    let source = """
        classDiagram
        class Guide
        click Guide href "https://example.com/guide"
        """
    let document = MarkdownDocument(markdown: "~~~mermaid\n\(source)\n~~~")
    let rendered = RenderedDocument(document, width: 360, style: .init())
    let label = try #require(rendered.ranges(matching: "Guide").first)
    let rect = try #require(rendered.selectionRects(for: label).first)
    #expect(rendered.link(at: CGPoint(x: rect.midX, y: rect.midY))?.absoluteString == "https://example.com/guide")
}
