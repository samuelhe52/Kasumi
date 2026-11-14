import Foundation

public enum TXTParagraphMode: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic, line, blank, indent
    public var title: String {
        switch self { case .automatic: "Automatic"; case .line: "One per line"; case .blank: "Blank line"; case .indent: "Indent" }
    }
}

public struct PlainTextOptions: Codable, Equatable, Sendable {
    public var paragraphMode: TXTParagraphMode
    public var detectChapters: Bool
    public var parseAsMarkdown: Bool
    public init(paragraphMode: TXTParagraphMode = .automatic, detectChapters: Bool = true, parseAsMarkdown: Bool = false) {
        self.paragraphMode = paragraphMode; self.detectChapters = detectChapters; self.parseAsMarkdown = parseAsMarkdown
    }
}

enum PlainTextParser {
    private struct Line {
        let text: String
        let number: Int
        let indented: Bool
        let chapter: Int?
    }
    private static let edgeSpaces = CharacterSet(charactersIn: " \t\u{3000}")
    private static let terminalPunctuation = Set("!\"').?]’”…。》」』】！）？")

    static func resolvedParagraphMode(for source: String) -> TXTParagraphMode { automaticMode(lines(source)) }

    static func parse(_ source: String, options: PlainTextOptions = PlainTextOptions(), baseURL: URL? = nil) -> ParsedDocument {
        let input = lines(source)
        let mode = options.paragraphMode == .automatic ? automaticMode(input) : options.paragraphMode
        var blocks: [DocumentBlock] = []
        var parts: [Line] = []
        func flush() {
            guard let first = parts.first, let last = parts.last else { return }
            var text = first.text
            for line in parts.dropFirst() {
                if let a = text.last, let b = line.text.first, !(eastAsian(a) && eastAsian(b)) { text += " " }
                text += line.text
            }
            var block = DocumentBlock(id: blocks.count, kind: .paragraph, runs: [InlineRun(text)])
            block.sourceLines = first.number...last.number
            blocks.append(block); parts.removeAll(keepingCapacity: true)
        }
        for line in input {
            if line.text.isEmpty { flush(); continue }
            if options.detectChapters, let level = line.chapter {
                flush()
                var block = DocumentBlock(id: blocks.count, kind: .heading, runs: [InlineRun(line.text)], level: level)
                block.sourceLines = line.number...line.number
                blocks.append(block)
            } else {
                if mode == .line || (mode == .indent && line.indented) { flush() }
                parts.append(line)
            }
        }
        flush()
        if options.detectChapters, !blocks.contains(where: { $0.kind == .heading && $0.level == 1 }) {
            for index in blocks.indices where blocks[index].kind == .heading { blocks[index].level = 1 }
        }
        return ParsedDocument(blocks: blocks, baseURL: baseURL)
    }

    private static func lines(_ source: String) -> [Line] {
        // The native scanner recognizes CR, LF and CRLF, not Unicode paragraph
        // separators. Only ASCII space/tab and ideographic space are trimmed.
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n").enumerated().map { index, raw in
            let text = raw.trimmingCharacters(in: edgeSpaces)
            let scalars = Array(raw.unicodeScalars.prefix(2))
            let indented = scalars.first == "\t" || scalars.first == "\u{3000}" || (scalars.first == " " && scalars.count > 1 && [" ", "\t", "\u{3000}"].contains(scalars[1]))
            return Line(text: text, number: index + 1, indented: indented, chapter: chapterLevel(text))
        }
    }

    private static func automaticMode(_ lines: [Line]) -> TXTParagraphMode {
        let sample = Array(lines.lazy.filter { !$0.text.isEmpty && $0.chapter == nil }.prefix(400))
        guard !sample.isEmpty else { return .line }
        if Double(sample.filter(\.indented).count) / Double(sample.count) >= 0.6 { return .indent }
        if Double(sample.filter { $0.text.last.map { terminalPunctuation.contains($0) } ?? false }.count) / Double(sample.count) >= 0.7 { return .line }
        return .blank
    }

    private static func eastAsian(_ character: Character) -> Bool {
        ParagraphBreaker.isCJK(character) || character.unicodeScalars.contains { (0xFF00...0xFFEF).contains($0.value) }
    }

    private static func chapterLevel(_ text: String) -> Int? {
        let scalars = Array(text.unicodeScalars)
        let separators = CharacterSet(charactersIn: " ,.-:·—，．：\u{3000}、")
        if scalars.count <= 40 {
            if scalars.first == "第" {
                var index = 1
                while index < scalars.count, edgeSpaces.contains(scalars[index]) { index += 1 }
                let start = index
                let numerals = CharacterSet(charactersIn: "0123456789０１２３４５６７８９〇一七万三两九二五八六十千四百零")
                while index < scalars.count, numerals.contains(scalars[index]), index - start < 8 { index += 1 }
                let count = index - start
                while index < scalars.count, edgeSpaces.contains(scalars[index]) { index += 1 }
                if count > 0, count <= 8, index < scalars.count {
                    let unit = scalars[index]
                    let level = "卷部集".unicodeScalars.contains(unit) ? 1 : "章回节篇".unicodeScalars.contains(unit) ? 2 : nil
                    if let level, index + 1 == scalars.count || separators.contains(scalars[index + 1]) { return level }
                }
            }
            for prefix in ["序章", "序言", "前言", "楔子", "引子", "番外", "尾声", "尾聲", "后记", "後記", "终章", "終章", "序"] where text.hasPrefix(prefix) {
                let count = prefix.unicodeScalars.count
                if scalars.count == count || separators.contains(scalars[count]) { return 2 }
            }
        }
        if !scalars.isEmpty, scalars.count <= 60 {
            var end = 0
            while end < scalars.count, scalars[end].isASCII, CharacterSet.letters.contains(scalars[end]) { end += 1 }
            let word = String(String.UnicodeScalarView(scalars.prefix(end))).lowercased()
            let level: Int?
            switch word { case "part", "book": level = 1; case "chapter", "prologue", "epilogue": level = 2; default: level = nil }
            if let level {
                if end == scalars.count { return level }
                if edgeSpaces.contains(scalars[end]) {
                    while end < scalars.count, edgeSpaces.contains(scalars[end]) { end += 1 }
                    if end == scalars.count || (scalars[end].isASCII && CharacterSet.alphanumerics.contains(scalars[end])) { return level }
                }
            }
        }
        return nil
    }
}
