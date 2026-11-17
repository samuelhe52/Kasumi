import PDFKit
import Testing

@testable import KasumiMarkdown

@Test func missingGlyphSquaresPreserveSourceAndWorkingFontFallback() throws {
    let absent = "\u{10FFFF}"
    let sample = "\(absent)\(absent) · Han 漢 · emoji 👩‍👧 · accent e\u{0301}"
    let markdown = """
        \(sample)

        ~~~text
        code \(absent) done
        ~~~

        ~~~mermaid
        graph LR
        A[Diagram \(absent) label]
        ~~~
        """
    let document = MarkdownDocument(markdown: markdown)
    let layout = DocumentTypesetter.layout(document.parsed, width: 320, style: Typography())
    #expect(layout.text.string.contains("□□ · Han 漢 · emoji 👩‍👧 · accent e\u{0301}"))
    #expect(layout.text.string.contains("code □ done"))
    let rendered = RenderedDocument(document, width: 320, style: .init())
    let matches = rendered.ranges(matching: absent)
    #expect(matches.count == 4)
    for match in matches {
        #expect(rendered.text(in: match) == absent)
        let rect = try #require(rendered.selectionRects(for: match).first)
        #expect(rect.width > 0 && rect.width < 30 && rect.height > 0)
    }
    #expect(rendered.ranges(matching: "□").isEmpty)
    let pdf = try #require(
        PDFDocument(
            data: DocumentExport.pdf(
                document, style: .init(), pageSize: CGSize(width: 420, height: 540), margins: .reader)))
    let page = try #require(pdf.page(at: 0))
    let text = try #require(page.string)
    #expect(text.contains("□□"))
    #expect(text.contains("code □ done"))
    #expect(text.contains("Diagram □ label"))
}
