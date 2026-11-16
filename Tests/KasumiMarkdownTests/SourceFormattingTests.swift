import Foundation
import Testing

// SourceFormatting.swift links to the actual app source.
@Suite struct SourceFormattingTests {
    private func run(_ text: String, _ selection: NSRange, _ command: (String, NSRange) -> SourceEdit)
        -> (String, NSRange)
    {
        let edit = command(text, selection)
        return (edit.applied(to: text), edit.selection)
    }

    @Test func headingCyclesTheCurrentLineAndKeepsTheCaret() {
        let text = "Intro\nTitle 😀 here\n"
        let caret = NSRange(location: 15, length: 0)  // after the emoji (two UTF-16 units)
        var (next, selection) = run(text, caret) { SourceFormatting.heading(in: $0, selection: $1) }
        #expect(next == "Intro\n# Title 😀 here\n" && selection.location == 17)
        (next, selection) = run(next, selection) { SourceFormatting.heading(in: $0, selection: $1) }
        #expect(next == "Intro\n## Title 😀 here\n" && selection.location == 18)
        (next, _) = run("###### Six", NSRange(location: 3, length: 0)) {
            SourceFormatting.heading(in: $0, selection: $1)
        }
        #expect(next == "Six")
        (next, _) = run("## Two", NSRange(location: 0, length: 0)) {
            SourceFormatting.heading(in: $0, selection: $1, level: 4)
        }
        #expect(next == "#### Two")
        (next, _) = run("#tag", NSRange(location: 0, length: 0)) { SourceFormatting.heading(in: $0, selection: $1) }
        #expect(next == "# #tag")
    }

    @Test func codeWrapsUnwrapsAndFencesSelections() {
        var (next, selection) = run("say hi", NSRange(location: 4, length: 2)) {
            SourceFormatting.code(in: $0, selection: $1)
        }
        #expect(next == "say `hi`" && selection == NSRange(location: 5, length: 2))
        (next, selection) = run(next, selection) { SourceFormatting.code(in: $0, selection: $1) }
        #expect(next == "say hi" && selection == NSRange(location: 4, length: 2))
        (next, selection) = run("a\nb", NSRange(location: 0, length: 3)) {
            SourceFormatting.code(in: $0, selection: $1)
        }
        #expect(next == "```\na\nb\n```" && selection == NSRange(location: 4, length: 3))
        (next, selection) = run("x", NSRange(location: 1, length: 0)) { SourceFormatting.code(in: $0, selection: $1) }
        #expect(next == "x``" && selection == NSRange(location: 2, length: 0))
    }

    @Test func quoteTogglesEverySelectedLine() {
        let text = "one\n\ntwo\nnext"
        let lines = NSRange(location: 0, length: 9)  // "one\n\ntwo\n": ends at a line break
        var (next, selection) = run(text, lines) { SourceFormatting.quote(in: $0, selection: $1) }
        #expect(next == "> one\n>\n> two\nnext")
        (next, _) = run(next, selection) { SourceFormatting.quote(in: $0, selection: $1) }
        #expect(next == text)
        (next, selection) = run("a\nline", NSRange(location: 4, length: 0)) {
            SourceFormatting.quote(in: $0, selection: $1)
        }
        #expect(next == "a\n> line" && selection.location == 6)
    }

    @Test func linkPlacesTheCaretInTheMissingPart() {
        var (next, selection) = run("see docs", NSRange(location: 4, length: 4)) {
            SourceFormatting.link(in: $0, selection: $1)
        }
        #expect(next == "see [docs]()" && selection.location == 11)
        (next, selection) = run("https://a.b", NSRange(location: 0, length: 11)) {
            SourceFormatting.link(in: $0, selection: $1)
        }
        #expect(next == "[](https://a.b)" && selection.location == 1)
        (next, selection) = run("", NSRange(location: 0, length: 0)) { SourceFormatting.link(in: $0, selection: $1) }
        #expect(next == "[]()" && selection.location == 1)
    }
}
