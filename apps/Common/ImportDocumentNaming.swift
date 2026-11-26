import Foundation
import KasumiMarkdown

/// Derives safe filenames for pasted text and URL downloads, using a leading
/// Markdown H1 heading when one appears near the top of the document.
enum ImportDocumentNaming {
    /// Maximum 1-based line (after frontmatter and leading blank lines) where
    /// an H1 still counts as near the top of the document.
    private static let maxHeadingLine = 10
    /// Bounded window parsed when searching for a leading heading.
    private static let parseLineLimit = 24
    private static let parseByteLimit = 8_192
    private static let maxFilenameCharacters = 80
    private static let maxFilenameBytes = 200

    static func pastedName(for text: String, at date: Date = .now) -> String {
        if let heading = leadingHeadingTitle(in: text) {
            return heading + ".md"
        }
        return timestampedPastedName(at: date)
    }

    static func downloadName(for url: URL, data: Data) -> String {
        let component = url.lastPathComponent
        let hasComponent = !component.isEmpty && component != "/" && component != "." && component != ".."
        if hasComponent, !url.hasDirectoryPath {
            return markdownName(component)
        }
        if let text = try? DocumentSource(data: data).text,
            let heading = leadingHeadingTitle(in: text)
        {
            return heading + ".md"
        }
        return markdownName(hasComponent ? component : url.host() ?? "Download")
    }

    /// Adds `.md` unless `name` already ends in a Markdown or text extension.
    static func markdownName(_ name: String) -> String {
        let extensions = ["md", "markdown", "mdown", "mkd", "txt", "text"]
        return extensions.contains((name as NSString).pathExtension.lowercased()) ? name : name + ".md"
    }

    /// Returns a filesystem-safe stem from the first H1 heading near the top of
    /// `text` (skipping optional YAML frontmatter and leading blank lines).
    static func leadingHeadingTitle(in text: String) -> String? {
        let body = bodyAfterFrontMatter(in: text)
        guard let start = firstNonBlankLine(in: text, from: body.startIndex) else { return nil }
        let end = windowEnd(in: text, from: start, maxLines: parseLineLimit, maxBytes: parseByteLimit)
        guard start < end else { return nil }
        // Parse from the original start so the parser sees the same frontmatter
        // (once) and reports lines in the original document.
        let prefix = String(text[..<end])
        let firstLine = lineNumber(of: start, in: text)
        guard let heading = firstH1(in: MarkdownDocument(markdown: prefix), firstLine: firstLine) else { return nil }
        if heading.contains("["),
            let definitions = referenceDefinitions(in: text[end...]),
            let resolved = firstH1(in: MarkdownDocument(markdown: prefix + "\n\n" + definitions), firstLine: firstLine)
        {
            return sanitizedFilenameStem(resolved)
        }
        return sanitizedFilenameStem(heading)
    }

    private static func firstH1(in document: MarkdownDocument, firstLine: Int) -> String? {
        for item in document.outline where item.level == 1 {
            guard let line = item.sourceLine, line - firstLine < maxHeadingLine else { return nil }
            if sanitizedFilenameStem(item.title) != nil { return item.title }
        }
        return nil
    }

    /// Cleans a heading into a safe single-component filename stem.
    static func sanitizedFilenameStem(_ raw: String) -> String? {
        var normalized = String.UnicodeScalarView()
        normalized.reserveCapacity(raw.unicodeScalars.count)
        for scalar in raw.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) || CharacterSet.whitespaces.contains(scalar) {
                normalized.append(" ")
            } else if scalar.properties.generalCategory != .control, !isBidiControl(scalar) {
                normalized.append(scalar)
            }
        }
        var stem = String(normalized)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        while stem.hasSuffix(":") { stem.removeLast() }
        stem = stem.replacingOccurrences(of: ": ", with: " - ")
        // Per scalar: a separator with a combining mark (`/\u{0301}`) is a
        // different Character, so string replacement would miss it.
        let separators: Set<Unicode.Scalar> = [":", "/", "\\"]
        stem = String(String.UnicodeScalarView(stem.unicodeScalars.map { separators.contains($0) ? "-" : $0 }))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        stem = trimBoundaryDotsAndSpaces(stem)
        guard hasSubstantiveCharacter(stem) else { return nil }
        stem = truncate(stem, maxCharacters: maxFilenameCharacters, maxBytes: maxFilenameBytes)
        stem = trimBoundaryDotsAndSpaces(stem)
        guard hasSubstantiveCharacter(stem) else { return nil }
        return stem
    }

    /// Embedding, override and isolate controls can disguise a filename's
    /// visible order. Joiners and other format characters stay.
    private static func isBidiControl(_ scalar: Unicode.Scalar) -> Bool {
        (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
    }

    private static func hasSubstantiveCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static func timestampedPastedName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Pasted Text \(formatter.string(from: date)).md"
    }

    /// Skips a leading YAML frontmatter envelope (`---` ... `---`/`...`) using
    /// the same bounds as `DocumentFrontMatter`.
    private static func bodyAfterFrontMatter(in source: String) -> Substring {
        var content = source[...]
        if content.hasPrefix("\u{FEFF}") { content = content.dropFirst() }
        guard content.hasPrefix("---") else { return content }

        let utf8 = content.utf8
        let limit = min(utf8.count, 65_536)
        var lineStart = utf8.startIndex
        var lineCount = 0
        var scanned = 0
        while lineStart < utf8.endIndex, scanned < limit, lineCount < 128 {
            var cursor = lineStart
            while cursor < utf8.endIndex, scanned < limit, utf8[cursor] != 10 {
                cursor = utf8.index(after: cursor)
                scanned += 1
            }
            let reachedNewline = cursor < utf8.endIndex && utf8[cursor] == 10
            guard reachedNewline || cursor == utf8.endIndex else { return content }
            let line = String(decoding: utf8[lineStart..<cursor], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let nextStart: String.UTF8View.Index
            if reachedNewline {
                nextStart = utf8.index(after: cursor)
                scanned += 1
            } else {
                nextStart = utf8.endIndex
            }
            if lineCount == 0 {
                guard line == "---" else { return content }
            } else if line == "---" || line == "..." {
                return content[nextStart...]
            }
            lineCount += 1
            lineStart = nextStart
        }
        return content
    }

    /// Start of the first line at or after `index` that isn't blank. Swift
    /// treats `\r\n` as one newline `Character`, so CRLF text works too.
    private static func firstNonBlankLine(in text: String, from index: String.Index) -> String.Index? {
        var lineStart = index
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(where: \.isNewline) ?? text.endIndex
            if !text[lineStart..<lineEnd].allSatisfy(\.isWhitespace) { return lineStart }
            guard lineEnd < text.endIndex else { return nil }
            lineStart = text.index(after: lineEnd)
        }
        return nil
    }

    /// End of a window starting at `start` with at most `maxLines` lines and
    /// `maxBytes` UTF-8 bytes. A window cut by the byte limit drops its partial
    /// last line, which could otherwise parse differently (`===notes` → `===`).
    private static func windowEnd(in text: String, from start: String.Index, maxLines: Int, maxBytes: Int)
        -> String.Index
    {
        var index = start
        var lastLineEnd = start
        var lines = 0
        var bytes = 0
        while index < text.endIndex, lines < maxLines {
            let next = text.index(after: index)
            bytes += text[index..<next].utf8.count
            if bytes > maxBytes { return lastLineEnd }
            if text[index].isNewline {
                lines += 1
                lastLineEnd = next
            }
            index = next
        }
        return index
    }

    /// One-based line of `index`, counting CRLF, CR and LF line breaks.
    private static func lineNumber(of index: String.Index, in text: String) -> Int {
        1 + text[..<index].reduce(0) { $1.isNewline ? $0 + 1 : $0 }
    }

    /// Link reference definition lines (`[label]: destination`) outside the
    /// parsed window, so a heading such as `# [Title][ref]` resolves as the
    /// reader shows it.
    private static func referenceDefinitions(in text: Substring) -> String? {
        var definitions: [Substring] = []
        for line in text.split(whereSeparator: \.isNewline) where line.utf8.count <= 2_048 {
            let content = line.drop { $0 == " " }
            guard line.count - content.count <= 3, content.first == "[",
                let close = content.firstIndex(of: "]"), close > content.index(after: content.startIndex),
                content[content.index(after: close)...].first == ":"
            else { continue }
            definitions.append(content)
            if definitions.count == 256 { break }
        }
        return definitions.isEmpty ? nil : definitions.joined(separator: "\n")
    }

    private static func trimBoundaryDotsAndSpaces(_ text: String) -> String {
        var view = text[...]
        while let first = view.first, first == "." || first.isWhitespace {
            view = view.dropFirst()
        }
        while let last = view.last, last == "." || last.isWhitespace {
            view = view.dropLast()
        }
        return String(view)
    }

    private static func truncate(_ text: String, maxCharacters: Int, maxBytes: Int) -> String {
        guard text.count > maxCharacters || text.utf8.count > maxBytes else { return text }
        var end = text.startIndex
        var chars = 0
        var bytes = 0
        while end < text.endIndex, chars < maxCharacters {
            let next = text.index(after: end)
            let stepBytes = text[end..<next].utf8.count
            if bytes + stepBytes > maxBytes { break }
            bytes += stepBytes
            chars += 1
            end = next
        }
        let slice = text[..<end]
        if end < text.endIndex, !text[end].isWhitespace,
            let space = slice.lastIndex(where: \.isWhitespace),
            slice.distance(from: slice.startIndex, to: space) >= chars / 2
        {
            return String(slice[..<space])
        }
        return String(slice)
    }
}
