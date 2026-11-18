import CoreGraphics
import Foundation
import Testing

@testable import KasumiMarkdown

@Suite struct HTMLTests {
    @Test func inlineTagsComposeWithMarkdownAndEndWithTheirContainer() throws {
        let document = DocumentParser.parse(
            """
            Press <kbd>⌘K</kbd> to <mark>search</mark>.<BR>H<sub>2</sub>O and <u>x<sup>2</sup></u>.
            <b>*nested*</b> <samp>sample</samp> <cite>citation</cite> <strike>gone</strike>
            <span style="color: red">plain</span> <a href="/?a=1&amp;b=2">link</a> <strong>open

            Next paragraph.
            """)
        let runs = document.blocks[0].runs
        func run(_ text: String) throws -> InlineRun { try #require(runs.first { $0.text == text }) }
        #expect(try run("⌘K").traits == [.code])
        #expect(try run("search").traits == [.highlight])
        #expect(try run("\n").traits.isEmpty)
        #expect(runs.filter { $0.text == "2" }.map(\.traits) == [[.subscript], [.superscript, .underline]])
        #expect(try run("nested").traits == [.strong, .emphasis])
        #expect(try run("sample").traits == [.code])
        #expect(try run("citation").traits == [.emphasis])
        #expect(try run("gone").traits == [.strikethrough])
        #expect(try run("plain").traits.isEmpty)
        #expect(try run("link").destination == "/?a=1&b=2")
        #expect(try run("open").traits == [.strong])
        #expect(document.blocks[1].runs[0].traits.isEmpty)
    }

    @Test func blocksKeepAlignmentDetailsHeadingsAndSourceLines() {
        let document = DocumentParser.parse(
            """
            <center>
            <h2>Getting &amp; started</h2>
            <details>
            <summary>Install <i>today</i></summary>

            Run `make app`.

            <p align=right>Right-aligned</p>

            </details>
            </center>

            ## Left as usual

            <hr>
            """)
        #expect(document.blocks.map(\.kind) == [.heading, .paragraph, .paragraph, .paragraph, .heading, .rule])
        #expect(document.headings.map(\.text) == ["Getting & started", "Left as usual"])
        #expect(document.headings.map(\.level) == [2, 2])
        #expect(document.blocks.map(\.alignment) == [.centered, .centered, .centered, .trailing, nil, nil])
        #expect(document.blocks[1].text == "▾ Install today")
        #expect(document.blocks[1].runs.allSatisfy { $0.traits.contains(.strong) })
        #expect(document.blocks[2].runs.contains { $0.text == "make app" && $0.traits == [.code] })
        #expect(document.blocks[2].sourceLines == 6...6)
    }

    @Test func unsupportedContentFallsBackToTextAndDroppedMarkupStaysHidden() {
        let document = DocumentParser.parse(
            """
            <!DOCTYPE html>
            <!-- invisible -->
            <table><tr><th>Platform</th><th>Version</th></tr><tr><td>iOS</td><td>17</td></tr></table>
            <script>if (x<y) { doSomething(); }</script>
            <style>.hidden { font-size: 0 }</style>
            <iframe>frame</iframe><object>object</object><embed src="ignored">
            <template>template</template><noscript>noscript</noscript>
            <svg><text>SVG</text></svg><math><mi>math</mi></math>
            <aside>Keep &copy; &#x1f642; &NotEqualTilde; <span>this</span></aside>

            Inline <script>hidden</script>and <svg><text>hidden</text></svg>visible.

            <div><template>

            **Hidden Markdown**

            </template></div>

            Visible again.
            """)
        #expect(
            document.blocks.map(\.text) == [
                "Platform\nVersion\niOS\n17\nKeep © 🙂 ≂̸ this", "Inline and visible.", "Visible again."
            ])
    }

    @Test func sizesAndLinksReachLayoutForHTMLImages() throws {
        let baseURL = testRepositoryURL.appendingPathComponent("fixtures")
        let document = DocumentParser.parse(
            """
            <p align=center><a href="https://example.com"><picture><source srcset="missing.png"><img SRC=images/tiny.png ALT="A &amp; B" width="64px"></picture></a></p>

            Inline <img src=images/tiny.png height=30 alt=Second>
            """, baseURL: baseURL)
        let image = try #require(document.blocks[0].runs.first)
        #expect(image.imageSource == "images/tiny.png")
        #expect(image.text == "A & B")
        #expect(image.destination == "https://example.com")
        #expect(image.imageWidth == 64 && image.imageHeight == nil)
        let layout = DocumentTypesetter.layout(document, width: 400, style: Typography())
        #expect(layout.imageBounds.count == 2)
        #expect(layout.imageBounds.first?.midX == 200)
        #expect(layout.imageBounds.first?.size == CGSize(width: 64, height: 48))
        #expect(layout.imageBounds.last?.size == CGSize(width: 40, height: 30))
        let original = try #require(DocumentImageStore.shared.image(for: "images/tiny.png", baseURL: baseURL))
        #expect(original.fitted(to: 40, width: 80, height: 20) == CGSize(width: 40, height: 10))
    }

    @Test func scriptAndUnderlineTraitsReachTypography() throws {
        let style = Typography()
        let text = style.attributed([
            InlineRun("a"),
            InlineRun("b", traits: [.superscript, .underline]),
            InlineRun("c", traits: [.subscript]),
            InlineRun("1", traits: [.footnote])
        ])
        func offset(_ index: Int) -> Double? {
            text.attribute(.baselineOffset, at: index, effectiveRange: nil) as? Double
        }
        func font(_ index: Int) throws -> PlatformFont {
            try #require(text.attribute(.font, at: index, effectiveRange: nil) as? PlatformFont)
        }
        #expect(try font(1).pointSize == font(3).pointSize)
        #expect(try font(2).pointSize == font(1).pointSize)
        #expect(try font(1).pointSize < font(0).pointSize)
        #expect(offset(1) == offset(3) && offset(1) == style.size * style.superscriptShift)
        #expect(offset(2) == -style.size * 0.15)
        #expect(text.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int == 1)
        #expect(InlineRun("b", traits: [.superscript]).paragraphFlags == 0x200)
        #expect(InlineRun("c", traits: [.subscript]).paragraphFlags == 0x400)
    }
}
