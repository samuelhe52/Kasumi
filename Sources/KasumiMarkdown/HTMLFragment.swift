import Foundation
import cmark_gfm

private struct HTMLTag {
    let name: String
    let closing: Bool
    let selfClosing: Bool
    var attributes: [String: String] = [:]

    var alignment: ParagraphAlignment? {
        switch attributes["align"]?.lowercased() {
        case "left": return .leading
        case "center": return .centered
        case "right": return .trailing
        case "justify": return .justified
        default: return name == "center" ? .centered : nil
        }
    }

    func dimension(_ name: String) -> Double? {
        guard var value = attributes[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        if value.hasSuffix("px") { value.removeLast(2) }
        guard let number = Double(value), number.isFinite, number > 0 else { return nil }
        return number
    }
}

/// Tokenizes Markdown's raw HTML nodes. Only attributes used by the renderer are retained.
private struct HTMLTokenizer {
    enum Token {
        case text(String)
        case tag(HTMLTag)
        case ignored
    }

    private let bytes: [UInt8]
    private var cursor = 0
    private var countedBytes = 0
    private var line = 0
    /// Zero-based source lines of the last token, without surrounding whitespace.
    private(set) var lines = 0...0
    private static let attributes: Set<String> = ["align", "width", "height", "href", "src", "alt"]

    init(_ source: String) { bytes = Array(source.utf8) }

    static func whitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 12 || byte == 13
    }

    private static func letter(_ byte: UInt8) -> Bool { (97...122).contains(byte | 32) }

    mutating func next(skippingRawTextOf rawTag: String? = nil) -> Token? {
        if let rawTag {
            // These HTML elements treat their contents as raw text. A '<' in a
            // script or stylesheet must not consume the actual closing tag.
            let end = Array(("</" + rawTag).utf8)
            while cursor + end.count < bytes.count {
                let next = cursor + end.count
                if bytes[cursor] == 60, bytes[next] == 62 || Self.whitespace(bytes[next]),
                    zip(bytes[cursor..<next], end).allSatisfy({ $0 == $1 || $0 | 32 == $1 })
                {
                    break
                }
                cursor += 1
            }
            if cursor + end.count >= bytes.count { cursor = bytes.count }
        }
        guard cursor < bytes.count else { return nil }
        let start = cursor
        let token = scan()
        let tokenBytes = bytes[start..<cursor]
        let first = tokenBytes.firstIndex { !Self.whitespace($0) } ?? start
        let last = tokenBytes.lastIndex { !Self.whitespace($0) } ?? start
        let lower = lineNumber(at: first)
        lines = lower...lineNumber(at: last)
        return token
    }

    private mutating func lineNumber(at offset: Int) -> Int {
        while countedBytes < offset {
            let next = countedBytes + 1
            if bytes[countedBytes] == 10 || (bytes[countedBytes] == 13 && (next == bytes.count || bytes[next] != 10)) {
                line += 1
            }
            countedBytes = next
        }
        return line
    }

    private mutating func scan() -> Token {
        let start = cursor
        if bytes[cursor] == 60, let markup = markup() { return markup }
        cursor = start + 1
        while cursor < bytes.count, bytes[cursor] != 60 { cursor += 1 }
        return .text(Self.decode(bytes[start..<cursor]))
    }

    private mutating func markup() -> Token? {
        let start = cursor
        cursor += 1
        guard cursor < bytes.count else { return nil }
        if bytes[cursor...].starts(with: [33, 45, 45]) {
            cursor += 3
            while cursor + 2 < bytes.count {
                if bytes[cursor...].starts(with: [45, 45, 62]) {
                    cursor += 3
                    return .ignored
                }
                cursor += 1
            }
            cursor = bytes.count
            return .ignored
        }
        if bytes[cursor] == 33 || bytes[cursor] == 63 {
            while cursor < bytes.count, bytes[cursor] != 62 { cursor += 1 }
            if cursor < bytes.count { cursor += 1 }
            return .ignored
        }
        let closing = bytes[cursor] == 47
        if closing { cursor += 1 }
        guard cursor < bytes.count, Self.letter(bytes[cursor]) else { return nil }
        let nameStart = cursor
        while cursor < bytes.count, !Self.whitespace(bytes[cursor]), ![47, 60, 62].contains(bytes[cursor]) {
            cursor += 1
        }
        let name = String(decoding: bytes[nameStart..<cursor], as: UTF8.self).lowercased()
        var attributes: [String: String] = [:]
        while cursor < bytes.count {
            skipWhitespace()
            guard cursor < bytes.count else { break }
            if bytes[cursor] == 62 {
                cursor += 1
                return .tag(HTMLTag(name: name, closing: closing, selfClosing: false, attributes: attributes))
            }
            if bytes[cursor...].starts(with: [47, 62]) {
                cursor += 2
                return .tag(HTMLTag(name: name, closing: closing, selfClosing: true, attributes: attributes))
            }
            if bytes[cursor] == 60 { break }
            let keyStart = cursor
            while cursor < bytes.count, !Self.whitespace(bytes[cursor]), ![47, 60, 61, 62].contains(bytes[cursor]) {
                cursor += 1
            }
            if cursor == keyStart {
                cursor += 1
                continue
            }
            let key = String(decoding: bytes[keyStart..<cursor], as: UTF8.self).lowercased()
            skipWhitespace()
            guard cursor < bytes.count, bytes[cursor] == 61 else { continue }
            cursor += 1
            skipWhitespace()
            guard cursor < bytes.count else { break }
            let quote = bytes[cursor]
            let quoted = quote == 34 || quote == 39
            if quoted { cursor += 1 }
            let valueStart = cursor
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if quoted ? byte == quote : Self.whitespace(byte) || byte == 60 || byte == 62 { break }
                cursor += 1
            }
            if Self.attributes.contains(key), attributes[key] == nil {
                attributes[key] = Self.decode(bytes[valueStart..<cursor])
            }
            if quoted && cursor < bytes.count { cursor += 1 }
        }
        // Retain a malformed tag as text. Resume at the next potential tag.
        cursor = bytes[(start + 1)...].firstIndex(of: 60) ?? bytes.count
        return .text(Self.decode(bytes[start..<cursor]))
    }

    private mutating func skipWhitespace() {
        while cursor < bytes.count, Self.whitespace(bytes[cursor]) { cursor += 1 }
    }

    private static func decode(_ bytes: ArraySlice<UInt8>) -> String {
        // Use the same named and numeric entities as the Markdown parser.
        if bytes.contains(38), let count = Int32(exactly: bytes.count) {
            var buffer = cmark_strbuf()
            cmark_strbuf_init(cmark_get_default_mem_allocator(), &buffer, 0)
            defer { cmark_strbuf_free(&buffer) }
            let decoded = bytes.withUnsafeBufferPointer {
                houdini_unescape_html(&buffer, $0.baseAddress, count)
            }
            if decoded != 0 {
                return String(decoding: UnsafeBufferPointer(start: buffer.ptr, count: Int(buffer.size)), as: UTF8.self)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

enum HTMLFragment {
    private static let inlineTraits: [String: InlineRun.Trait] = [
        "b": .strong, "strong": .strong,
        "i": .emphasis, "em": .emphasis, "cite": .emphasis,
        "code": .code, "kbd": .code, "samp": .code, "tt": .code,
        "s": .strikethrough, "del": .strikethrough, "strike": .strikethrough,
        "mark": .highlight, "sub": .subscript, "sup": .superscript, "u": .underline, "ins": .underline
    ]
    private static let ignoredContent: Set<String> = [
        "script", "style", "iframe", "object", "embed", "template", "noscript", "svg", "math"
    ]
    private static let rawText: Set<String> = ["script", "style", "iframe"]
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
    ]
    private static let lineEnds: Set<String> = [
        "address", "article", "aside", "blockquote", "caption", "dd", "dl", "dt", "figcaption", "figure",
        "footer", "form", "header", "li", "main", "nav", "ol", "pre", "section", "table", "tbody", "td",
        "tfoot", "th", "thead", "tr", "ul"
    ]
    private static let headingLevels = ["h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6]

    fileprivate struct HiddenContent {
        var names: [String] = []
        var rawTag: String? { names.last.flatMap { rawText.contains($0) ? $0 : nil } }

        mutating func consume(_ tag: HTMLTag) -> Bool {
            if tag.closing, !names.isEmpty {
                if let index = names.lastIndex(of: tag.name) { names.removeSubrange(index...) }
                return true
            }
            if !tag.closing, ignoredContent.contains(tag.name) {
                if !tag.selfClosing, !voidTags.contains(tag.name) { names.append(tag.name) }
                return true
            }
            return !names.isEmpty
        }
    }

    struct InlineContext {
        private struct Frame {
            var name: String
            var traits: Set<InlineRun.Trait>
            var destination: String?
        }

        private var frames: [Frame] = []
        private var hidden = HiddenContent()
        var blockContext: Context?
        let inheritedTraits: Set<InlineRun.Trait>
        let inheritedDestination: String?

        init(traits: Set<InlineRun.Trait> = [], destination: String? = nil, blockContext: Context? = nil) {
            inheritedTraits = traits
            inheritedDestination = destination
            self.blockContext = blockContext
        }

        var traits: Set<InlineRun.Trait> { frames.last?.traits ?? inheritedTraits }
        var destination: String? { frames.last?.destination ?? inheritedDestination }
        var isHidden: Bool { !hidden.names.isEmpty || blockContext?.isHidden == true }

        mutating func runs(_ raw: String) -> [InlineRun] {
            var tokenizer = HTMLTokenizer(raw)
            var result: [InlineRun] = []
            while let token = tokenizer.next(skippingRawTextOf: hidden.rawTag ?? blockContext?.hidden.rawTag) {
                guard case .tag(let tag) = token else { continue }
                if blockContext?.isHidden == true {
                    _ = blockContext?.hidden.consume(tag)
                    continue
                }
                if hidden.consume(tag) { continue }
                if tag.closing { blockContext?.close(tag.name) }
                if let run = consume(tag) { result.append(run) }
            }
            return result
        }

        fileprivate mutating func consume(_ tag: HTMLTag) -> InlineRun? {
            if tag.closing {
                if let index = frames.lastIndex(where: { $0.name == tag.name }) { frames.removeSubrange(index...) }
                return nil
            }
            switch tag.name {
            case "br": return InlineRun("\n", traits: traits, destination: destination)
            case "img":
                var run = InlineRun(
                    tag.attributes["alt"] ?? "", traits: traits.union([.image]), destination: destination)
                run.imageSource = tag.attributes["src"]
                run.imageWidth = tag.dimension("width")
                run.imageHeight = tag.dimension("height")
                return run
            default:
                guard !tag.selfClosing else { return nil }
                if let trait = inlineTraits[tag.name] {
                    frames.append(Frame(name: tag.name, traits: traits.union([trait]), destination: destination))
                } else if tag.name == "a", let href = tag.attributes["href"] {
                    frames.append(Frame(name: tag.name, traits: traits.union([.link]), destination: href))
                }
                return nil
            }
        }
    }

    struct Context {
        fileprivate struct Frame {
            var name: String
            var alignment: ParagraphAlignment?
        }

        fileprivate var frames: [Frame] = []
        fileprivate var hidden = HiddenContent()
        var alignment: ParagraphAlignment? { frames.last?.alignment }
        var isHidden: Bool { !hidden.names.isEmpty }
        var needsInlineTracking: Bool { !frames.isEmpty || isHidden }
        fileprivate var inDetails: Bool { frames.contains { $0.name == "details" } }

        fileprivate mutating func open(_ tag: HTMLTag) {
            guard !tag.selfClosing, !voidTags.contains(tag.name) else { return }
            frames.append(Frame(name: tag.name, alignment: tag.alignment ?? alignment))
        }

        fileprivate mutating func close(_ name: String) {
            if let index = frames.lastIndex(where: { $0.name == name }) { frames.removeSubrange(index...) }
        }
    }

    struct Block {
        var kind: DocumentBlock.Kind = .paragraph
        var runs: [InlineRun] = []
        var level: Int = 0
        var alignment: ParagraphAlignment?
        /// Zero-based lines within the raw HTML.
        var lines = 0...0
    }

    static func blocks(_ raw: String, context: inout Context) -> [Block] {
        var tokenizer = HTMLTokenizer(raw)
        var output: [Block] = []
        var runs: [InlineRun] = []
        var inline = InlineContext()
        var pendingSpace = false
        var trailingBoundary = false
        var headingLevel = 0
        var summary = false
        var firstLine: Int?
        var lastLine = 0

        func includeToken() {
            firstLine = firstLine ?? tokenizer.lines.lowerBound
            lastLine = tokenizer.lines.upperBound
        }

        func flush(alignment: ParagraphAlignment?) {
            if trailingBoundary { runs.removeLast() }
            if !runs.isEmpty || summary {
                if summary { runs.insert(InlineRun("▾ ", traits: [.strong]), at: 0) }
                output.append(
                    Block(
                        kind: headingLevel > 0 ? .heading : .paragraph, runs: runs, level: headingLevel,
                        alignment: alignment, lines: (firstLine ?? lastLine)...lastLine))
            }
            runs = []
            firstLine = nil
            headingLevel = 0
            summary = false
            pendingSpace = false
            trailingBoundary = false
        }

        func appendText(_ text: String) {
            var bytes: [UInt8] = []
            for byte in text.utf8 {
                if HTMLTokenizer.whitespace(byte) {
                    pendingSpace = true
                } else {
                    if pendingSpace, !bytes.isEmpty || (!runs.isEmpty && runs.last?.text != "\n") { bytes.append(32) }
                    pendingSpace = false
                    bytes.append(byte)
                }
            }
            guard !bytes.isEmpty else { return }
            includeToken()
            let traits = summary ? inline.traits.union([.strong]) : inline.traits
            runs.append(
                InlineRun(String(decoding: bytes, as: UTF8.self), traits: traits, destination: inline.destination))
            trailingBoundary = false
        }

        while let token = tokenizer.next(skippingRawTextOf: context.hidden.rawTag) {
            switch token {
            case .ignored: continue
            case .text(let text):
                if !context.isHidden { appendText(text) }
            case .tag(let tag):
                if context.hidden.consume(tag) { continue }
                let level = headingLevels[tag.name] ?? 0
                let boundary = level > 0 || ["p", "div", "center", "details", "summary", "hr"].contains(tag.name)
                let aligned =
                    tag.closing
                    ? context.frames.contains { $0.name == tag.name }
                    : tag.alignment != nil && !voidTags.contains(tag.name)
                if boundary || aligned {
                    if tag.closing, !runs.isEmpty { lastLine = tokenizer.lines.upperBound }
                    flush(alignment: context.alignment)
                    if tag.closing {
                        context.close(tag.name)
                    } else if tag.name == "hr" {
                        output.append(Block(kind: .rule, alignment: context.alignment, lines: tokenizer.lines))
                    } else {
                        context.open(tag)
                        includeToken()
                        headingLevel = level
                        summary = tag.name == "summary" && context.inDetails
                    }
                } else if tag.closing, lineEnds.contains(tag.name) {
                    if !runs.isEmpty, runs.last?.text != "\n" {
                        runs.append(InlineRun("\n"))
                        trailingBoundary = true
                    }
                    pendingSpace = false
                } else if let run = inline.consume(tag) {
                    includeToken()
                    if pendingSpace, !runs.isEmpty, runs.last?.text != "\n", run.traits.contains(.image) {
                        runs.append(InlineRun(" "))
                    }
                    runs.append(run)
                    pendingSpace = false
                    trailingBoundary = false
                }
            }
        }
        flush(alignment: context.alignment)
        return output
    }
}
