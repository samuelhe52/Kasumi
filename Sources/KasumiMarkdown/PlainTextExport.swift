extension DocumentExport {
    /// Export the parsed content without layout or resource loading. Quotes and lists keep
    /// their markers, tables use tab-separated cells, and code, math and diagrams use source text.
    public static func plainText(_ document: MarkdownDocument) -> String {
        let containers = document.parsed.containers
        var output = PlainTextOutput(containers: containers)
        // An empty list item has a container but no blocks. Emit its marker
        // before the block that follows it in source order.
        var isEmptyItem = containers.map { container in
            if case .item = container.kind { return true }
            return false
        }
        for container in containers { if let parent = container.parent { isEmptyItem[parent] = false } }
        for block in document.parsed.blocks { if let id = block.containerID { isEmptyItem[id] = false } }
        var emptyItems = isEmptyItem.indices.filter { isEmptyItem[$0] }[...]
        func emitEmptyItems(before blockIndex: Int) {
            while let id = emptyItems.first, containers[id].firstBlock <= blockIndex {
                emptyItems.removeFirst()
                output.beginBlock(DocumentBlock(id: -1, kind: .paragraph, runs: [], containerID: id))
                output.trimTrailingSpaces()
            }
        }
        for (blockIndex, block) in document.parsed.blocks.enumerated() {
            emitEmptyItems(before: blockIndex)
            if block.containerID == nil, block.footnoteLabel == nil, block.rows.isEmpty, block.kind != .rule,
                block.codeSource?.isEmpty ?? block.runs.allSatisfy({ $0.text.isEmpty })
            {
                continue
            }
            output.beginBlock(block)
            switch block.kind {
            case .code, .diagram:
                if let source = block.codeSource {
                    output.append(source)
                } else {
                    output.appendRuns(block.runs)
                }
            case .math:
                for run in block.runs { output.appendMath(run.text) }
            case .rule:
                output.append("---")
            case .table:
                for (rowIndex, row) in block.rows.enumerated() {
                    if rowIndex > 0 { output.append("\n") }
                    for (columnIndex, cell) in row.enumerated() {
                        if columnIndex > 0 { output.append("\t") }
                        output.appendCell(cell)
                    }
                }
            case .paragraph, .quote, .heading, .image:
                output.appendRuns(block.runs)
            }
        }
        emitEmptyItems(before: document.parsed.blocks.count)
        return output.text
    }
}

private struct PlainTextOutput {
    var text = ""
    private let containers: [DocumentBlock.Container]
    private var path: [Int] = []
    private var nextPath: [Int] = []
    private var hasBlock = false
    private var previousFootnoteLabel: String?
    private var continuationPrefix = ""
    private var blankLinePrefix = ""
    // A line may have had a quote marker but no payload. Count payload line endings, capped at two.
    private var trailingBreaks = 0

    init(containers: [DocumentBlock.Container]) { self.containers = containers }

    mutating func beginBlock(_ block: DocumentBlock) {
        var shared = path.count
        if block.containerID != path.last {
            nextPath.removeAll(keepingCapacity: true)
            var id = block.containerID
            while let current = id {
                nextPath.append(current)
                id = containers[current].parent
            }
            nextPath.reverse()
            shared = 0
            while shared < path.count, shared < nextPath.count, path[shared] == nextPath[shared] {
                shared += 1
            }
            swap(&path, &nextPath)
        }

        var firstLinePrefix = ""
        var separatorPrefix = ""
        var startsNestedList = false
        var opensItem = false
        continuationPrefix = ""
        blankLinePrefix = ""
        if let display = block.footnoteDisplay {
            continuationPrefix = String(repeating: " ", count: display.count + 3)
            firstLinePrefix = block.footnoteLabel == previousFootnoteLabel ? continuationPrefix : "[\(display)] "
        }
        for (index, id) in path.enumerated() {
            switch containers[id].kind {
            case .quote:
                blankLinePrefix = continuationPrefix + ">"
                if index < shared { separatorPrefix = blankLinePrefix }
                firstLinePrefix += "> "
                continuationPrefix += "> "
            case .list:
                if opensItem {
                    // An item whose first child is itself a list still needs its own marker line.
                    firstLinePrefix.removeLast()
                    firstLinePrefix += "\n"
                    firstLinePrefix += continuationPrefix
                    opensItem = false
                }
                if index == shared, index > 0, case .item = containers[path[index - 1]].kind {
                    startsNestedList = true
                }
            case .item(let marker, _):
                let indent = String(repeating: " ", count: marker.count + 1)
                continuationPrefix += indent
                if index < shared {
                    firstLinePrefix += indent
                } else {
                    firstLinePrefix += marker
                    firstLinePrefix += " "
                    opensItem = true
                }
            }
        }

        if hasBlock {
            let startsSiblingItem = shared < path.count && {
                if case .item = containers[path[shared]].kind { return true }
                return false
            }()
            if trailingBreaks == 0 { text += "\n" }
            if !startsSiblingItem, !startsNestedList, trailingBreaks < 2 {
                text += separatorPrefix
                text += "\n"
            }
        }
        text += firstLinePrefix
        trailingBreaks = 0
        hasBlock = true
        previousFootnoteLabel = block.footnoteLabel
    }

    mutating func appendRuns(_ runs: [InlineRun]) {
        var wroteText = false
        for run in runs {
            if run.traits.contains(.math), run.text.contains(where: \.isNewline) {
                // Display math inside a paragraph keeps its raw source lines,
                // so it needs the same prefix stripping as a math block.
                if wroteText {
                    trimTrailingSpaces()
                    append("\n")
                }
                appendMath(run.text)
            } else {
                append(run.footnoteDisplay.map { "[\($0)]" } ?? run.text)
            }
            wroteText = wroteText || !run.text.isEmpty
        }
    }

    mutating func trimTrailingSpaces() {
        while text.last == " " || text.last == "\t" { text.removeLast() }
    }

    mutating func appendCell(_ runs: [InlineRun]) {
        var replacingSeparators = false
        for run in runs {
            let text = run.footnoteDisplay.map { "[\($0)]" } ?? run.text
            var remaining = text[...]
            while let separator = remaining.firstIndex(where: { $0 == "\t" || $0.isNewline }) {
                if separator != remaining.startIndex {
                    append(remaining[..<separator])
                    replacingSeparators = false
                }
                if !replacingSeparators { append(" ") }
                replacingSeparators = true
                remaining = remaining[remaining.index(after: separator)...]
            }
            if !remaining.isEmpty {
                append(remaining)
                replacingSeparators = false
            }
        }
    }

    mutating func appendMath(_ value: String) {
        var remaining = value[...]
        var startsAfterNewline = remaining.first?.isNewline == true
        if startsAfterNewline { remaining = remaining.dropFirst() }
        if path.isEmpty {
            if remaining.last?.isNewline == true { remaining = remaining.dropLast() }
            append(remaining)
            return
        }

        // The preprocessor captures raw source between the delimiters. Strip
        // container syntax only on lines that still carry their source prefix.
        var precedingBreak: Substring?
        while true {
            let end = remaining.firstIndex(where: \.isNewline) ?? remaining.endIndex
            let rawLine = remaining[..<end]
            let (line, leadingSpaces) = startsAfterNewline ? removingMathSourcePrefix(from: rawLine) : (rawLine, 0)
            // A final whitespace-only line belongs to the closing delimiter.
            if end == remaining.endIndex, startsAfterNewline, line.allSatisfy({ $0 == " " || $0 == "\t" }) { return }
            if let precedingBreak { append(precedingBreak) }
            if leadingSpaces > 0 { append(String(repeating: " ", count: leadingSpaces)) }
            append(line)
            if end == remaining.endIndex { return }
            let next = remaining.index(after: end)
            precedingBreak = remaining[end..<next]
            remaining = remaining[next...]
            startsAfterNewline = true
        }
    }

    private func removingMathSourcePrefix(from source: Substring) -> (Substring, Int) {
        var line = source
        var column = 0
        // A tab can span both structural indentation and the start of the TeX.
        var leadingSpaces = 0
        for id in path {
            switch containers[id].kind {
            case .quote:
                guard leadingSpaces <= 3 else { return (line, leadingSpaces) }
                let indent = line.prefix(3 - leadingSpaces).prefix(while: { $0 == " " })
                let marker = line[indent.endIndex...]
                guard marker.first == ">" else { return (line, leadingSpaces) }
                line = marker.dropFirst()
                column += leadingSpaces + indent.count + 1
                leadingSpaces = 0
                if line.first == " " {
                    line = line.dropFirst()
                    column += 1
                } else if line.first == "\t" {
                    line = line.dropFirst()
                    leadingSpaces = 3 - column % 4
                    column += 1
                }
            case .list:
                break
            case .item(_, let sourceIndent):
                let endColumn = column + sourceIndent
                var nextColumn = column + leadingSpaces
                var index = line.startIndex
                while nextColumn < endColumn, index < line.endIndex {
                    if line[index] == " " {
                        nextColumn += 1
                    } else if line[index] == "\t" {
                        nextColumn += 4 - nextColumn % 4
                    } else {
                        break
                    }
                    line.formIndex(after: &index)
                }
                if nextColumn < endColumn {
                    return index == line.endIndex ? (line[index...], 0) : (line, leadingSpaces)
                }
                line = line[index...]
                column = endColumn
                leadingSpaces = nextColumn - endColumn
            }
        }
        return (line, leadingSpaces)
    }

    mutating func append(_ value: some StringProtocol) {
        guard let last = value.last else { return }
        if continuationPrefix.isEmpty {
            text.append(contentsOf: value)
            if !last.isNewline {
                trailingBreaks = 0
            } else if let penultimate = value.dropLast().last {
                trailingBreaks = penultimate.isNewline ? 2 : 1
            } else {
                trailingBreaks = min(trailingBreaks + 1, 2)
            }
            return
        }

        var remaining = value[...]
        while !remaining.isEmpty {
            let lineEnd = remaining.firstIndex(where: \.isNewline) ?? remaining.endIndex
            let emptyLine = lineEnd == remaining.startIndex
            if trailingBreaks > 0 { text += emptyLine ? blankLinePrefix : continuationPrefix }
            text.append(contentsOf: remaining[..<lineEnd])
            if lineEnd == remaining.endIndex {
                trailingBreaks = 0
                break
            }
            text.append(remaining[lineEnd])
            trailingBreaks = emptyLine ? min(trailingBreaks + 1, 2) : 1
            remaining = remaining[remaining.index(after: lineEnd)...]
        }
    }
}
