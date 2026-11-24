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
        for (plain, expected) in [
            ("    Example", "##     Example"), ("- item\n\n    Example", "- item\n\n    ## Example")
        ] {
            let end = NSRange(location: plain.utf16.count, length: 0)
            (next, _) = run(plain, end) { SourceFormatting.heading(in: $0, selection: $1, level: 2) }
            #expect(next == expected)
        }
        (next, _) = run("#tag", NSRange(location: 0, length: 0)) { SourceFormatting.heading(in: $0, selection: $1) }
        #expect(next == "# #tag")
        for (marked, expected) in [("  # Title", "  ## Title"), ("#\tTitle", "## Title")] {
            (next, _) = run(marked, NSRange(location: 5, length: 0)) {
                SourceFormatting.heading(in: $0, selection: $1, level: 2)
            }
            #expect(next == expected)
        }
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
        (next, selection) = run("a\r\nb", NSRange(location: 0, length: 4)) {
            SourceFormatting.code(in: $0, selection: $1)
        }
        #expect(next == "```\r\na\r\nb\r\n```" && selection == NSRange(location: 5, length: 4))
        (next, selection) = run("x", NSRange(location: 1, length: 0)) { SourceFormatting.code(in: $0, selection: $1) }
        #expect(next == "x``" && selection == NSRange(location: 2, length: 0))
    }

    @Test func boldAndItalicToggleWithUTF16Selections() {
        let selected = NSRange(location: 2, length: 2)
        let (bold, boldRange) = run("a 😀 z", selected) { SourceFormatting.bold(in: $0, selection: $1) }
        #expect(bold == "a **😀** z" && boldRange == NSRange(location: 4, length: 2))
        let (both, bothRange) = run(bold, boldRange) { SourceFormatting.italic(in: $0, selection: $1) }
        #expect(both == "a ***😀*** z")
        let (unitalic, unitalicRange) = run(both, bothRange) { SourceFormatting.italic(in: $0, selection: $1) }
        #expect(unitalic == bold && unitalicRange == boldRange)
        let (unbold, unboldRange) = run(unitalic, unitalicRange) { SourceFormatting.bold(in: $0, selection: $1) }
        #expect(unbold == "a 😀 z" && unboldRange == selected)
        let (unwrapped, innerRange) = run("a _word_", NSRange(location: 2, length: 6)) {
            SourceFormatting.italic(in: $0, selection: $1)
        }
        #expect(unwrapped == "a word" && innerRange == NSRange(location: 2, length: 4))
        let (inserted, caret) = run("a", NSRange(location: 1, length: 0)) {
            SourceFormatting.bold(in: $0, selection: $1)
        }
        #expect(inserted == "a****" && caret.location == 3)
        let (removed, originalCaret) = run(inserted, caret) { SourceFormatting.bold(in: $0, selection: $1) }
        #expect(removed == "a" && originalCaret.location == 1)
    }

    @Test func emphasisOnlyUnwrapsOneEnclosingSpan() {
        let text = "**one** and **two**"
        let all = NSRange(location: 0, length: 19)
        let (both, range) = run(text, all) { SourceFormatting.bold(in: $0, selection: $1) }
        #expect(both == "****one** and **two****" && range == NSRange(location: 2, length: 19))
        #expect(run(both, range) { SourceFormatting.bold(in: $0, selection: $1) }.0 == text)
        let between = run(text, NSRange(location: 7, length: 5)) { SourceFormatting.bold(in: $0, selection: $1) }.0
        #expect(between == "**one** **and** **two**")
        let names = run("a snake_case_name", NSRange(location: 8, length: 4)) {
            SourceFormatting.italic(in: $0, selection: $1)
        }.0
        #expect(names == "a snake_*case*_name")
        // Not a Markdown span, but still the pair Bold just inserted.
        let (quoted, inner) = run("中“文”字", NSRange(location: 1, length: 3)) {
            SourceFormatting.bold(in: $0, selection: $1)
        }
        #expect(quoted == "中**“文”**字")
        #expect(run(quoted, inner) { SourceFormatting.bold(in: $0, selection: $1) }.0 == "中“文”字")
        let code = run("**a `**` b**", NSRange(location: 0, length: 12)) {
            SourceFormatting.bold(in: $0, selection: $1)
        }.0
        #expect(code == "a `**` b")
        for literal in ["`**x**`", "~~~\n**x**", "text\n\n    code\n    **x**", "> ~~~\n> **x**", "$**x**$"] {
            let location = (literal as NSString).range(of: "x", options: .backwards).location
            let edit = SourceFormatting.bold(in: literal, selection: NSRange(location: location, length: 1))
            #expect(edit.applied(to: literal).contains("****x****"))
        }
        for prose in ["text\n    **x**", "1. item\n\n    **x**"] {
            let location = (prose as NSString).range(of: "x", options: .backwards).location
            let edit = SourceFormatting.bold(in: prose, selection: NSRange(location: location, length: 1))
            #expect(!edit.applied(to: prose).contains("*"))
        }
    }

    @Test func emphasisKeepsWhitespaceOutsideTheMarkers() {
        let (bold, range) = run("word next", NSRange(location: 0, length: 5)) {
            SourceFormatting.bold(in: $0, selection: $1)
        }
        #expect(bold == "**word** next" && range == NSRange(location: 2, length: 4))
        let (plain, _) = run("a *word*\nb", NSRange(location: 1, length: 8)) {
            SourceFormatting.italic(in: $0, selection: $1)
        }
        #expect(plain == "a word\nb")
        let spaces = run("a  b", NSRange(location: 1, length: 2)) { SourceFormatting.bold(in: $0, selection: $1) }.0
        #expect(spaces == "a  b")
    }

    @Test func quoteTogglesEverySelectedLine() {
        let text = "one\n\ntwo\nnext"
        let lines = NSRange(location: 0, length: 9)  // "one\n\ntwo\n": ends at a line break
        var (next, selection) = run(text, lines) { SourceFormatting.quote(in: $0, selection: $1) }
        #expect(next == "> one\n>\n> two\nnext")
        (next, _) = run(next, selection) { SourceFormatting.quote(in: $0, selection: $1) }
        #expect(next == text)
        let windows = "one\r\n\r\ntwo\r\nnext"
        (next, selection) = run(windows, NSRange(location: 0, length: 12)) {
            SourceFormatting.quote(in: $0, selection: $1)
        }
        #expect(next == "> one\r\n>\r\n> two\r\nnext")
        #expect(run(next, selection) { SourceFormatting.quote(in: $0, selection: $1) }.0 == windows)
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
