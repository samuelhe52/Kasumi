import KasumiMarkdown
import Testing

@Suite struct PlainTextExportTests {
    @Test func exportsVisibleSpansAltTextAndTeXWithoutMarkup() {
        let source = #"""
            # **Heading**

            Read *plain* [labels](https://example.com), `code`, ![small icon](icon.png), and $x_i$.\
            Next line.

            $$
            \frac{1}{2}
            $$

            ![Full alternative](photo.png)

            ---
            """#
        #expect(
            DocumentExport.plainText(MarkdownDocument(markdown: source)) == #"""
                Heading

                Read plain labels, code, small icon, and x_i.
                Next line.

                \frac{1}{2}

                Full alternative

                ---
                """#)
    }

    @Test func expandsMathInImageAltText() {
        let source = "Read ![the value $x_i$](icon.png).\n\n![$x$](image.png)"
        #expect(DocumentExport.plainText(MarkdownDocument(markdown: source)) == "Read the value x_i.\n\nx")
        // Code in alt text stays literal instead of becoming highlight markup.
        let code = "![`a == b == c`](icon.png)"
        #expect(DocumentExport.plainText(MarkdownDocument(markdown: code)) == "`a == b == c`")
    }

    @Test func keepsEmptyListItems() {
        let source = "1. One\n2.\n3. Three\n\n> - a\n> -\n> - b"
        #expect(
            DocumentExport.plainText(MarkdownDocument(markdown: source)) == "1. One\n2.\n3. Three\n\n> • a\n> •\n> • b")
    }

    @Test func stripsSourcePrefixesFromDisplayMathInsideParagraphs() {
        let source = "> Intro\n> $$\n> x\n> $$"
        #expect(DocumentExport.plainText(MarkdownDocument(markdown: source)) == "> Intro\n> x")
    }

    @Test func numbersFootnoteReferencesAndIndentsDefinitionContinuations() {
        let source = #"""
            See this.[^note]

            | Name | Note |
            | --- | --- |
            | first[^note] | next[^other] |

            [^note]: First paragraph.

                Second paragraph.\
                Next line.

            [^other]: Another note.

            Back to body text.
            """#
        #expect(
            DocumentExport.plainText(MarkdownDocument(markdown: source)) == """
                See this.[1]

                Name\tNote
                first[1]\tnext[2]

                [1] First paragraph.

                    Second paragraph.
                    Next line.

                [2] Another note.

                Back to body text.
                """)
    }

    @Test func stripsSourcePrefixesFromMultilineDisplayMath() {
        let source = """
            > $$
            > x
            >   y
            > > z
            > $$

            > 9. First
            > 1. $$
            >    a
            >      b
            >    $$

            - > $$
              > c
              > $$
            """
        #expect(
            DocumentExport.plainText(MarkdownDocument(markdown: source)) == """
                > x
                >   y
                > > z

                > 9. First
                > 10. a
                >       b

                • > c
                """)
    }

    @Test func stripsListIndentationWithoutLosingMathIndentation() {
        let source = "  - $$\n      x\n    $$\n\n* $$\n\ty\n\t$$"
        #expect(DocumentExport.plainText(MarkdownDocument(markdown: source)) == "•   x\n\n•   y")
    }

    @Test func retainsListStartsTasksAndParagraphSeparation() {
        let source = """
            7. First
               - [x] Done
               - [ ] Waiting

               Second paragraph

            8. Next
            """
        #expect(
            DocumentExport.plainText(MarkdownDocument(markdown: source)) == """
                7. First
                   ☑ Done
                   ☐ Waiting

                   Second paragraph
                8. Next
                """)
    }

    @Test func retainsQuoteAndListAncestryForNonParagraphBlocks() {
        let source = #"""
            > - ## Quoted heading
            >   > deeper\
            >   > next line
            >
            > - ![picture](image.png)

            - > block quote
              >
              > more

            - - only child
            """#
        #expect(
            DocumentExport.plainText(MarkdownDocument(markdown: source)) == """
                > • Quoted heading
                >
                >   > deeper
                >   > next line
                > • picture

                • > block quote
                  >
                  > more
                •
                  • only child
                """)
    }

    @Test func retainsRawCodeAndMermaidWhitespaceWithoutExtraBlankLines() {
        let code = "  indented  \n\n\tlast\t\n\n"
        let diagram = "flowchart TD\n  A[Start] --> B[Done]\n"
        let source = "Before\n\n```text\n" + code + "```\n\n```mermaid\n" + diagram + "```\n\nAfter"
        #expect(DocumentExport.plainText(MarkdownDocument(markdown: source)) == "Before\n\n" + code + diagram + "\nAfter")
    }

    @Test func keepsCodeAndRuleUnderTheirListMarkers() {
        let source = """
            > - ```text
            >     indented
            >
            >   next
            >   ```
            >
            > - ***
            """
        #expect(
            DocumentExport.plainText(MarkdownDocument(markdown: source)) == """
                > •   indented
                >
                >   next
                > • ---
                """)
    }

    @Test func preservesTableShapeAndFlattensCellSeparators() {
        let source = """
            | Name | Note |
            | --- | --- |
            | first<br><br>line | tab&#9;separated |
            | single |
            """
        #expect(DocumentExport.plainText(MarkdownDocument(markdown: source)) == "Name\tNote\nfirst line\ttab separated\nsingle\t")
    }

    @Test func emptyContentDoesNotAddSeparators() {
        #expect(DocumentExport.plainText(MarkdownDocument(markdown: "")) == "")
        #expect(DocumentExport.plainText(MarkdownDocument(markdown: "```\n```\n\nText")) == "Text")
    }
}
