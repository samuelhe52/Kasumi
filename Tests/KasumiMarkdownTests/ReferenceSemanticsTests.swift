import Foundation
import CryptoKit
import Testing
@testable import KasumiMarkdown

private struct CoreSnapshot: Decodable {
    var blocks: Int
    var fixture_sha256: String
    var items: [Item]
    struct Item: Decodable {
        var kind: Int
        var level: Int
        var text: String
        var footnote_label: String
        var display_label: String
        var marks: [String]
    }
}

@Test(arguments: ["Rendering", "ExtensionSemantics"])
func parserSemanticsMatchNativeReference(fixture: String) throws {
    let root = testRepositoryURL
    let input = try Data(contentsOf: root.appendingPathComponent("fixtures/\(fixture).md"))
    let snapshot = try JSONDecoder().decode(CoreSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/\(fixture).core.json")))
    #expect(SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined() == snapshot.fixture_sha256)
    let document = DocumentParser.parse(String(decoding: input, as: UTF8.self))
    #expect(document.blocks.count == snapshot.blocks)
    let kinds: [DocumentBlock.Kind: Int] = [.paragraph: 0, .quote: 0, .heading: 1, .code: 2, .diagram: 2, .rule: 4, .table: 6, .math: 7]
    for (index, pair) in zip(document.blocks, snapshot.items).enumerated() {
        let (block, expected) = pair
        let kind = block.prefix.isEmpty ? kinds[block.kind] : 3
        #expect(kind == expected.kind, "\(fixture) block \(index) kind")
        #expect(block.text == expected.text, "\(fixture) block \(index) text")
        if block.kind == .heading { #expect(block.level == expected.level) }
        #expect((block.footnoteLabel ?? "") == expected.footnote_label, "\(fixture) block \(index) definition")
        #expect((block.footnoteDisplay ?? "") == expected.display_label, "\(fixture) block \(index) display label")
        #expect(block.runs.compactMap(\.footnoteDisplay) == expected.marks, "\(fixture) block \(index) marks")
    }
}

@Test func extensionProtectionPreservesCodeAndMathSource() {
    let parsed = DocumentParser.parse("`$x_i$` and $x_i + \\{a\\} + \\frac{1}{2}\\,dx$.")
    #expect(parsed.blocks[0].runs.contains { $0.text == "$x_i$" && $0.traits.contains(.code) })
    #expect(parsed.blocks[0].runs.contains { $0.text == "x_i + \\{a\\} + \\frac{1}{2}\\,dx" && $0.traits.contains(.math) })
    #expect(parsed.blocks[0].runs.allSatisfy { !$0.traits.contains(.emphasis) })
}

@Test func backslashDelimitersMatchDollarMath() {
    let parsed = DocumentParser.parse(#"""
    Inline \(x_i + \{a\}\), $y_j$, `\(code\)`, \\(not math\\), \(unclosed, and \[x\] mid-line.

    \[
    \int_0^1 x^2\,dx
    \]

    \[unclosed
    """#)
    #expect(parsed.blocks[0].runs.filter { $0.traits.contains(.math) }.map(\.text) == [#"x_i + \{a\}"#, "y_j"])
    #expect(parsed.blocks[0].runs.contains { $0.text == #"\(code\)"# && $0.traits.contains(.code) })
    #expect(parsed.blocks[0].text.hasSuffix(#", \(not math\), (unclosed, and [x] mid-line."#))
    #expect(parsed.blocks[1].kind == .math)
    #expect(parsed.blocks[1].runs.map(\.text) == ["\n\\int_0^1 x^2\\,dx\n"])
    #expect(parsed.blocks[1].sourceLines == 3...5)
    #expect(parsed.blocks[2].kind == .paragraph && parsed.blocks[2].text == "[unclosed")
}

@Test func footnotesRetainSourceLinesAndUndefinedReferences() {
    let parsed = DocumentParser.parse("Start[^later], [^missing].\n\n[^later]: First.\n\n    Second.\n")
    #expect(parsed.blocks[0].text == "Startlater, [^missing].")
    #expect(parsed.blocks[1].footnoteDisplay == "1")
    #expect(parsed.blocks[2].footnoteDisplay == "1")
    #expect(parsed.blocks[2].sourceLines?.lowerBound == 5)
}

@Test func footnotePresentationUsesResolvedMarkersAndAnchors() {
    let parsed = DocumentParser.parse("# A heading!\n\nText[^key].\n\n[^key]: Note body.\n\n# A heading!\n")
    let style = Typography()
    let attributed = style.attributed(parsed.blocks[1].runs)
    #expect(attributed.string == "Text1.")
    #expect((attributed.attribute(.baselineOffset, at: 4, effectiveRange: nil) as? Double ?? 0) > 0)
    let layout = DocumentTypesetter.layout(parsed, width: 600, style: style)
    #expect(layout.anchorPositions["fn-key"] != nil)
    #expect(layout.anchorPositions["a-heading"] != nil)
    #expect(layout.anchorPositions["a-heading-1"] != nil)
    #expect((layout.anchorPositions["a-heading-1"] ?? 0) > (layout.anchorPositions["a-heading"] ?? 0))
}

@Test func mathProtectionUsesUTF8SourceColumnsAfterCJK() {
    let parsed = DocumentParser.parse("中文 `代码 $literal$`；公式 $x_i$ 与 **$y_j$**。")
    let runs = parsed.blocks[0].runs
    #expect(runs.contains { $0.text == "代码 $literal$" && $0.traits.contains(.code) })
    #expect(runs.filter { $0.traits.contains(.math) }.map(\.text) == ["x_i", "y_j"])
    #expect(runs.contains { $0.text == "y_j" && $0.traits.contains(.strong) })
}
