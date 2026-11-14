#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import PDFKit
import Testing
@testable import KasumiMarkdown

@Test func diagramsFitReadingMeasureAndRemainAtomicOnPDFPages() throws {
    let source = "pie title A wide legend\n\"A substantially wider category\" : 70\n\"Other\" : 30"
    let document = DocumentParser.parse("```mermaid\n\(source)\n```\n\nAfter diagram.")
    var priorSize: CGSize?
    for width: CGFloat in [240, 400, 800] {
        let layout = DocumentTypesetter.layout(document, width: width, style: Typography())
        var attachment: MermaidAttachment?
        layout.text.enumerateAttribute(.kasumiDiagram, in: NSRange(location: 0, length: layout.text.length)) { value, _, _ in
            attachment = value as? MermaidAttachment ?? attachment
        }
        let diagram = try #require(attachment)
        #expect(diagram.size.width <= width - 80 + 0.001)
        #expect(diagram.size.height > 0 && diagram.size.height.isFinite)
        if let priorSize { #expect(abs(diagram.size.width / diagram.size.height - priorSize.width / priorSize.height) < 0.0001) }
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
        try MermaidTypesetter.layout("\u{FEFF}\n%% prefix\n---\ntitle: A diagram\n---\ngraph LR\nA[", size: 16, fontFamily: "Helvetica", dark: false)
    }
}
