import Testing

@testable import KasumiMarkdown

@Test func nestedFormattingPreservesTextAndTraits() {
    let parsed = DocumentParser.parse("# Heading\n\nA **bold *nested*** and [link](https://example.com).\n")
    #expect(parsed.headings.map(\.text) == ["Heading"])
    #expect(parsed.blocks[1].text == "A bold nested and link.")
    let nested = parsed.blocks[1].runs.first { $0.text == "nested" }
    #expect(nested?.traits == [.strong, .emphasis])
    #expect(parsed.blocks[1].runs.first { $0.destination != nil }?.destination == "https://example.com")
}

@Test func tablesAndListHierarchyAreStructured() {
    let parsed = DocumentParser.parse("- Parent\n  - Child\n\n| A | B |\n|---|---:|\n| x | y |\n")
    #expect(parsed.blocks[0].prefix == "•")
    #expect(parsed.blocks[1].level > parsed.blocks[0].level)
    let table = parsed.blocks.first { $0.kind == .table }
    #expect(table?.rows.count == 2)
    #expect(table?.rows[1][1].map(\.text).joined() == "y")
}

@Test func plaintextDoesNotInterpretMarkdown() {
    let parsed = DocumentParser.parse("Chapter IV\n**literal**\n", plainText: true)
    #expect(parsed.blocks.first?.kind == .heading)
    #expect(parsed.blocks.last?.text == "**literal**")
    #expect(parsed.blocks.last?.runs.first?.traits.isEmpty == true)
}

@Test func displayMathStaysSeparateFromInlineMath() {
    let parsed = DocumentParser.parse("Inline $x+y$.\n\n$$\n\\frac{1}{2}\\,dx\n$$\n")
    #expect(parsed.blocks[0].runs.contains { $0.text == "x+y" && $0.traits.contains(.math) })
    #expect(parsed.blocks[1].kind == .math)
    #expect(parsed.blocks[1].text.contains("\\frac{1}{2}\\,dx"))
}

@Test func mathLineIndexPreservesSourceRangesAcrossManyExpressionsAndCode() throws {
    let source = (0..<60).map { index in
        "Paragraph \(index) $x_\(index)$\n\n```text\n$not_math$\n```\n\n$$\ny_\(index)\n$$"
    }.joined(separator: "\n\n")
    let extensions = MarkdownExtensions(source: source)
    #expect(extensions.math.count == 120)
    for index in 0..<60 {
        let inline = try #require(extensions.math.values.first { $0.text == "x_\(index)" })
        let display = try #require(extensions.math.values.first { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "y_\(index)" })
        #expect(inline.sourceLines == (index * 10 + 1)...(index * 10 + 1))
        #expect(display.sourceLines == (index * 10 + 7)...(index * 10 + 9))
    }
    let parsed = DocumentParser.parse("Text $x$.\n\nA note [^a].\n\n[^a]: $y$\n    continued $z$\n")
    #expect(parsed.blocks.contains { $0.footnoteLabel == "a" && $0.runs.contains { $0.traits.contains(.math) } })
    #expect(parsed.blocks.flatMap(\.runs).contains { $0.footnoteDisplay == "1" })
}
