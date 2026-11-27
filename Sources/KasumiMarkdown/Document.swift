import Foundation
import Markdown

struct InlineRun: Equatable, Sendable {
    enum Trait: String, Sendable {
        case strong, emphasis, code, strikethrough, link, math, highlight, footnote, image
        case `subscript`, superscript, underline
    }
    var text: String
    var traits: Set<Trait> = []
    var destination: String?
    var imageSource: String?
    var imageWidth: Double?
    var imageHeight: Double?
    var footnoteLabel: String?
    var footnoteDisplay: String?
    init(_ text: String, traits: Set<Trait> = [], destination: String? = nil) {
        self.text = text
        self.traits = traits
        self.destination = destination
    }
}

struct DocumentBlock: Identifiable, Sendable {
    enum Kind: String, Sendable { case paragraph, heading, quote, code, rule, table, image, math, diagram }

    struct Container: Sendable {
        enum Kind: Sendable { case quote, list, item(marker: String, sourceIndent: Int) }
        let parent: Int?
        let kind: Kind
        /// Index of the first block parsed inside this container, or of the next block if it has none.
        let firstBlock: Int
    }

    let id: Int
    var kind: Kind
    var runs: [InlineRun]
    var alignment: ParagraphAlignment?
    var level: Int = 0
    var prefix = ""
    /// Index of the innermost container in ParsedDocument.containers.
    var containerID: Int? = nil
    var language: String?
    var syntaxTokens: [CodeSyntax.Token] = []
    var codeSource: String?
    var rows: [[[InlineRun]]] = []
    var alignments: [String] = []
    var destination: String?
    var sourceLines: ClosedRange<Int>?
    var footnoteLabel: String?
    var footnoteDisplay: String?
    var text: String { runs.map(\.text).joined() }
}

struct ParsedDocument: Sendable {
    var blocks: [DocumentBlock]
    let containers: [DocumentBlock.Container]
    /// Directory against which relative resources in this document resolve.
    var baseURL: URL? = nil
    let languageAnalysis: DocumentLanguageAnalysis
    init(
        blocks: [DocumentBlock], containers: [DocumentBlock.Container] = [], baseURL: URL? = nil,
        declaredLanguage: String? = nil
    ) {
        self.blocks = blocks
        self.containers = containers
        self.baseURL = baseURL
        languageAnalysis = DocumentLanguageAnalysis.analyze(blocks, declaredLanguage: declaredLanguage)
    }
    var headings: [DocumentBlock] { blocks.filter { $0.kind == .heading } }
}

enum DocumentParser {
    static func parse(
        _ source: String, plainText: Bool = false, keepLineBreaks: Bool = false, baseURL: URL? = nil,
        plainTextOptions: PlainTextOptions = PlainTextOptions()
    ) -> ParsedDocument {
        if plainText && !plainTextOptions.parseAsMarkdown {
            return PlainTextParser.parse(source, options: plainTextOptions, baseURL: baseURL)
        }
        let frontMatter = DocumentFrontMatter.extract(source)
        let extensions = MarkdownExtensions(source: frontMatter.markdown)
        let hasDisplayMath = extensions.math.values.contains { $0.display }
        let ast = Markdown.Document(parsing: extensions.markdown)
        var blocks: [DocumentBlock] = []
        var htmlContext = HTMLFragment.Context()
        var containers: [DocumentBlock.Container] = []
        var containerID: Int?
        func withContainer(_ kind: DocumentBlock.Container.Kind, _ body: () -> Void) {
            let parent = containerID
            containerID = containers.count
            containers.append(.init(parent: parent, kind: kind, firstBlock: blocks.count))
            body()
            containerID = parent
        }

        // The exported number (or checkbox) isn't necessarily the source list
        // marker. Read its actual width and padding for multiline math only.
        let bytes = extensions.markdown.utf8
        var itemLine = 1
        var itemLineStart = bytes.startIndex
        func sourceIndent(for item: ListItem) -> Int {
            guard hasDisplayMath, let start = item.range?.lowerBound else { return 0 }
            while itemLine < start.line {
                guard let newline = bytes[itemLineStart...].firstIndex(where: { $0 == 10 || $0 == 13 }) else { return 0 }
                itemLineStart = bytes.index(after: newline)
                if bytes[newline] == 13, itemLineStart < bytes.endIndex, bytes[itemLineStart] == 10 {
                    bytes.formIndex(after: &itemLineStart)
                }
                itemLine += 1
            }
            guard let marker = bytes.index(itemLineStart, offsetBy: start.column - 1, limitedBy: bytes.endIndex),
                marker < bytes.endIndex
            else { return 0 }
            // Count the item's own leading indent, not the surrounding quote
            // or ancestor list padding already accounted for in the path.
            var column = 0
            var parentColumn = 0
            var afterQuoteMarker = false
            for byte in bytes[itemLineStart..<marker] {
                column += byte == 9 ? 4 - column % 4 : 1
                if afterQuoteMarker, byte == 32 || byte == 9 { parentColumn += 1 }
                afterQuoteMarker = byte == 62
                if afterQuoteMarker { parentColumn = column }
            }
            var parent = containerID
            while let id = parent {
                if case .quote = containers[id].kind { break }
                if case .item(_, let indent) = containers[id].kind { parentColumn += indent }
                parent = containers[id].parent
            }
            let leadingIndent = max(0, column - parentColumn)
            let digits = bytes[marker...].prefix(while: { (48...57).contains($0) })
            guard digits.endIndex < bytes.endIndex else { return 0 }
            let markerWidth = digits.count + 1
            var index = bytes.index(after: digits.endIndex)
            var padding = 0
            while index < bytes.endIndex, padding < 5 {
                if bytes[index] == 32 {
                    padding += 1
                } else if bytes[index] == 9 {
                    padding += 4 - (column + markerWidth + padding) % 4
                } else {
                    break
                }
                bytes.formIndex(after: &index)
            }
            let hasContent = index < bytes.endIndex && bytes[index] != 10 && bytes[index] != 13
            return leadingIndent + markerWidth + ((1...4).contains(padding) && hasContent ? padding : 1)
        }
        func append(
            _ node: any Markup, kind: DocumentBlock.Kind, runs: [InlineRun], level: Int = 0, prefix: String = "",
            language: String? = nil, alignment: ParagraphAlignment? = nil
        ) {
            var block = DocumentBlock(
                id: blocks.count, kind: kind, runs: runs, alignment: alignment, level: level, prefix: prefix,
                containerID: containerID, language: language)
            if let r = node.range {
                block.sourceLines = r.lowerBound.line...r.upperBound.line
                block.footnoteLabel = extensions.definitionLabelsByLine[r.lowerBound.line]
            }
            blocks.append(block)
        }
        func blockRuns(_ node: any Markup) -> (runs: [InlineRun], alignment: ParagraphAlignment?) {
            guard htmlContext.needsInlineTracking else {
                return (inline(node, extensions: extensions, keepLineBreaks: keepLineBreaks), nil)
            }
            let alignment = htmlContext.alignment
            let beganHidden = htmlContext.isHidden
            var context = HTMLFragment.InlineContext(blockContext: htmlContext)
            let runs = inlineChildren(node, context: &context, extensions: extensions, keepLineBreaks: keepLineBreaks)
            if let updated = context.blockContext { htmlContext = updated }
            return (runs, beganHidden ? htmlContext.alignment : alignment)
        }
        func walk(_ node: any Markup, quoteDepth: Int = 0, listDepth: Int = 0, prefix: String = "") {
            if htmlContext.isHidden, !(node is HTMLBlock), node.childCount == 0 || node is Markdown.Table {
                return
            }
            switch node {
            case let heading as Heading:
                let beganHidden = htmlContext.isHidden
                let (runs, alignment) = blockRuns(heading)
                if !beganHidden || !runs.isEmpty {
                    append(node, kind: .heading, runs: runs, level: heading.level, alignment: alignment)
                }
            case let paragraph as Paragraph:
                let (runs, alignment) = blockRuns(paragraph)
                guard !runs.isEmpty else { return }
                let math =
                    hasDisplayMath
                    ? extensions.math[paragraph.plainText.trimmingCharacters(in: .whitespacesAndNewlines)] : nil
                if let math, math.display {
                    append(node, kind: .math, runs: [InlineRun(math.text)])
                    blocks[blocks.count - 1].sourceLines = math.sourceLines
                } else if runs.count == 1, runs[0].traits.contains(.image) {
                    append(node, kind: .image, runs: runs, alignment: alignment)
                    blocks[blocks.count - 1].destination = runs[0].imageSource
                } else {
                    append(
                        node, kind: quoteDepth > 0 ? .quote : .paragraph, runs: runs, level: max(quoteDepth, listDepth),
                        prefix: prefix, alignment: alignment)
                }
            case let code as CodeBlock:
                let language = code.language?.trimmingCharacters(in: .whitespacesAndNewlines)
                append(
                    node, kind: language == "mermaid" ? .diagram : .code,
                    runs: [InlineRun(code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)],
                    language: language)
                blocks[blocks.count - 1].codeSource = code.code
                if blocks[blocks.count - 1].kind == .code {
                    blocks[blocks.count - 1].syntaxTokens = CodeSyntax.tokens(
                        in: blocks[blocks.count - 1].text, language: language)
                }
            case is ThematicBreak:
                append(node, kind: .rule, runs: [])
            case let table as Markdown.Table:
                append(node, kind: .table, runs: [])
                blocks[blocks.count - 1].rows =
                    [table.head.cells.map { inline($0, extensions: extensions, keepLineBreaks: true) }]
                    + table.body.rows.map { $0.cells.map { inline($0, extensions: extensions, keepLineBreaks: true) } }
                blocks[blocks.count - 1].alignments = table.columnAlignments.map { String(describing: $0) }
            case is BlockQuote:
                withContainer(.quote) {
                    for child in node.children {
                        walk(child, quoteDepth: quoteDepth + 1, listDepth: listDepth, prefix: prefix)
                    }
                }
            case let list as OrderedList:
                withContainer(.list) {
                    for (index, item) in list.children.enumerated() {
                        walk(
                            item, quoteDepth: quoteDepth, listDepth: listDepth + 1,
                            prefix: "\(list.startIndex + UInt(index)).")
                    }
                }
            case is UnorderedList:
                withContainer(.list) {
                    for child in node.children {
                        walk(child, quoteDepth: quoteDepth, listDepth: listDepth + 1, prefix: "•")
                    }
                }
            case let item as ListItem:
                var marker = prefix
                if let check = item.checkbox { marker = check == .checked ? "☑" : "☐" }
                withContainer(.item(marker: marker, sourceIndent: sourceIndent(for: item))) {
                    for (index, child) in item.children.enumerated() {
                        walk(child, quoteDepth: quoteDepth, listDepth: listDepth, prefix: index == 0 ? marker : "")
                    }
                }
            case let html as HTMLBlock:
                for part in HTMLFragment.blocks(html.rawHTML, context: &htmlContext) {
                    let body = part.kind == .paragraph
                    append(
                        node, kind: body && quoteDepth > 0 ? .quote : part.kind, runs: part.runs,
                        level: body ? max(quoteDepth, listDepth) : part.level,
                        prefix: body ? prefix : "", alignment: part.alignment)
                    if let firstLine = node.range?.lowerBound.line {
                        blocks[blocks.count - 1].sourceLines =
                            (firstLine + part.lines.lowerBound)...(firstLine + part.lines.upperBound)
                    }
                }
            default:
                for child in node.children { walk(child, quoteDepth: quoteDepth, listDepth: listDepth, prefix: prefix) }
            }
        }
        walk(ast)
        extensions.resolveFootnotes(in: &blocks)
        return ParsedDocument(
            blocks: blocks, containers: containers, baseURL: baseURL, declaredLanguage: frontMatter.language)
    }

    private static func inlineChildren(
        _ node: any Markup, traits: Set<InlineRun.Trait>, destination: String?,
        extensions: MarkdownExtensions, keepLineBreaks: Bool
    ) -> [InlineRun] {
        var context = HTMLFragment.InlineContext(traits: traits, destination: destination)
        return inlineChildren(node, context: &context, extensions: extensions, keepLineBreaks: keepLineBreaks)
    }

    private static func inlineChildren(
        _ node: any Markup, context: inout HTMLFragment.InlineContext,
        extensions: MarkdownExtensions, keepLineBreaks: Bool
    ) -> [InlineRun] {
        var runs: [InlineRun] = []
        for child in node.children {
            if let html = child as? InlineHTML {
                runs.append(contentsOf: context.runs(html.rawHTML))
            } else if !context.isHidden {
                runs.append(
                    contentsOf: inline(
                        child, traits: context.traits, destination: context.destination, extensions: extensions,
                        keepLineBreaks: keepLineBreaks))
            }
        }
        return runs
    }

    private static func inline(
        _ node: any Markup, traits: Set<InlineRun.Trait> = [], destination: String? = nil,
        extensions: MarkdownExtensions, keepLineBreaks: Bool
    ) -> [InlineRun] {
        switch node {
        case let text as Markdown.Text:
            return extensions.textRuns(text.string, traits: traits, destination: destination)
        case let code as InlineCode:
            return [InlineRun(code.code, traits: traits.union([.code]), destination: destination)]
        case is Strong:
            return inlineChildren(
                node, traits: traits.union([.strong]), destination: destination, extensions: extensions,
                keepLineBreaks: keepLineBreaks)
        case is Emphasis:
            return inlineChildren(
                node, traits: traits.union([.emphasis]), destination: destination, extensions: extensions,
                keepLineBreaks: keepLineBreaks)
        case is Strikethrough:
            return inlineChildren(
                node, traits: traits.union([.strikethrough]), destination: destination, extensions: extensions,
                keepLineBreaks: keepLineBreaks)
        case let link as Markdown.Link:
            return inlineChildren(
                node, traits: traits.union([.link]), destination: link.destination, extensions: extensions,
                keepLineBreaks: keepLineBreaks)
        case let image as Markdown.Image:
            var run = InlineRun(
                extensions.expandingMath(image.plainText), traits: traits.union([.image]), destination: destination)
            run.imageSource = image.source
            return [run]
        case is SoftBreak: return [InlineRun(keepLineBreaks ? "\n" : " ", traits: traits, destination: destination)]
        case is LineBreak: return [InlineRun("\n", traits: traits, destination: destination)]
        default:
            return inlineChildren(
                node, traits: traits, destination: destination, extensions: extensions, keepLineBreaks: keepLineBreaks)
        }
    }

}
