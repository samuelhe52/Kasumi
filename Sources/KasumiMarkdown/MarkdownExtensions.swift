import Darwin
import Foundation
import Markdown

/// Uses source ranges to protect literal code and HTML before placeholder insertion.
private struct ExtensionExclusions: MarkupWalker {
    let lineStarts: [Int]
    let sourceLength: Int
    var ranges: [Range<Int>] = []
    var scriptRanges: [Range<Int>] = []

    mutating func defaultVisit(_ markup: any Markup) {
        if markup.childCount > 0 { descendInto(markup) }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) { record(codeBlock.range) }
    mutating func visitInlineCode(_ inlineCode: InlineCode) { record(inlineCode.range) }
    mutating func visitHTMLBlock(_ html: HTMLBlock) { record(html.range) }
    mutating func visitInlineHTML(_ html: InlineHTML) { record(html.range) }
    mutating func visitImage(_ image: Markdown.Image) {
        if let range = offsets(image.range) { scriptRanges.append(range) }
        descendInto(image)
    }

    mutating func visitLink(_ link: Markdown.Link) {
        if let range = offsets(link.range) {
            let lastChild = link.childCount > 0 ? link.child(at: link.childCount - 1) : nil
            let labelEnd = lastChild.flatMap { offsets($0.range)?.upperBound } ?? range.lowerBound
            if labelEnd < range.upperBound { scriptRanges.append(labelEnd..<range.upperBound) }
        }
        descendInto(link)
    }

    private mutating func record(_ range: SourceRange?) {
        if let range = offsets(range) { ranges.append(range) }
    }

    private func offsets(_ range: SourceRange?) -> Range<Int>? {
        guard let range, let lower = byteOffset(range.lowerBound), let upper = byteOffset(range.upperBound)
        else { return nil }
        return lower..<upper
    }

    private func byteOffset(_ location: SourceLocation) -> Int? {
        guard location.line > 0, location.line <= lineStarts.count, location.column > 0 else { return nil }
        return min(sourceLength, lineStarts[location.line - 1] + location.column - 1)
    }
}

/// Protects math and script syntax before Markdown consumes their delimiters.
struct MarkdownExtensions {
    struct MathSource {
        let text: String
        let display: Bool
        let sourceLines: ClosedRange<Int>
    }
    let markdown: String
    let math: [String: MathSource]
    private let scripts: [String: InlineRun]
    let mathPrefix: String
    let definitionLabelsByLine: [Int: String]
    let definitionOrder: [String]
    private static let defaultMathPrefix = "\u{E000}kasumi.math."
    private static let defaultInlinePattern = inlinePattern(prefix: defaultMathPrefix)
    private static let footnoteDefinition = try! NSRegularExpression(pattern: #"^ {0,3}\[\^([^\]]+)\]:[ \t]*(.*)$"#)
    private static let footnoteReference = try! NSRegularExpression(pattern: #"\[\^([^\]]+)\]"#)

    private static func inlinePattern(prefix: String) -> NSRegularExpression {
        let pattern = NSRegularExpression.escapedPattern(for: prefix) + #"[0-9]+\uE001|==([^\n=]+)=="#
        return try! NSRegularExpression(pattern: pattern)
    }

    private static func escaped<Bytes: RandomAccessCollection>(_ index: Int, in bytes: Bytes) -> Bool
    where Bytes.Index == Int, Bytes.Element == UInt8 {
        var before = index
        while before > 0, bytes[before - 1] == 92 { before -= 1 }
        return (index - before) % 2 == 1
    }

    /// One delimiter on each side, with nonempty content on the same line.
    /// A backslash can quote punctuation or a space. GFM handles doubled tildes.
    private static func scriptEnd<Bytes: RandomAccessCollection>(
        _ start: Int, in bytes: Bytes, before limit: Int
    ) -> Int? where Bytes.Index == Int, Bytes.Element == UInt8 {
        let delimiter = bytes[start]
        guard start + 2 < limit,
            !escaped(start, in: bytes),
            start == 0 || bytes[start - 1] != delimiter || escaped(start - 1, in: bytes),
            bytes[start + 1] != delimiter
        else { return nil }
        var end = start + 1
        while end < limit {
            switch bytes[end] {
            case 9, 10, 13, 32: return nil
            case 92 where end + 1 < limit:
                let next = bytes[end + 1]
                if next == 32 || isASCIIPunctuation(next) { end += 1 }
            case delimiter:
                return end + 1 == bytes.endIndex || bytes[end + 1] != delimiter ? end : nil
            default: break
            }
            end += 1
        }
        return nil
    }

    private static func isASCIIPunctuation(_ byte: UInt8) -> Bool {
        (33...47).contains(byte) || (58...64).contains(byte) || (91...96).contains(byte) || (123...126).contains(byte)
    }

    private static func scriptText(_ source: ArraySlice<UInt8>) -> String {
        guard source.contains(92) else { return String(decoding: source, as: UTF8.self) }
        var output: [UInt8] = []
        var cursor = source.startIndex
        while cursor < source.endIndex {
            if source[cursor] == 92, cursor + 1 < source.endIndex {
                let next = source[cursor + 1]
                if next == 32 {
                    // Pandoc's escaped space is nonbreaking.
                    output.append(contentsOf: [0xc2, 0xa0])
                    cursor += 2
                    continue
                }
                if isASCIIPunctuation(next) { cursor += 1 }
            }
            output.append(source[cursor])
            cursor += 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    init(source: String) {
        // Delimiters are ASCII bytes. Grapheme-aware substring searches over a
        // long CJK document can cost more than the parse they are meant to skip.
        @inline(__always) func markers(in bytes: UnsafeBufferPointer<UInt8>)
            -> (extensions: Bool, footnotes: Bool, privateUse: Bool)
        {
            guard let start = bytes.baseAddress else { return (false, false, false) }
            let hasDollar = memchr(start, 36, bytes.count) != nil
            let privateUse = memchr(start, 0xee, bytes.count) != nil
            // libc's byte search skips the delimiter loop for ordinary prose.
            // Only a caret can require footnote setup after finding math.
            if memchr(start, 94, bytes.count) == nil,
                hasDollar || (memchr(start, 92, bytes.count) == nil && memchr(start, 126, bytes.count) == nil)
            {
                return (hasDollar, false, privateUse)
            }
            var previous: UInt8 = 0
            var result = (extensions: hasDollar, footnotes: false, privateUse: privateUse)
            for index in bytes.indices {
                let byte = bytes[index]
                switch byte {
                case 40, 91:
                    if previous == 92 { result.extensions = true }
                case 94 where previous == 91:
                    result.footnotes = true
                    result.extensions = true
                case 94, 126:
                    if !result.extensions, Self.scriptEnd(index, in: bytes, before: bytes.count) != nil {
                        result.extensions = true
                    }
                default: break
                }
                previous = byte
            }
            return result
        }
        let found =
            source.utf8.withContiguousStorageIfAvailable { markers(in: $0) }
            ?? Array(source.utf8).withUnsafeBufferPointer { markers(in: $0) }
        let hasFootnotes = found.footnotes
        if !found.extensions {
            markdown = source
            math = [:]
            scripts = [:]
            var prefix = Self.defaultMathPrefix
            if found.privateUse {
                while source.contains(prefix) { prefix += "." }
            }
            mathPrefix = prefix
            definitionLabelsByLine = [:]
            definitionOrder = []
            return
        }
        let initial = Markdown.Document(parsing: source)
        var codeLines: Set<Int> = []
        func gatherCodeLines(_ node: any Markup) {
            if node is CodeBlock, let range = node.range {
                codeLines.formUnion(range.lowerBound.line...range.upperBound.line)
            } else {
                node.children.forEach(gatherCodeLines)
            }
        }
        if hasFootnotes { gatherCodeLines(initial) }
        var lines = hasFootnotes ? source.components(separatedBy: "\n") : []
        var labels: [Int: String] = [:]
        var order: [String] = []
        var active: String?
        for index in lines.indices {
            let line = lines[index]
            if let label = active, line.hasPrefix("    ") || line.hasPrefix("\t") {
                lines[index] = String(line.dropFirst(line.hasPrefix("\t") ? 1 : 4))
                labels[index + 1] = label
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            active = nil
            guard !codeLines.contains(index + 1) else { continue }
            let ns = line as NSString
            if let match = Self.footnoteDefinition.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
            {
                let label = ns.substring(with: match.range(at: 1))
                labels[index + 1] = label
                if !order.contains(label) { order.append(label) }
                active = label
                lines[index] = ns.substring(with: match.range(at: 2))
            }
        }
        definitionLabelsByLine = labels
        definitionOrder = order
        let prepared = hasFootnotes ? lines.joined(separator: "\n") : source
        let bytes = Array(prepared.utf8)
        var lineStarts = [0]
        for (index, byte) in bytes.enumerated() where byte == 10 { lineStarts.append(index + 1) }
        var exclusions = ExtensionExclusions(lineStarts: lineStarts, sourceLength: bytes.count)
        exclusions.visit(labels.isEmpty ? initial : Markdown.Document(parsing: prepared))
        var excluded = exclusions.ranges
        excluded.sort { $0.lowerBound < $1.lowerBound }
        let scriptExcluded = exclusions.scriptRanges.sorted { $0.lowerBound < $1.lowerBound }
        var prefix = Self.defaultMathPrefix
        if found.privateUse {
            while prepared.contains(prefix) { prefix += "." }
        }
        mathPrefix = prefix
        var tokens: [String: MathSource] = [:]
        var scriptTokens: [String: InlineRun] = [:]
        var output: [UInt8] = []
        var cursor = 0
        var copied = 0
        var exclusion = 0
        var scriptExclusion = 0
        func insertMarker(endingAt finish: Int, lineBreaks: Int = 0) -> String {
            let marker = prefix + String(tokens.count + scriptTokens.count) + "\u{E001}"
            output.append(contentsOf: bytes[copied..<cursor])
            output.append(contentsOf: marker.utf8)
            output.append(contentsOf: repeatElement(UInt8(10), count: lineBreaks))
            cursor = finish
            copied = finish
            return marker
        }
        func whitespace(_ byte: UInt8) -> Bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 }
        func lineBreak(_ byte: UInt8) -> Bool { byte == 10 || byte == 13 }
        // `\[` is also CommonMark's escaped bracket, so display brackets count only
        // when `\[` opens a line (after up to three spaces) and `\]` closes one.
        func opensLine(_ index: Int) -> Bool {
            var before = index
            while before > 0 && bytes[before - 1] == 32 && index - before < 3 { before -= 1 }
            return before == 0 || lineBreak(bytes[before - 1])
        }
        func closesLine(_ index: Int) -> Bool {
            var after = index
            while after < bytes.count && (bytes[after] == 32 || bytes[after] == 9) { after += 1 }
            return after == bytes.count || lineBreak(bytes[after])
        }
        while cursor < bytes.count {
            while exclusion < excluded.count && excluded[exclusion].upperBound <= cursor { exclusion += 1 }
            if exclusion < excluded.count && excluded[exclusion].contains(cursor) {
                cursor = excluded[exclusion].upperBound
                continue
            }
            if bytes[cursor] == 126 || bytes[cursor] == 94 {
                while scriptExclusion < scriptExcluded.count && scriptExcluded[scriptExclusion].upperBound <= cursor {
                    scriptExclusion += 1
                }
                let nextLiteral = exclusion < excluded.count ? excluded[exclusion].lowerBound : bytes.count
                let nextDestination =
                    scriptExclusion < scriptExcluded.count
                    ? scriptExcluded[scriptExclusion].lowerBound : bytes.count
                if cursor == 0 || bytes[cursor - 1] != 91 || bytes[cursor] != 94,
                    let end = Self.scriptEnd(cursor, in: bytes, before: min(nextLiteral, nextDestination))
                {
                    let trait: InlineRun.Trait = bytes[cursor] == 126 ? .subscript : .superscript
                    let text = Self.scriptText(bytes[(cursor + 1)..<end])
                    let marker = insertMarker(endingAt: end + 1)
                    scriptTokens[marker] = InlineRun(text, traits: [trait])
                    continue
                }
            }
            let display: Bool
            let contentStart: Int
            let closing: Int?
            let width: Int
            if bytes[cursor] == 36, !Self.escaped(cursor, in: bytes) {
                let delimiter = cursor + 1 < bytes.count && bytes[cursor + 1] == 36 ? 2 : 1
                contentStart = cursor + delimiter
                guard contentStart < bytes.count, delimiter == 2 || !whitespace(bytes[contentStart]) else {
                    cursor += delimiter
                    continue
                }
                var end = contentStart
                var found: Int?
                while end < bytes.count {
                    if delimiter == 1 && lineBreak(bytes[end]) { break }
                    if bytes[end] == 36 && !Self.escaped(end, in: bytes) {
                        guard delimiter == 2 else {
                            if end > contentStart && !whitespace(bytes[end - 1])
                                && !(end + 1 < bytes.count && (48...57).contains(bytes[end + 1]))
                            {
                                found = end
                            }
                            break
                        }
                        if end + 1 < bytes.count && bytes[end + 1] == 36 {
                            found = end
                            break
                        }
                    }
                    end += 1
                }
                display = delimiter == 2
                closing = found
                width = delimiter
            } else if bytes[cursor] == 92, cursor + 1 < bytes.count, bytes[cursor + 1] == 40 || bytes[cursor + 1] == 91,
                !Self.escaped(cursor, in: bytes)
            {
                display = bytes[cursor + 1] == 91
                guard !display || opensLine(cursor) else {
                    cursor += 2
                    continue
                }
                contentStart = cursor + 2
                let close: UInt8 = display ? 93 : 41
                var end = contentStart
                var found: Int?
                while end + 1 < bytes.count {
                    if !display && lineBreak(bytes[end]) { break }
                    if bytes[end] == 92 {
                        if bytes[end + 1] == close && end > contentStart && (!display || closesLine(end + 2)) {
                            found = end
                            break
                        }
                        end += 2
                        continue
                    }
                    end += 1
                }
                closing = found
                width = 2
            } else {
                cursor += 1
                continue
            }
            guard let closing else {
                cursor += width
                continue
            }
            let finish = closing + width
            func lineNumber(at offset: Int) -> Int {
                var lower = 0
                var upper = lineStarts.count
                while lower < upper {
                    let middle = lower + (upper - lower) / 2
                    if lineStarts[middle] <= offset { lower = middle + 1 } else { upper = middle }
                }
                return lower
            }
            let lowerLine = lineNumber(at: cursor)
            let upperLine = lineNumber(at: finish)
            let marker = insertMarker(endingAt: finish, lineBreaks: upperLine - lowerLine)
            tokens[marker] = MathSource(
                text: String(decoding: bytes[contentStart..<closing], as: UTF8.self), display: display,
                sourceLines: lowerLine...upperLine)
        }
        output.append(contentsOf: bytes[copied...])
        markdown = String(decoding: output, as: UTF8.self)
        math = tokens
        scripts = scriptTokens
    }

    /// Replace math placeholders with their TeX source, leaving every other character literal.
    func expandingMath(_ text: String) -> String {
        guard !math.isEmpty, text.contains(mathPrefix) else { return text }
        var result = ""
        var remaining = text[...]
        while let start = remaining.range(of: mathPrefix) {
            result += remaining[..<start.lowerBound]
            if let end = remaining[start.upperBound...].firstIndex(of: "\u{E001}"),
                let source = math[String(remaining[start.lowerBound...end])]
            {
                result += source.text
                remaining = remaining[remaining.index(after: end)...]
            } else {
                result += remaining[start]
                remaining = remaining[start.upperBound...]
            }
        }
        return result + remaining
    }

    func textRuns(_ text: String, traits: Set<InlineRun.Trait>, destination: String?) -> [InlineRun] {
        // Ordinary prose needs neither the marker regex nor two generic UTF-8
        // walks. Check both ASCII '=' and the private-use marker's leading byte
        // together, using direct buffer access when String can provide it.
        let hasMarkers =
            text.utf8.withContiguousStorageIfAvailable { bytes in
                for byte in bytes where byte == 0xee || byte == 61 { return true }
                return false
            } ?? text.utf8.contains(where: { $0 == 0xee || $0 == 61 })
        guard hasMarkers else {
            return text.isEmpty ? [] : [InlineRun(text, traits: traits, destination: destination)]
        }
        let regex =
            mathPrefix == Self.defaultMathPrefix ? Self.defaultInlinePattern : Self.inlinePattern(prefix: mathPrefix)
        let ns = text as NSString
        var cursor = 0
        var result: [InlineRun] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result.append(
                    InlineRun(
                        ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                        traits: traits, destination: destination))
            }
            let value = ns.substring(with: match.range)
            if let math = math[value] {
                result.append(InlineRun(math.text, traits: traits.union([.math]), destination: destination))
            } else if let script = scripts[value] {
                result.append(InlineRun(script.text, traits: traits.union(script.traits), destination: destination))
            } else if match.range(at: 1).location != NSNotFound {
                result.append(
                    contentsOf: textRuns(
                        ns.substring(with: match.range(at: 1)), traits: traits.union([.highlight]),
                        destination: destination))
            } else {
                result.append(InlineRun(value, traits: traits, destination: destination))
            }
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length {
            result.append(InlineRun(ns.substring(from: cursor), traits: traits, destination: destination))
        }
        return result
    }

    func resolveFootnotes(in blocks: inout [DocumentBlock]) {
        let labels = Set(definitionOrder)
        guard !definitionOrder.isEmpty else { return }
        let regex = Self.footnoteReference
        var referenced: [String] = []
        func annotate(_ runs: [InlineRun]) -> [InlineRun] {
            runs.flatMap { run -> [InlineRun] in
                guard !run.traits.contains(.code), !run.traits.contains(.math), !run.traits.contains(.image) else {
                    return [run]
                }
                let ns = run.text as NSString
                var cursor = 0
                var result: [InlineRun] = []
                for match in regex.matches(in: run.text, range: NSRange(location: 0, length: ns.length)) {
                    let label = ns.substring(with: match.range(at: 1))
                    guard labels.contains(label) else { continue }
                    if match.range.location > cursor {
                        result.append(
                            InlineRun(
                                ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                                traits: run.traits, destination: run.destination))
                    }
                    var mark = InlineRun(label, traits: run.traits.union([.footnote]), destination: "#fn-" + label)
                    mark.footnoteLabel = label
                    result.append(mark)
                    if !referenced.contains(label) { referenced.append(label) }
                    cursor = NSMaxRange(match.range)
                }
                if cursor < ns.length {
                    result.append(
                        InlineRun(ns.substring(from: cursor), traits: run.traits, destination: run.destination))
                }
                return result
            }
        }
        for index in blocks.indices where ![.code, .diagram, .math, .image].contains(blocks[index].kind) {
            blocks[index].runs = annotate(blocks[index].runs)
            for row in blocks[index].rows.indices {
                for cell in blocks[index].rows[row].indices {
                    blocks[index].rows[row][cell] = annotate(blocks[index].rows[row][cell])
                }
            }
        }
        let ordered = referenced + definitionOrder.filter { !referenced.contains($0) }
        let display = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, String($0.offset + 1)) })
        for index in blocks.indices {
            if let label = blocks[index].footnoteLabel { blocks[index].footnoteDisplay = display[label] }
            func fill(_ runs: [InlineRun]) -> [InlineRun] {
                runs.map { run in
                    var result = run
                    if let label = run.footnoteLabel { result.footnoteDisplay = display[label] }
                    return result
                }
            }
            blocks[index].runs = fill(blocks[index].runs)
            for row in blocks[index].rows.indices {
                for cell in blocks[index].rows[row].indices {
                    blocks[index].rows[row][cell] = fill(blocks[index].rows[row][cell])
                }
            }
        }
    }
}
