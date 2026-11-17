import Foundation
import Testing

@testable import KasumiMarkdown

@Suite struct ReaderSearchTests {
    @Test func retainedOffsetsRecreateIndependentPositionsAcrossWidthsAndAttachmentMaps() throws {
        let math = MarkdownDocument(markdown: "Before $x_i$ after 中文 👩‍👩‍👧‍👦.")
        let plain = MarkdownDocument(plainText: "Before x_i after 中文 👩‍👩‍👧‍👦.")
        let style = RenderStyle(fontSize: 16, widthLimit: nil)
        let snapshots = [
            RenderedDocument(math, width: 320, style: style),
            RenderedDocument(math, width: 480, style: style),
            RenderedDocument(plain, width: 320, style: style)
        ]
        var search = ReaderSearchState()
        var previous: KasumiMarkdown.TextRange?
        for snapshot in snapshots {
            let text = snapshot.text(in: snapshot.documentRange)
            let offsets = search.ranges(in: text, matching: "x_i")
            #expect(offsets == [NSRange(location: 7, length: 3)])
            let start = try #require(
                snapshot.position(from: snapshot.documentRange.lowerBound, offset: offsets[0].location))
            let end = try #require(snapshot.position(from: start, offset: offsets[0].length))
            let range = TextRange(start, end)
            #expect(snapshot.text(in: range) == "x_i")
            #expect(!snapshot.selectionRects(for: range).isEmpty)
            if let previous { #expect(snapshot.selectionRects(for: previous).isEmpty) }
            previous = range
        }
        #expect(search.searchBuilds == 1 && search.wordBoundaryBuilds == 0)
        let text = snapshots[0].text(in: snapshots[0].documentRange)
        #expect(search.ranges(in: text, matching: "👩‍👩‍👧‍👦") == [NSRange(location: 20, length: 11)])
        #expect(search.ranges(in: text, matching: "not found").isEmpty)
        let builds = search.searchBuilds
        #expect(search.ranges(in: text, matching: "not found").isEmpty)
        #expect(search.searchBuilds == builds)
    }

    @Test func optionsAndTextInvalidateResultsWhileWordSegmentationSurvivesQueryChanges() {
        let text = "Café cafe CAFÉ cafeteria"
        var search = ReaderSearchState()
        #expect(search.ranges(in: text, matching: "cafe").count == 4)
        #expect(
            search.ranges(in: text, matching: "cafe", options: .init(comparison: [.diacriticInsensitive])).count == 2)
        #expect(search.ranges(in: text, matching: "cafe", options: .init(comparison: [.caseInsensitive])).count == 2)
        #expect(search.wordBoundaryBuilds == 0)
        #expect(search.ranges(in: text, matching: "cafe", options: .init(wordMatch: .fullWord)).count == 3)
        #expect(search.ranges(in: text, matching: "cafe", options: .init(wordMatch: .startsWith)).count == 4)
        #expect(search.ranges(in: text, matching: "afe", options: .init(wordMatch: .startsWith)).isEmpty)
        #expect(search.wordBoundaryBuilds == 1)
        #expect(search.ranges(in: text, matching: "", options: .init(wordMatch: .fullWord)).isEmpty)
        #expect(search.ranges(in: text + " cafe", matching: "cafe", options: .init(wordMatch: .fullWord)).count == 4)
        #expect(search.wordBoundaryBuilds == 2)
        #expect(search.ranges(in: "", matching: "cafe").isEmpty)
    }

    @Test func canonicallyEquivalentTextAndQueriesStillInvalidateUTF16Offsets() {
        let composed = "é target"
        let decomposed = "e\u{301} target"
        #expect(composed == decomposed)
        var search = ReaderSearchState()
        #expect(search.ranges(in: composed, matching: "target") == [NSRange(location: 2, length: 6)])
        #expect(search.ranges(in: decomposed, matching: "target") == [NSRange(location: 3, length: 6)])
        #expect(search.searchBuilds == 2)
        let text = "é e\u{301}"
        let literal = ReaderSearchState.Options(comparison: [.literal])
        #expect(search.ranges(in: text, matching: "é", options: literal) == [NSRange(location: 0, length: 1)])
        #expect(search.ranges(in: text, matching: "e\u{301}", options: literal) == [NSRange(location: 2, length: 2)])
        #expect(search.searchBuilds == 4)
    }

    @Test func cachedCJKWordResultsAgreeWithFoundationBoundaries() {
        let text = "中文阅读 中文测试 hello 👩‍👩‍👧‍👦"
        let ns = text as NSString
        var tokens: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .substringNotRequired])
        {
            _, range, _, _ in tokens.append(range)
        }
        var search = ReaderSearchState()
        for query in ["中文", "文", "hello", "中文"] {
            let expected = tokens.filter { ns.substring(with: $0) == query }
            #expect(search.ranges(in: text, matching: query, options: .init(wordMatch: .fullWord)) == expected)
        }
        #expect(search.wordBoundaryBuilds == 1)
    }
}
