import CoreText
import Foundation
import Testing

@testable import KasumiMarkdown

@Suite struct CodeSyntaxTests {
    @Test(arguments: [
        ("swift", "let message: String = \"hello\" // comment"),
        ("rust", "let message: String = \"hello\"; // comment"),
        ("python", "if True:\n    print(\"hello\") # comment"),
        ("javascript", "const message = \"hello\"; // comment"),
        ("typescript", "const message: string = \"hello\"; // comment"),
        ("json", "{\"message\": \"hello\", \"count\": 42}"),
        ("bash", "echo \"hello\" # comment"),
        ("yaml", "message: \"hello\" # comment"),
        ("toml", "message = \"hello\" # comment")
    ])
    func languagesProduceTokens(_ language: String, _ source: String) {
        let tokens = CodeSyntax.tokens(in: source, language: language)
        #expect(!tokens.isEmpty, "No highlighting for \(language)")
        #expect(tokens.contains { $0.role == .string })
    }

    @Test func aliasesAndPlainFallbacks() {
        let source = "if True:\n    print(\"hello\") # comment"
        let python = CodeSyntax.tokens(in: source, language: "python")
        for alias in ["py", "python3", "PYTHON", " Python ", "python title=sample"] {
            #expect(CodeSyntax.tokens(in: source, language: alias) == python)
        }
        for language: String? in [nil, "", "text", "txt", "plain", "plaintext", "none", "unknown-language"] {
            #expect(CodeSyntax.tokens(in: source, language: language).isEmpty)
        }
        let script = "echo \"hello\" # comment"
        for alias in ["sh", "shell", "zsh"] {
            #expect(CodeSyntax.tokens(in: script, language: alias) == CodeSyntax.tokens(in: script, language: "bash"))
        }
        #expect(CodeSyntax.tokens(in: "", language: "swift").isEmpty)
        #expect(CodeSyntax.tokens(in: String(repeating: "x", count: 16 * 1024 + 1), language: "swift").isEmpty)
        #expect(CodeSyntax.tokens(in: String(repeating: "// x\n", count: 60_000), language: "swift").isEmpty)
    }

    @Test func multilineStateUnicodeOffsetsAndIndependentBlocks() throws {
        let source = "/* 中文🙂\r\nlet hidden = 7; */\r\nlet text = \"e\u{301}👩‍💻\";\nlet count = 42;"
        let tokens = CodeSyntax.tokens(in: source, language: "rust")
        let ns = source as NSString
        func covered(_ text: String, by role: CodeSyntax.Role) -> Bool {
            let range = ns.range(of: text)
            return tokens.contains { $0.role == role && NSIntersectionRange($0.range, range) == range }
        }
        #expect(covered("let hidden = 7;", by: .comment))
        #expect(covered("e\u{301}👩‍💻", by: .string))
        #expect(covered("42", by: .literal))
        #expect(tokens.contains { $0.role == .keyword && ns.substring(with: $0.range).contains("let") })
        let document = DocumentParser.parse("```rust\n/* unclosed\n```\n\n```rust\nlet count = 42;\n```")
        #expect(document.blocks[0].syntaxTokens.contains { $0.role == .comment })
        #expect(document.blocks[1].syntaxTokens.contains { $0.role == .keyword })
        #expect(!document.blocks[1].syntaxTokens.contains { $0.role == .comment })
    }

    @Test func onlyLabeledCodeBlocksAreHighlighted() {
        let document = DocumentParser.parse(
            """
            `let value = 42;`

            ```rust
            let value = 42;
            ```

            ```
            let value = 42;
            ```

            ```unknown-language
            let value = 42;
            ```

                let value = 42;

            <div>literal HTML</div>

            ```mermaid
            graph LR
              A --> B
            ```
            """)
        #expect(document.blocks.filter { !$0.syntaxTokens.isEmpty }.count == 1)
        #expect(document.blocks.first { !$0.syntaxTokens.isEmpty }?.language == "rust")
        #expect(document.blocks.last?.kind == .diagram)
        #expect(document.blocks.last?.syntaxTokens.isEmpty == true)
    }

    private let code = "let message: String = \"hello world\";\n// reader code comment\nlet count: u32 = 12345;"

    @Test func themeChangesPreserveTextFontsMetadataAndLayout() throws {
        let document = DocumentParser.parse("```rust\n\(code)\n```")
        let tokens = try #require(document.blocks.first?.syntaxTokens)
        #expect(Set(tokens.map(\.role)) == Set([.keyword, .string, .comment, .literal, .type]))
        var plain = document
        plain.blocks[0].syntaxTokens = []
        for theme in DocumentThemeCatalog.themes {
            var style = Typography()
            style.dark = theme.dark
            if theme.dark { style.darkThemeID = theme.id } else { style.lightThemeID = theme.id }
            let colored = DocumentTypesetter.layout(document, width: 260, style: style)
            let uncolored = DocumentTypesetter.layout(plain, width: 260, style: style)
            #expect(colored.text.string == uncolored.text.string)
            #expect(colored.textMap.string == uncolored.textMap.string)
            #expect(colored.textMap.matches("hello world").count == 1)
            #expect(abs(colored.height - uncolored.height) < 0.001)
            #expect(
                colored.paragraphs[0].paragraph.lines.map(\.range)
                    == uncolored.paragraphs[0].paragraph.lines.map(\.range))
            for index in 0..<colored.text.length {
                let expectedFont = uncolored.text.attribute(.font, at: index, effectiveRange: nil) as? PlatformFont
                let actualFont = colored.text.attribute(.font, at: index, effectiveRange: nil) as? PlatformFont
                #expect(actualFont == expectedFont)
                #expect(
                    colored.text.attribute(.kasumiParagraphRun, at: index, effectiveRange: nil) != nil
                        || index == colored.text.length - 1)
            }
            for token in tokens {
                let color =
                    colored.text.attribute(.foregroundColor, at: token.range.location, effectiveRange: nil)
                    as? PlatformColor
                #expect(color == style.documentTheme.syntax[token.role.themeKey]?.nsColor)
            }
        }
    }

    @Test(arguments: ["one-light", "one-dark"])
    func syntaxColorsReachTheRaster(_ theme: String) throws {
        let document = DocumentParser.parse("```rust\n\(code)\n```")
        var style = Typography()
        style.dark = theme.hasSuffix("dark")
        if style.dark { style.darkThemeID = theme } else { style.lightThemeID = theme }
        #expect(style.documentTheme.id == theme)
        let width = 600
        let layout = DocumentTypesetter.layout(document, width: CGFloat(width), style: style)
        let height = Int(ceil(layout.height))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(style.paperColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        DocumentTypesetter.draw(layout, in: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for role: CodeSyntax.Role in [.keyword, .string, .comment, .literal, .type] {
            let color = try #require(style.documentTheme.syntax[role.themeKey]?.nsColor.kasumiSRGB)
            let rgb = [color.redComponent, color.greenComponent, color.blueComponent].map { Int(round($0 * 255)) }
            let count = stride(from: 0, to: width * height * 4, by: 4).filter { offset in
                (0..<3).allSatisfy { abs(Int(bytes[offset + $0]) - rgb[$0]) <= 3 }
            }.count
            #expect(count > 3, "Missing \(role) ink in \(theme)")
        }
    }
}
