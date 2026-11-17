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

@Test func inlineMarkerScanningPreservesTextAndTraits() throws {
    let extensions = MarkdownExtensions(source: "$x+y$")
    let marker = try #require(extensions.math.keys.first)
    let traits: Set<InlineRun.Trait> = [.strong, .link]
    let destination = "https://example.com"
    for text in ["", "ordinary prose", String(repeating: "plain text ", count: 100), "中文 Café 🙂", "\u{E123} literal", "a = b"] {
        let runs = extensions.textRuns(text, traits: traits, destination: destination)
        #expect(runs == (text.isEmpty ? [] : [InlineRun(text, traits: traits, destination: destination)]))
    }
    let runs = extensions.textRuns("before \(marker) ==marked== after", traits: traits, destination: destination)
    #expect(runs.map(\.text) == ["before ", "x+y", " ", "marked", " after"])
    #expect(runs[1].traits == traits.union([.math]))
    #expect(runs[3].traits == traits.union([.highlight]))
    #expect(runs.allSatisfy { $0.destination == destination && $0.traits.isSuperset(of: traits) })

    let literal = "\u{E000}kasumi.math.0\u{E001}"
    for source in [literal, "Math $x+y$.\n\n" + literal + "\n\nA [^a].\n\n[^a]: Note"] {
        let protected = MarkdownExtensions(source: source)
        #expect(!source.contains(protected.mathPrefix))
        let parsed = DocumentParser.parse(source)
        #expect(parsed.blocks.contains { $0.text == literal })
        #expect(source == literal || parsed.blocks.flatMap(\.runs).contains { $0.traits.contains(.math) })
    }
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
    let literalDelimiters = MarkdownExtensions(
        source: "Text `$inline$` and <span title=\"$attribute$\">real $y$</span>.\n\n"
            + "<div>\n$block$\n</div>\n\n```text\n$fenced$\n```\n\n    $indented$\n")
    #expect(literalDelimiters.math.values.map(\.text) == ["y"])
    let parsed = DocumentParser.parse("Text $x$.\n\nA note [^a].\n\n[^a]: $y$\n    continued $z$\n")
    #expect(parsed.blocks.contains { $0.footnoteLabel == "a" && $0.runs.contains { $0.traits.contains(.math) } })
    #expect(parsed.blocks.flatMap(\.runs).contains { $0.footnoteDisplay == "1" })
}
