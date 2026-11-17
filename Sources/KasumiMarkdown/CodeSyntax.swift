import CSyntax
import Foundation

/// Theme-independent spans retained by the parsed document, so reflow and
/// export reuse tokenization. Only foreground paint changes, never source text,
/// fonts, or the paragraph engine's run metadata.
enum CodeSyntax {
    enum Role: UInt32, Sendable {
        case keyword = 1, string, comment, literal, type

        var themeKey: String {
            switch self {
            case .keyword: "keyword"
            case .string: "string"
            case .comment: "comment"
            case .literal: "literal"
            case .type: "type"
            }
        }
    }

    struct Token: Sendable, Equatable {
        let range: NSRange
        let role: Role
    }

    static func tokens(in source: String, language: String?) -> [Token] {
        // Match native resource limits before copying a potentially large block.
        guard let language, !language.isEmpty, language.utf8.count <= 128,
            !source.isEmpty, source.utf8.count <= 256 * 1024
        else { return [] }
        let bytes = Array(source.utf8)
        let tag = Array(language.utf8)
        return bytes.withUnsafeBufferPointer { input in
            tag.withUnsafeBufferPointer { language in
                let required = kasumi_syntax_highlight(
                    input.baseAddress, input.count, language.baseAddress, language.count, nil, 0)
                guard let count = Int(exactly: required), count > 0, count <= input.count else { return [] }
                var output = [KasumiSyntaxSpan](repeating: KasumiSyntaxSpan(), count: count)
                let written = output.withUnsafeMutableBufferPointer {
                    kasumi_syntax_highlight(
                        input.baseAddress, input.count, language.baseAddress, language.count, $0.baseAddress, $0.count)
                }
                guard Int(exactly: written) == count else { return [] }
                let length = source.utf16.count
                var previousEnd = 0
                var tokens: [Token] = []
                for span in output {
                    guard let role = Role(rawValue: span.role), span.location >= previousEnd,
                        span.length > 0, span.location <= length, span.length <= length - span.location
                    else { return [] }
                    tokens.append(Token(range: NSRange(location: span.location, length: span.length), role: role))
                    previousEnd = span.location + span.length
                }
                return tokens
            }
        }
    }

    static func applying(_ tokens: [Token], to text: NSAttributedString, theme: DocumentTheme) -> NSAttributedString {
        guard !tokens.isEmpty else { return text }
        let result = NSMutableAttributedString(attributedString: text)
        for token in tokens {
            if let color = theme.syntax[token.role.themeKey]?.nsColor {
                result.addAttribute(.foregroundColor, value: color, range: token.range)
            }
        }
        return result
    }
}
