import Testing

@testable import KasumiMarkdown

@Suite struct SourceLineMappingTests {
    @Test func markdownBlocksKeepOriginalSourceRanges() throws {
        let document = MarkdownDocument(
            markdown: """
                # Start

                A wrapped paragraph
                with a second source line.

                ---

                | Column | Value |
                | ------ | ----- |
                | A      | B     |

                ## End
                """)
        let rendered = RenderedDocument(document, width: 300, style: .init())
        let paragraph = try #require(rendered.readerSourceTop(for: 3))
        let rule = try #require(rendered.readerSourceTop(for: 6))
        let table = try #require(rendered.readerSourceTop(for: 8))
        let end = try #require(rendered.readerSourceTop(for: 12))

        #expect(rendered.readerSourceLine(atY: 0) == 1)
        #expect(rendered.readerSourceTop(for: 2) == paragraph)
        #expect(rendered.readerSourceTop(for: 4) == paragraph)
        #expect(rendered.readerSourceLine(atY: paragraph) == 3)
        #expect(rendered.readerSourceLine(atY: rule) == 6)
        #expect(rendered.readerSourceTop(for: 10) == table)
        #expect(rendered.readerSourceLine(atY: table + 1) == 8)
        #expect(rendered.readerSourceTop(for: 500) == end)
        #expect(rendered.readerSourceLine(atY: rendered.size.height) == 12)
        #expect(document.outline.map(\.sourceLine) == [1, 12])
    }

    @Test func htmlBlocksKeepTheirOwnSourceLines() throws {
        let document = MarkdownDocument(
            markdown: "Intro\n\n<div>\r\n<h1>One</h1>\n<p>\nFirst\nparagraph\n</p>\n<h2>\nTwo\n</h2>\n</div>\n")
        #expect(document.parsed.blocks.map(\.sourceLines) == [1...1, 4...4, 5...8, 9...11])
        #expect(document.outline.map(\.sourceLine) == [4, 9])
        let rendered = RenderedDocument(document, width: 300, style: .init())
        let first = try #require(rendered.readerSourceTop(for: 4))
        let second = try #require(rendered.readerSourceTop(for: 10))
        #expect(second > first)
        #expect(rendered.readerSourceLine(atY: second) == 9)
    }

    @Test func plainTextAndEmptyDocuments() throws {
        let plainText = RenderedDocument(
            MarkdownDocument(
                plainText: "One line.\r\nWrapped line.\r\n\r\nSecond paragraph.", options: .init(paragraphMode: .blank)),
            width: 300, style: .init())
        let second = try #require(plainText.readerSourceTop(for: 4))
        #expect(plainText.readerSourceTop(for: 2) == plainText.readerSourceTop(for: 1))
        #expect(plainText.readerSourceLine(atY: second) == 4)

        let empty = RenderedDocument(MarkdownDocument(markdown: ""), width: 300, style: .init())
        #expect(empty.readerSourceLine(atY: 0) == nil)
        #expect(empty.readerSourceTop(for: 1) == nil)
    }
}
