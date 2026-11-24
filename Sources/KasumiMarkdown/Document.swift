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
    let id: Int
    var kind: Kind
    var runs: [InlineRun]
    var alignment: ParagraphAlignment?
    var level: Int = 0
    var prefix = ""
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
    /// Directory against which relative resources in this document resolve.
    var baseURL: URL? = nil
    let languageAnalysis: DocumentLanguageAnalysis
    init(blocks: [DocumentBlock], baseURL: URL? = nil, declaredLanguage: String? = nil) {
        self.blocks = blocks
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
        func append(
            _ node: any Markup, kind: DocumentBlock.Kind, runs: [InlineRun], level: Int = 0, prefix: String = "",
            language: String? = nil, alignment: ParagraphAlignment? = nil
        ) {
            var block = DocumentBlock(
                id: blocks.count, kind: kind, runs: runs, alignment: alignment, level: level, prefix: prefix,
                language: language)
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
                for child in node.children {
                    walk(child, quoteDepth: quoteDepth + 1, listDepth: listDepth, prefix: prefix)
                }
            case let list as OrderedList:
                for (index, item) in list.children.enumerated() {
                    walk(
                        item, quoteDepth: quoteDepth, listDepth: listDepth + 1,
                        prefix: "\(list.startIndex + UInt(index)).")
                }
            case is UnorderedList:
                for child in node.children {
                    walk(child, quoteDepth: quoteDepth, listDepth: listDepth + 1, prefix: "•")
                }
            case let item as ListItem:
                var marker = prefix
                if let check = item.checkbox { marker = check == .checked ? "☑" : "☐" }
                for (index, child) in item.children.enumerated() {
                    walk(child, quoteDepth: quoteDepth, listDepth: listDepth, prefix: index == 0 ? marker : "")
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
        return ParsedDocument(blocks: blocks, baseURL: baseURL, declaredLanguage: frontMatter.language)
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
            var run = InlineRun(image.plainText, traits: traits.union([.image]), destination: destination)
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
