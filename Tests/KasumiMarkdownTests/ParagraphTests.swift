import CoreText
import Foundation
import Testing

@testable import KasumiMarkdown

@Test func paragraphOptimizationLooksBeyondGreedyLine() {
    let source = "aaa bb cc ddddd"
    let ns = source as NSString
    let result = ParagraphBreaker.ranges(in: source, width: 6, alignment: .leading) { Double($0.length) }
    #expect(result.map { ns.substring(with: $0) } == ["aaa", "bb cc", "ddddd"])
}

@Test func emergencyBreakingDoesNotSplitGraphemes() {
    let source = "a👩‍👩‍👧‍👦e\u{301}汉字word"
    let ns = source as NSString
    let boundaries = Set(source.indices.map { $0.utf16Offset(in: source) } + [ns.length])
    let lines = ParagraphBreaker.ranges(in: source, width: 1, alignment: .leading) { Double($0.length) }
    #expect(!lines.isEmpty)
    for line in lines {
        #expect(boundaries.contains(line.location))
        #expect(boundaries.contains(NSMaxRange(line)))
    }
    #expect(lines.map { ns.substring(with: $0) }.joined() == source)
}

@Test func hardBreaksSurviveParagraphOptimization() {
    let source = "one two\nthree four"
    let ns = source as NSString
    let lines = ParagraphBreaker.ranges(in: source, width: 100, alignment: .leading) { Double($0.length) }
    #expect(lines.map { ns.substring(with: $0) } == ["one two", "three four"])
}

@Test func shapedMixedScriptsHaveFiniteGeometry() {
    let style = Typography()
    let text = "中文排版 mixed English words with **not syntax** and 日本語."
    let attributed = style.attributed([InlineRun(text)])
    let paragraph = ParagraphTypesetter.layout(attributed, width: 240, fontSize: 16)
    #expect(paragraph.lines.count > 1)
    #expect(paragraph.height.isFinite && paragraph.height > 0)
    for line in paragraph.lines {
        #expect(line.width.isFinite && line.ascent > 0)
        #expect(NSMaxRange(line.range) <= attributed.length)
    }
}

@Test func verbatimLayoutRetainsCodeIndentation() {
    let style = Typography()
    let source = "struct A {\n    let value = 1\n}\n"
    let attributed = style.attributed([InlineRun(source)], code: true)
    let layout = ParagraphTypesetter.layout(attributed, width: 500, fontSize: 16, alignment: .leading, verbatim: true)
    let ns = source as NSString
    #expect(layout.lines.count == 3)
    #expect(ns.substring(with: layout.lines[1].range).hasPrefix("    let"))
}

@Test func indentOnlyNarrowsFirstLine() {
    let source = "aaa bb cc ddd"
    let ns = source as NSString
    let lines = ParagraphBreaker.ranges(in: source, width: 9, alignment: .leading, firstLineIndent: 4) {
        Double($0.length)
    }
    #expect(ns.substring(with: lines[0]) == "aaa")
    #expect(lines.dropFirst().contains { $0.length > 5 })
}

@Test func blankVerbatimLineDoesNotDrawRemainingDocument() {
    let style = Typography()
    let attributed = style.attributed([InlineRun("\ncontent\n")], code: true)
    let layout = ParagraphTypesetter.layout(attributed, width: 500, fontSize: 16, alignment: .leading, verbatim: true)
    #expect(layout.lines.count == 2)
    #expect(layout.lines[0].range.length == 0)
    #expect(CTLineGetStringRange(layout.lines[0].line).length == 0)
    #expect(layout.lines[0].width == 0)
    #expect((attributed.string as NSString).substring(with: layout.lines[1].range) == "content")
}
