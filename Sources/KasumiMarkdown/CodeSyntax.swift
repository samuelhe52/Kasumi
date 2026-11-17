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
        var capture = Capture(length: source.utf16.count)
        return bytes.withUnsafeBufferPointer { input in
            tag.withUnsafeBufferPointer { language in
                let written = withUnsafeMutablePointer(to: &capture) { context in
                    kasumi_syntax_highlight_visit(
                        input.baseAddress, input.count, language.baseAddress, language.count,
                        { spans, count, context in
                            guard let context else { return }
                            context.assumingMemoryBound(to: Capture.self).pointee.copy(spans, count: count)
                        }, context)
                }
                guard capture.valid, Int(exactly: written) == capture.tokens.count else { return [] }
                return capture.tokens
            }
        }
    }

    /// Stack-scoped callback context. Only copied Swift tokens escape the native
    /// call; the borrowed native span buffer is never retained.
    private struct Capture {
        let length: Int
        var tokens: [Token] = []
        var valid = false
        private var visited = false

        init(length: Int) { self.length = length }

        mutating func copy(_ spans: UnsafePointer<KasumiSyntaxSpan>?, count: Int) {
            guard !visited else { valid = false; return }
            visited = true
            guard count >= 0, count <= length, count == 0 || spans != nil else { return }
            tokens.reserveCapacity(count)
            var previousEnd = 0
            for span in UnsafeBufferPointer(start: spans, count: count) {
                guard let role = Role(rawValue: span.role), span.location >= previousEnd,
                    span.length > 0, span.location <= length, span.length <= length - span.location
                else { return }
                tokens.append(Token(range: NSRange(location: span.location, length: span.length), role: role))
                previousEnd = span.location + span.length
            }
            valid = true
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
