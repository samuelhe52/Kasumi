import CoreText
import Foundation
import PDFKit
import Testing

@testable import KasumiMarkdown

@Suite struct PunctuationPolicyTests {
    private func typography(_ strategy: String) -> Typography {
        Typography().applying(ProfileValues([
            .punctStrategy: .string(strategy), .hanFamily: .string("PingFang SC"), .bodyAlign: .string("left")
        ]))
    }

    @Test func foldingUsesLocalHanContextAndMatchedParentheses() {
        let cases: [(String, String)] = [
            ("汉,字.句;子:好!吗?汉(API)字", "汉，字。句；子：好！吗？汉（API）字"),
            ("漢,字", "漢，字"), ("abc,def", "abc,def"), ("汉 abc,def", "汉 abc,def"),
            ("汉, abc", "汉， abc"), ("汉 3.14, 1,000 12:30 字", "汉 3.14, 1,000 12:30 字"),
            ("汉(abc) 汉(字) def", "汉（abc） 汉（字） def"), ("汉(abc", "汉(abc"),
            ("汉(👩‍💻)字", "汉（👩‍💻）字"),
            ("汉!!!字", "汉！！！字"), ("日本語,です", "日本語,です"),
            ("한글,문장", "한글,문장"), ("汉,字 カナ", "汉,字 カナ"),
            ("中文，原样。", "中文，原样。"), ("👩🏽‍💻 汉,字 e\u{301}", "👩🏽‍💻 汉，字 e\u{301}")
        ]
        for (source, expected) in cases {
            let text = typography("fold").attributed([InlineRun(source)])
            #expect(text.string == expected)
            #expect(DocumentTextMap(text).string == source)
            #expect(DocumentTextMap(text).substring(in: NSRange(location: 0, length: text.length)) == source)
        }
    }

    @Test func protectedRunsAndStyledBoundariesKeepTheirSourceAndMetadata() throws {
        let document = DocumentParser.parse("汉**字,!文**字 `汉,字` $x,y$ [汉,字](https://example.com) ![汉,字](missing.png) 日本語`かな`汉,字")
        let text = typography("fold").attributed(document.blocks[0].runs)
        #expect(text.string.hasPrefix("汉字，！文字 汉,字"))
        let semantic = DocumentTextMap(text)
        #expect(semantic.string.contains("汉字,!文字 汉,字 x,y 汉,字 汉,字"))
        #expect(semantic.string.hasSuffix("日本語かな汉,字"))
        let comma = (text.string as NSString).range(of: "，")
        let metadata = try #require(text.attribute(.kasumiParagraphRun, at: comma.location, effectiveRange: nil) as? ParagraphRunStyle)
        #expect(metadata.flags & 1 == 1)
        let linked = (text.string as NSString).range(of: "汉,字", options: .backwards)
        #expect(linked.location != NSNotFound)
        // A protected run is a context barrier, not punctuation's Han evidence.
        let runs = [InlineRun("汉", traits: [.code]), InlineRun(", word")]
        #expect(typography("fold").attributed(runs).string == "汉, word")
        #expect(typography("fold").attributed([InlineRun("汉,字")], code: true).string == "汉,字")
    }

    @Test func spacingAddsMeasuredEighthEmWithoutAddingSemanticCharacters() throws {
        for (source, gaps) in [("汉,字", 2), ("汉, 字", 1), ("汉 ,字", 1), ("汉 , 字", 0), ("汉?!字", 2)] {
            let faithful = typography("faithful").attributed([InlineRun(source)])
            let spaced = typography("spacing").attributed([InlineRun(source)])
            #expect(spaced.string == source)
            #expect(DocumentTextMap(spaced).string == source)
            let before = ParagraphShaper.shape(faithful, fallbackSize: 16)
            let after = ParagraphShaper.shape(spaced, fallbackSize: 16)
            let delta = after.clusters.reduce(0) { $0 + $1.advance } - before.clusters.reduce(0) { $0 + $1.advance }
            #expect(abs(delta - Float(gaps) * 2) < 0.01, "Measured padding: \(source), delta \(delta)")
            let plain = ParagraphTypesetter.layout(faithful, width: 300, fontSize: 16, alignment: .leading)
            let padded = ParagraphTypesetter.layout(spaced, width: 300, fontSize: 16, alignment: .leading)
            let plainLine = try #require(plain.lines.first)
            let paddedLine = try #require(padded.lines.first)
            #expect(abs(paddedLine.width - plainLine.width - CGFloat(gaps) * 2) < 0.02)
        }
    }

    @Test func publicSearchSelectionCaretTablesAndPDFUseTheSamePolicy() throws {
        let source = "# 中文,标题\n\n汉,!字 👩‍💻 `汉,字` [汉,字](https://example.com)\n\n| 中文,列 | 数值 |\n| --- | --- |\n| 汉,字 | 3.14 |\n\n```text\n汉,字\n```"
        let document = MarkdownDocument(markdown: source)
        let baseline = RenderedDocument(document, width: 300, style: RenderStyle())
        let original = baseline.text(in: baseline.documentRange)
        for mode in ["fold", "spacing"] {
            let preset = try TypographyPreset(id: mode, name: mode, toml: "[profile]\npunct_strategy='\(mode)'\nhan_family='PingFang SC'")
            let style = RenderStyle(preset: preset)
            for width: CGFloat in [160, 300] {
                let rendered = RenderedDocument(document, width: width, style: style)
                #expect(rendered.text(in: rendered.documentRange) == original)
                #expect(rendered.ranges(matching: "汉,字").count == baseline.ranges(matching: "汉,字").count)
                #expect(rendered.ranges(matching: "汉，字").isEmpty)
                let foundLink = rendered.ranges(matching: "汉,字").flatMap { rendered.selectionRects(for: $0) }.contains { rect in
                    rendered.link(at: CGPoint(x: rect.midX, y: rect.midY)) == URL(string: "https://example.com")
                }
                #expect(foundLink, "Protected link labels must retain hit testing after display transformations")
                let range = try #require(rendered.ranges(matching: "汉,!字").first)
                #expect(rendered.text(in: range) == "汉,!字")
                #expect(!rendered.selectionRects(for: range).isEmpty)
                for offset in 0...4 {
                    let position = try #require(rendered.position(from: range.lowerBound, offset: offset))
                    let caret = rendered.caretRect(for: position)
                    #expect(rendered.position(closestTo: CGPoint(x: caret.minX, y: caret.midY)) == position)
                }
                #expect(rendered.codeBlocks.first?.source == "汉,字\n")
            }
            let pdf = try #require(PDFDocument(data: DocumentExport.pdf(document, style: style)))
            #expect((pdf.string ?? "").contains(mode == "fold" ? "，标题" : ",标题"))
        }
    }

    @Test func cliPunctuationFlagOverridesProfileInEitherOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.md")
        let profile = directory.appendingPathComponent("profile.toml")
        let output = directory.appendingPathComponent("output.pdf")
        try "汉,字".write(to: input, atomically: true, encoding: .utf8)
        try "[profile]\npunct_strategy='faithful'\nhan_family='PingFang SC'".write(to: profile, atomically: true, encoding: .utf8)
        for flags in [["--punct-strategy", "fold", "--profile", profile.path], ["--profile", profile.path, "--punct-strategy", "fold"]] {
            _ = try await RenderCommand.run(["KasumiRender", input.path, output.path] + flags)
            let pdf = try #require(PDFDocument(url: output))
            #expect((pdf.string ?? "").filter { !$0.isWhitespace }.contains("汉，字"))
        }
        let previous = try Data(contentsOf: output)
        await #expect(throws: (any Error).self) {
            try await RenderCommand.run(["KasumiRender", input.path, output.path, "--punct-strategy", "unknown"])
        }
        #expect(try Data(contentsOf: output) == previous)
    }
}
