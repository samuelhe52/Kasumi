import Foundation
import Markdown

/// Owns syntax that the GFM adapter does not represent: TeX source and footnotes.
/// Math is protected before Markdown unescapes punctuation or parses underscores.
struct MarkdownExtensions {
    struct MathSource {
        let text: String
        let display: Bool
        let sourceLines: ClosedRange<Int>
    }
    let markdown: String
    let math: [String: MathSource]
    let mathPrefix: String
    let definitionLabelsByLine: [Int: String]
    let definitionOrder: [String]

    init(source: String) {
        let initial = Markdown.Document(parsing: source)
        var codeLines: Set<Int> = []
        func gatherCodeLines(_ node: any Markup) {
            if node is CodeBlock, let range = node.range {
                codeLines.formUnion(range.lowerBound.line...range.upperBound.line)
            } else {
                node.children.forEach(gatherCodeLines)
            }
        }
        gatherCodeLines(initial)
        let definition = try! NSRegularExpression(pattern: #"^ {0,3}\[\^([^\]]+)\]:[ \t]*(.*)$"#)
        var lines = source.components(separatedBy: "\n")
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
            if let match = definition.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let label = ns.substring(with: match.range(at: 1))
                labels[index + 1] = label
                if !order.contains(label) { order.append(label) }
                active = label
                lines[index] = ns.substring(with: match.range(at: 2))
            }
        }
        definitionLabelsByLine = labels
        definitionOrder = order
        let prepared = lines.joined(separator: "\n")
        let bytes = Array(prepared.utf8)
        var lineStarts = [0]
        for (index, byte) in bytes.enumerated() where byte == 10 { lineStarts.append(index + 1) }
        func byteOffset(_ location: SourceLocation) -> Int? {
            guard location.line > 0, location.line <= lineStarts.count, location.column > 0 else { return nil }
            return min(bytes.count, lineStarts[location.line - 1] + location.column - 1)
        }
        var excluded: [Range<Int>] = []
        func gatherExcluded(_ node: any Markup) {
            if node is CodeBlock || node is InlineCode || node is HTMLBlock || node is InlineHTML {
                if let range = node.range, let lower = byteOffset(range.lowerBound),
                    let upper = byteOffset(range.upperBound)
                {
                    excluded.append(lower..<upper)
                }
            } else {
                node.children.forEach(gatherExcluded)
            }
        }
        gatherExcluded(Markdown.Document(parsing: prepared))
        excluded.sort { $0.lowerBound < $1.lowerBound }
        var prefix = "\u{E000}kasumi.math."
        while prepared.contains(prefix) { prefix += "." }
        mathPrefix = prefix
        var tokens: [String: MathSource] = [:]
        var output: [UInt8] = []
        var cursor = 0
        var copied = 0
        var exclusion = 0
        func escaped(_ index: Int) -> Bool {
            var before = index
            var slashes = 0
            while before > 0 && bytes[before - 1] == 92 {
                before -= 1
                slashes += 1
            }
            return slashes % 2 == 1
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
            let display: Bool
            let contentStart: Int
            let closing: Int?
            let width: Int
            if bytes[cursor] == 36, !escaped(cursor) {
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
                    if bytes[end] == 36 && !escaped(end) {
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
                !escaped(cursor)
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
            let marker = prefix + String(tokens.count) + "\u{E001}"
            let lowerLine = bytes[..<cursor].filter { $0 == 10 }.count + 1
            let upperLine = lowerLine + bytes[cursor..<finish].filter { $0 == 10 }.count
            tokens[marker] = MathSource(
                text: String(decoding: bytes[contentStart..<closing], as: UTF8.self), display: display,
                sourceLines: lowerLine...upperLine)
            output.append(contentsOf: bytes[copied..<cursor])
            output.append(contentsOf: marker.utf8)
            output.append(contentsOf: repeatElement(UInt8(10), count: upperLine - lowerLine))
            cursor = finish
            copied = finish
        }
        output.append(contentsOf: bytes[copied...])
        markdown = String(decoding: output, as: UTF8.self)
        math = tokens
    }

    func textRuns(_ text: String, traits: Set<InlineRun.Trait>, destination: String?) -> [InlineRun] {
        let pattern = NSRegularExpression.escapedPattern(for: mathPrefix) + #"[0-9]+\uE001|==([^\n=]+)=="#
        let regex = try! NSRegularExpression(pattern: pattern)
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
            } else {
                result.append(
                    InlineRun(
                        ns.substring(with: match.range(at: 1)), traits: traits.union([.highlight]),
                        destination: destination))
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
        let regex = try! NSRegularExpression(pattern: #"\[\^([^\]]+)\]"#)
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
