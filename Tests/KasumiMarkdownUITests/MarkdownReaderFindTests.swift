import KasumiMarkdown
import Testing

@testable import KasumiMarkdownUI

@MainActor @Suite struct MarkdownReaderFindTests {
    @Test func searchBeforeLayoutWrapsAndKeepsCurrentMatchAcrossReflow() throws {
        let document = MarkdownDocument(markdown: "Café and cafe.\n\nAnother café.")
        let initial = RenderedDocument(document, width: 300, style: .init())
        let reflowed = RenderedDocument(document, width: 480, style: .init())
        var find = ProgrammaticFind()
        find.setQuery("CAFE", options: [], in: nil)
        find.install(initial)
        #expect(find.result.count == 3)
        #expect(find.result.currentIndex == 0)
        find.move(.previous)
        #expect(find.result.currentIndex == 2)

        let previous = try #require(find.ranges.last)
        find.install(reflowed)
        #expect(find.result.currentIndex == 2)
        let current = try #require(find.ranges.last)
        #expect(reflowed.text(in: current) == "café")
        #expect(reflowed.text(in: previous).isEmpty)
        find.move(.next)
        #expect(find.result.currentIndex == 0)
    }

    @Test func queryOptionsAndClearDoNotLeaveAnOldHighlight() {
        let document = RenderedDocument(MarkdownDocument(plainText: "Café cafe CAFÉ"), width: 300, style: .init())
        var find = ProgrammaticFind()
        find.setQuery("cafe", options: [], in: document)
        find.move(.previous)
        find.setQuery("cafe", options: [.caseSensitive, .diacriticSensitive], in: document)
        #expect(find.result.count == 1)
        #expect(find.result.currentIndex == 0)
        find.clear()
        find.install(document)
        #expect(find.result.count == 0)
        #expect(find.result.currentIndex == nil)
    }
}
