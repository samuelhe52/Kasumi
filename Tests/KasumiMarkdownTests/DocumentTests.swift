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
