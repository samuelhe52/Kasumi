import Foundation
import Testing

// ImportDocumentNaming.swift links to the actual app source.
@Suite struct ImportDocumentNamingTests {
    @Test func extractsLeadingH1AcrossMarkdownForms() {
        #expect(ImportDocumentNaming.leadingHeadingTitle(in: "# Hello **World** `v2`\n\nBody") == "Hello World v2")
        #expect(ImportDocumentNaming.leadingHeadingTitle(in: "Setext Title\n============\n\nBody") == "Setext Title")
        #expect(
            ImportDocumentNaming.leadingHeadingTitle(in: "<div align=\"center\">\n<h1>Kasumi</h1>\n</div>\n")
                == "Kasumi")
        #expect(
            ImportDocumentNaming.leadingHeadingTitle(
                in: "\u{FEFF}---\ntitle: Front\nlang: en\n---\n\n![Logo](logo.png)\n\n# Real Heading\n")
                == "Real Heading")
        #expect(
            ImportDocumentNaming.leadingHeadingTitle(in: String(repeating: "\r\n", count: 9) + "# CRLF Title\r\n")
                == "CRLF Title")
        // Frontmatter is detected once; a later `---` pair is body content.
        #expect(
            ImportDocumentNaming.leadingHeadingTitle(in: "---\ntitle: x\n---\n---\n# After Rule\n---\n")
                == "After Rule")
        let reference =
            "# [My Title][ref]\n\n" + String(repeating: "line\n", count: 40) + "\n[ref]: https://a.example\n"
        #expect(ImportDocumentNaming.leadingHeadingTitle(in: reference) == "My Title")
    }

    @Test func ignoresNonH1CodeBlocksAndDistantHeadings() {
        #expect(ImportDocumentNaming.leadingHeadingTitle(in: "## Only H2\n\nBody") == nil)
        #expect(ImportDocumentNaming.leadingHeadingTitle(in: "```python\n# not a heading\nx = 1\n```\n") == nil)
        let distant = String(repeating: "Line of prose\n", count: 12) + "# Appendix\n"
        #expect(ImportDocumentNaming.leadingHeadingTitle(in: distant) == nil)
        #expect(
            ImportDocumentNaming.leadingHeadingTitle(in: String(repeating: "Prose\r\n", count: 10) + "# Too Far\r\n")
                == nil)
        // The byte limit cuts `===notes` to `===`; the partial line must not
        // turn the paragraph above into a Setext heading.
        let cutoff = String(repeating: "w", count: 8_188) + "\n===notes\n"
        #expect(ImportDocumentNaming.leadingHeadingTitle(in: cutoff) == nil)
        #expect(ImportDocumentNaming.leadingHeadingTitle(in: "#   / : ...\n") == nil)
    }

    @Test func sanitizesAndTruncatesHeadingNames() {
        #expect(
            ImportDocumentNaming.sanitizedFilenameStem("Part 1: A/B\\C\tNotes.") == "Part 1 - A-B-C Notes")
        #expect(ImportDocumentNaming.sanitizedFilenameStem("... .env Guide ...") == "env Guide")
        #expect(ImportDocumentNaming.sanitizedFilenameStem("A/\u{0301}B") == "A-\u{0301}B")
        #expect(ImportDocumentNaming.sanitizedFilenameStem("👩\u{200D}💻 Guide") == "👩\u{200D}💻 Guide")
        #expect(ImportDocumentNaming.sanitizedFilenameStem("Report\u{202E}fdp.exe\u{0007}") == "Reportfdp.exe")
        let longEnglish =
            "An In-Depth Guide to Building High-Performance Markdown Rendering Engines on Apple Platforms Today"
        let truncated = ImportDocumentNaming.sanitizedFilenameStem(longEnglish)
        #expect(truncated == "An In-Depth Guide to Building High-Performance Markdown Rendering Engines on")
        #expect((truncated?.count ?? 0) <= 80)

        let longCJK = String(repeating: "霞", count: 100)
        let truncatedCJK = ImportDocumentNaming.sanitizedFilenameStem(longCJK)
        #expect(truncatedCJK != nil)
        #expect((truncatedCJK?.utf8.count ?? 0) <= 200)
    }

    @Test func pastedAndDownloadNamesUseHeadingWithFallback() {
        let fixedDate = Date(timeIntervalSince1970: 0)
        #expect(ImportDocumentNaming.pastedName(for: "# Release Notes\n\nChanges", at: fixedDate) == "Release Notes.md")
        #expect(
            ImportDocumentNaming.pastedName(for: "Plain paragraph only", at: fixedDate).hasPrefix("Pasted Text "))
        #expect(
            ImportDocumentNaming.pastedName(for: "# notes.txt\n", at: fixedDate) == "notes.txt.md")

        let mdBytes = Data("# Fetched Guide\n\nHello".utf8)
        let plainBytes = Data("No heading here".utf8)
        #expect(
            ImportDocumentNaming.downloadName(
                for: URL(string: "https://example.com/docs/README.md")!, data: mdBytes) == "README.md")
        #expect(
            ImportDocumentNaming.downloadName(
                for: URL(string: "https://example.com/notes.txt")!, data: mdBytes) == "notes.txt")
        #expect(
            ImportDocumentNaming.downloadName(
                for: URL(string: "https://example.com/")!, data: mdBytes) == "Fetched Guide.md")
        #expect(
            ImportDocumentNaming.downloadName(
                for: URL(string: "https://example.com")!, data: mdBytes) == "Fetched Guide.md")
        #expect(
            ImportDocumentNaming.downloadName(
                for: URL(string: "https://example.com/")!, data: plainBytes) == "example.com.md")
        #expect(
            ImportDocumentNaming.downloadName(
                for: URL(string: "https://example.com/guides/")!, data: mdBytes) == "Fetched Guide.md")
        #expect(
            ImportDocumentNaming.downloadName(
                for: URL(string: "https://example.com/guides/")!, data: plainBytes) == "guides.md")
    }
}
