import CoreText
import Foundation

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

struct PlacedText {
    let paragraph: ParagraphLayout
    let origin: CGPoint
    let textOffset: Int
    var tableIndex: Int? = nil
    var bounds: CGRect {
        CGRect(
            x: origin.x, y: origin.y,
            width: paragraph.estimate?.width ?? (paragraph.lines.map { $0.origin.x + $0.width }.max() ?? 0),
            height: paragraph.height)
    }
    /// Unknown lines can paint outside their estimated body box, notably quote
    /// bars centered on cap height. Allow one line height on each edge, at least
    /// two points for the fixed-width quote stroke at tiny text sizes. This does
    /// not change placement or the scroll extent.
    var estimatedPaintBounds: CGRect {
        bounds.insetBy(dx: 0, dy: -(paragraph.estimate.map { max(2, $0.lineHeight) } ?? 0))
    }
}
struct PaintedRect {
    let rect: CGRect
    let color: PlatformColor
    var radius: CGFloat = 0
    var tableIndex: Int? = nil
}
struct PaintedRule {
    let start: CGPoint
    let end: CGPoint
    let color: PlatformColor
    var width: CGFloat = 1
    var tableIndex: Int? = nil
}
public struct DocumentInsets: Sendable, Equatable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
    public static let reader = DocumentInsets(top: 28, left: 40, bottom: 48, right: 40)
    public static let zero = DocumentInsets(top: 0, left: 0, bottom: 0, right: 0)
}
struct DocumentLayout {
    var width: CGFloat
    var height: CGFloat
    var text: NSAttributedString
    var textMap: DocumentTextMap
    var paragraphs: [PlacedText]
    var backgrounds: [PaintedRect]
    var rules: [PaintedRule]
    var headingPositions: [Int: CGFloat]
    var anchorPositions: [String: CGFloat]
    /// Occupied image rectangles, including inline images, for pagination/hit testing.
    var imageBounds: [CGRect]
    var paginationGroups: [Range<CGFloat>]
    var tables: [RenderedTable] = []
    var semanticContent: DocumentSemanticContent? = nil
}

enum DocumentTypesetter {
    static func layout(
        _ document: ParsedDocument, width: CGFloat, style: Typography, insets: DocumentInsets = .reader,
        scrollableTables: Bool = false, preparation: ReflowPreparation? = nil, viewport: ViewportConstruction? = nil,
        buildSemanticContent: Bool = true
    )
        -> DocumentLayout
    {
        let available = max(20, width - insets.left - insets.right)
        let measure = style.limitWidth ? min(available, style.widthLimit) : available
        let left = insets.left + (available - measure) / 2
        let theme = style.documentTheme
        let markerInset = style.profileValues.resolved(.markerInset).number! * style.size
        let markerGap = style.profileValues.resolved(.listMarkerGap).number!
        let bulletDiameter = style.profileValues.resolved(.listBulletSize).number! * style.size
        let quoteStep = markerInset + 3 + style.profileValues.resolved(.quoteBarGap).number!
        // A list shares marker columns across its numbered, bullet and task rows.
        // Include continuation paragraphs and preserve a distinct column per depth.
        var listInsets: [Int: CGFloat] = [:]
        var listSlots: [Int: CGFloat] = [:]
        var listStart = 0
        while listStart < document.blocks.count {
            let start = document.blocks[listStart]
            guard start.kind == .paragraph && start.level > 0 && start.footnoteLabel == nil else {
                listStart += 1
                continue
            }
            var end = listStart
            var slots: [Int: CGFloat] = [:]
            while end < document.blocks.count {
                let block = document.blocks[end]
                guard block.kind == .paragraph && block.level > 0 && block.footnoteLabel == nil else { break }
                let width =
                    block.prefix == "•" || block.prefix == "☐" || block.prefix == "☑"
                    ? max(style.size * 0.78, bulletDiameter)
                    : CGFloat(
                        CTLineGetTypographicBounds(
                            CTLineCreateWithAttributedString(style.attributed([InlineRun(block.prefix)])), nil, nil, nil
                        ))
                slots[block.level] = max(slots[block.level] ?? style.size * 0.78, width)
                end += 1
            }
            for index in listStart..<end {
                let depth = document.blocks[index].level
                listSlots[index] = slots[depth] ?? style.size * 0.78
                listInsets[index] = (1...depth).reduce(CGFloat(0)) {
                    $0 + markerInset + (slots[$1] ?? style.size * 0.78) + markerGap
                }
            }
            listStart = end
        }
        var y = insets.top
        let storage = NSMutableAttributedString(string: "")
        var paragraphs: [PlacedText] = []
        var backgrounds: [PaintedRect] = []
        var rules: [PaintedRule] = []
        var headings: [Int: CGFloat] = [:]
        var anchors: [String: CGFloat] = [:]
        var headingCounts: [String: Int] = [:]
        var imageBounds: [CGRect] = []
        var paginationGroups: [Range<CGFloat>] = []
        var tables: [RenderedTable] = []
        var paragraphValues = style.profileValues
        paragraphValues[.hangingPunctuation] = .flag(style.hangingPunctuation)
        paragraphValues[.autoRaggedNarrow] = .flag(style.narrowMeasureRagged)
        paragraphValues[.autoRaggedMeasureEm] = .number(style.narrowMeasureEm)
        let defaultFont = style.font()
        var preparationBlock = -1
        var preparationSlot = 0
        var forceExactParagraphs = false
        var deferBlock = false
        func attributed(
            _ runs: [InlineRun], size: Double? = nil, heading: Bool = false, code: Bool = false,
            headingLevel: Int? = nil, imageMaxWidth: CGFloat? = nil, allowPlaceholder: Bool = true
        ) -> NSAttributedString {
            let slot = preparationSlot
            preparationSlot += 1
            if allowPlaceholder, deferBlock, let preparation {
                return preparation.placeholder(block: preparationBlock, slot: slot, runs: runs)
            }
            func build() -> NSAttributedString {
                style.attributed(
                    runs, size: size, heading: heading, code: code, headingLevel: headingLevel,
                    baseURL: document.baseURL, imageMaxWidth: imageMaxWidth ?? measure)
            }
            func prepared() -> NSAttributedString {
                preparation?.attributed(
                    block: preparationBlock, slot: slot, runs: runs, size: size, heading: heading, code: code,
                    level: headingLevel, build: build) ?? build()
            }
            if let viewport { return viewport.attributed(block: preparationBlock, slot: slot, build: prepared) }
            return prepared()
        }
        func attachment(_ build: () -> NSAttributedString?) -> NSAttributedString? {
            if let viewport { return viewport.attachment(block: preparationBlock, build: build) }
            return build()
        }
        func diagram(_ block: DocumentBlock) -> NSAttributedString? {
            attachment {
                guard
                    let scene = try? MermaidTypesetter.layout(
                        block.text, size: 14, fontFamily: style.latinFamily, dark: style.dark,
                        textStyle: .native(style),
                        theme: style.documentTheme)
                else { return nil }
                return MermaidAttachment(
                    source: block.text, scene: scene, fontSize: 14, fontFamily: style.latinFamily, dark: style.dark,
                    maximumWidth: measure, renderScale: style.size / 16
                ).attributed()
            }
        }
        func place(
            _ attributed: NSAttributedString, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat,
            alignment: ParagraphAlignment, indent: CGFloat = 0, verbatim: Bool = false
        ) -> CGFloat {
            let offset = storage.length
            storage.append(attributed)
            storage.append(NSAttributedString(string: "\n"))
            let prepared = preparation?.paragraph(attributed, fontSize: size, verbatim: verbatim)
            let index = paragraphs.count
            let paragraph: ParagraphLayout
            if let existing = viewport?.exact[index] {
                paragraph = existing
            } else if let viewport, !forceExactParagraphs, !viewport.selected.contains(index),
                let preparation, let prepared
            {
                paragraph = ParagraphLayout(
                    attributed: prepared.attributed, lines: [],
                    height: preparation.height(
                        at: index, width: max(1, width), prepared: prepared, lineHeight: size * style.lineSpacing),
                    semanticContent: prepared.semanticContent, estimate: (max(1, width), size * style.lineSpacing))
            } else {
                paragraph = ParagraphTypesetter.layout(
                    attributed, width: max(1, width), fontSize: size, lineSpacing: style.lineSpacing,
                    alignment: alignment, indent: indent, verbatim: verbatim, profileValues: paragraphValues,
                    outerWidth: measure, baseEm: style.size, preparation: prepared, deferFragments: prepared != nil)
                viewport?.exact[index] = paragraph
                preparation?.measuredHeight(paragraph.height, at: index, width: max(1, width))
            }
            paragraphs.append(PlacedText(paragraph: paragraph, origin: CGPoint(x: x, y: y), textOffset: offset))
            for line in paragraph.lines {
                attributed.enumerateAttribute(.kasumiImage, in: line.range) { value, range, _ in
                    guard let image = value as? ImageAttachment else { return }
                    let offset = line.offset(forStringIndex: range.location)
                    imageBounds.append(
                        CGRect(
                            x: x + line.origin.x + offset, y: y + line.origin.y - image.size.height,
                            width: image.size.width, height: image.size.height))
                }
                attributed.enumerateAttribute(.kasumiDiagram, in: line.range) { value, range, _ in
                    guard let diagram = value as? MermaidAttachment else { return }
                    let top = y + line.origin.y - diagram.size.height
                    paginationGroups.append(top..<(top + diagram.size.height))
                }
            }
            return paragraph.height
        }
        var firstBodyParagraph = true
        for (blockIndex, block) in document.blocks.enumerated() {
            preparationBlock = blockIndex
            preparationSlot = 0
            let count: Int
            if block.kind == .table, let first = block.rows.first {
                count = block.rows.reduce(0) { $0 + min(first.count, $1.count) }
            } else {
                count = 1 + (block.prefix.isEmpty ? 0 : 1) + (block.footnoteLabel == nil ? 0 : 1)
            }
            let selected = viewport.map { viewport in
                (paragraphs.count..<(paragraphs.count + count)).contains { viewport.selected.contains($0) }
            } ?? true
            // Resource-dependent images and diagram fallbacks retain their exact
            // storage path. Other offscreen blocks need only semantic text.
            deferBlock = viewport != nil && !selected && block.kind != .image && block.kind != .diagram
                && !block.runs.contains(where: { $0.traits.contains(.image) })
                && !block.rows.joined().joined().contains(where: { $0.traits.contains(.image) })
            forceExactParagraphs = !deferBlock && [.table, .image, .math, .diagram].contains(block.kind)
            if block.kind == .heading {
                let size = style.size * style.headingScale(block.level)
                let fontSize = style.headingSize(block.level)
                if y > insets.top { y += size * style.headingSpaceBefore }
                firstBodyParagraph = true
                headings[block.id] = y
                let slug = anchorSlug(block.text)
                let duplicate = headingCounts[slug, default: 0]
                anchors[slug + (duplicate == 0 ? "" : "-\(duplicate)")] = y
                headingCounts[slug] = duplicate + 1
                y += place(
                    attributed(block.runs, size: fontSize, heading: true, headingLevel: block.level), x: left, y: y,
                    width: measure, size: size, alignment: .leading)
                y += size * style.headingSpaceAfter
            } else if block.kind == .image {
                y += place(
                    attributed(block.runs), x: left, y: y, width: measure, size: style.size, alignment: .centered)
                y += style.size * 0.65
            } else if block.kind == .math {
                let math = deferBlock
                    ? preparation!.placeholder(block: blockIndex, slot: 0, runs: block.runs)
                    : attachment {
                    MathAttachment(source: block.text, size: style.size, display: true, options: style.mathOptions)
                        .attributed(
                            color: style.textColor, fallbackFont: style.font(size: style.size * 0.88, code: true))
                }!
                y += style.size * 0.5
                y += place(
                    math, x: left,
                    y: y, width: measure, size: style.size, alignment: .centered)
                y += style.size * 0.65
            } else if block.kind == .diagram && style.mermaidEnabled, let diagram = diagram(block) {
                y += style.size * 0.5
                y += place(diagram, x: left, y: y, width: measure, size: style.size, alignment: .centered)
                y += style.size * 0.65
            } else if block.kind == .rule {
                y += 12
                rules.append(
                    PaintedRule(
                        start: CGPoint(x: left, y: y), end: CGPoint(x: left + measure, y: y), color: style.ruleColor))
                y += 20
            } else if block.kind == .table, let first = block.rows.first, !first.isEmpty {
                let grid = style.profileValues.resolved(.tableStyle).string == "grid"
                let columns = first.count
                let horizontalPadding = style.size * 0.6
                let verticalPadding = style.size * 0.3
                let cells = block.rows.enumerated().map { row, cells in
                    cells.map { attributed($0, heading: row == 0) }
                }
                let widths = deferBlock
                    ? (preparation?.cachedTableWidths(
                        block: blockIndex, rows: block.rows, width: measure, em: style.size,
                        padding: horizontalPadding, scrollable: scrollableTables)
                        ?? Array(repeating: measure / CGFloat(columns), count: columns))
                    : viewport?.tableWidths[blockIndex]
                    ?? {
                        func build() -> [CGFloat] {
                            TableColumns.widths(cells: cells, count: columns, measure: measure, em: style.size,
                                               padding: horizontalPadding, scrollable: scrollableTables)
                        }
                        return preparation?.tableWidths(
                            block: blockIndex, rows: block.rows, width: measure, em: style.size,
                            padding: horizontalPadding, scrollable: scrollableTables, build: build) ?? build()
                    }()
                if !deferBlock { viewport?.tableWidths[blockIndex] = widths }
                let tableWidth = widths.reduce(0, +)
                let tableLeft = left + max(0, (measure - tableWidth) / 2)
                let paragraphStart = paragraphs.count
                let backgroundStart = backgrounds.count
                let ruleStart = rules.count
                let top = y
                for (rowIndex, row) in block.rows.enumerated() {
                    let rowTop = y
                    var x = tableLeft
                    var height: CGFloat = style.size * style.lineSpacing + verticalPadding * 2
                    for (column, cell) in row.enumerated() where column < columns {
                        let attr = attributed(
                            cell, heading: rowIndex == 0,
                            imageMaxWidth: max(1, widths[column] - horizontalPadding * 2))
                        let alignment: ParagraphAlignment =
                            column < block.alignments.count && block.alignments[column].lowercased().contains("right")
                            ? .trailing
                            : column < block.alignments.count
                                && block.alignments[column].lowercased().contains("center") ? .centered : .leading
                        height = max(
                            height,
                            place(
                                attr, x: x + horizontalPadding, y: y + verticalPadding,
                                width: widths[column] - horizontalPadding * 2, size: style.size,
                                alignment: alignment) + verticalPadding * 2)
                        x += widths[column]
                    }
                    if rowIndex == 0 {
                        backgrounds.append(
                            PaintedRect(
                                rect: CGRect(x: tableLeft, y: y, width: tableWidth, height: height),
                                color: theme.color("table_header_background")!))
                    }
                    y += height
                    paginationGroups.append(rowTop..<y)
                    if rowIndex == 0 || grid {
                        rules.append(
                            PaintedRule(
                                start: CGPoint(x: tableLeft, y: y), end: CGPoint(x: tableLeft + tableWidth, y: y),
                                color: style.ruleColor))
                    }
                }
                if grid {
                    var edge = tableLeft
                    for column in 0...columns {
                        rules.append(
                            PaintedRule(
                                start: CGPoint(x: edge, y: top), end: CGPoint(x: edge, y: y), color: style.ruleColor))
                        if column < columns { edge += widths[column] }
                    }
                }
                for edge in [top, y] {
                    rules.append(
                        PaintedRule(
                            start: CGPoint(x: tableLeft, y: edge), end: CGPoint(x: tableLeft + tableWidth, y: edge),
                            color: style.textColor, width: 1.2))
                }
                let tableIndex = tables.count
                for index in paragraphStart..<paragraphs.count { paragraphs[index].tableIndex = tableIndex }
                for index in backgroundStart..<backgrounds.count { backgrounds[index].tableIndex = tableIndex }
                for index in ruleStart..<rules.count { rules[index].tableIndex = tableIndex }
                tables.append(
                    RenderedTable(
                        id: tableIndex,
                        frame: CGRect(x: tableLeft, y: top - 1, width: min(measure, tableWidth), height: y - top + 2),
                        contentWidth: tableWidth))
                y += style.size
            } else {
                let isCode = block.kind == .code || block.kind == .diagram
                var inset: CGFloat =
                    isCode
                    ? 14 : block.kind == .quote ? quoteStep * CGFloat(max(1, block.level)) : listInsets[blockIndex] ?? 0
                if let label = block.footnoteLabel, let display = block.footnoteDisplay {
                    // Styled like the in-text reference: script size, raised by the superscript shift.
                    let marker = attributed([InlineRun(display, traits: [.footnote])])
                    var markerAscent: CGFloat = 0
                    let markerWidth = CGFloat(
                        CTLineGetTypographicBounds(CTLineCreateWithAttributedString(marker), &markerAscent, nil, nil))
                    // Footnote text shares the quote text column; the marker hangs before it.
                    let markerSep = style.size * style.profileValues.resolved(.footnoteMarkSep).number!
                    inset = max(inset, quoteStep, markerWidth + markerSep)
                    if anchors["fn-" + label] == nil {
                        anchors["fn-" + label] = y
                        // Lines set their baseline at max(ascent, size); the raised marker's
                        // ascent can exceed the size, so lift it to share the body baseline.
                        _ = place(
                            marker, x: left + inset - markerSep - markerWidth, y: y - max(0, markerAscent - style.size),
                            width: max(1, markerWidth + 1), size: style.size, alignment: .leading)
                    }
                }
                let contentWidth = max(12, measure - inset - (isCode ? 14 : 0))
                if !block.prefix.isEmpty {
                    let slot = listSlots[blockIndex] ?? style.size * 0.78
                    let x = left + inset - markerGap - slot
                    let marker = NSMutableAttributedString(attributedString: attributed([InlineRun(block.prefix)], allowPlaceholder: false))
                    if block.prefix == "•" {
                        marker.addAttribute(
                            .foregroundColor, value: PlatformColor.clear,
                            range: NSRange(location: 0, length: marker.length))
                        let baseline = max(defaultFont.ascender, style.size)
                        backgrounds.append(
                            PaintedRect(
                                rect: CGRect(
                                    x: x + (slot - bulletDiameter) / 2,
                                    y: y + baseline - defaultFont.xHeight / 2 - bulletDiameter / 2,
                                    width: bulletDiameter, height: bulletDiameter), color: style.textColor,
                                radius: bulletDiameter / 2))
                    }
                    _ = place(marker, x: x, y: y, width: slot + 1, size: style.size, alignment: .trailing)
                }
                let top = y
                if isCode { y += 10 }
                if block.kind == .diagram && style.mermaidEnabled {
                    let reason: String
                    do {
                        _ = try MermaidTypesetter.layout(
                            block.text, size: 14, fontFamily: style.latinFamily, dark: style.dark,
                            textStyle: .native(style), theme: style.documentTheme)
                        reason = "unavailable"
                    } catch let error as MermaidError { reason = error.explanation } catch {
                        reason = "layout unavailable"
                    }
                    let caption = attributed([InlineRun("Mermaid · not rendered: " + reason)], size: style.size * 0.75)
                    y +=
                        place(
                            caption, x: left + inset, y: y, width: contentWidth, size: style.size * 0.75,
                            alignment: .leading) + 4
                }
                let attr = attributed(
                    block.runs, size: style.size * (isCode ? 0.88 : 1), code: isCode, imageMaxWidth: contentWidth)
                let alignment: ParagraphAlignment = isCode ? .leading : style.alignment
                let bodyParagraph =
                    block.kind == .paragraph && block.level == 0 && block.prefix.isEmpty && block.footnoteLabel == nil
                if bodyParagraph { y += style.size * style.paraSpaceBefore }
                let firstRun =
                    attr.length > 0
                    ? attr.attribute(.kasumiParagraphRun, at: 0, effectiveRange: nil) as? ParagraphRunStyle : nil
                let firstRunEm = firstRun.map { CTFontGetSize($0.baseFont) } ?? defaultFont.pointSize
                let indent =
                    bodyParagraph && (style.indentFirstParagraph || !firstBodyParagraph)
                    ? firstRunEm * style.firstLineIndent : 0
                y += place(
                    attr, x: left + inset, y: y, width: contentWidth, size: style.size * (isCode ? 0.88 : 1),
                    alignment: alignment, indent: indent, verbatim: isCode)
                if block.kind == .quote, let placed = paragraphs.last, let first = placed.paragraph.lines.first,
                    let last = placed.paragraph.lines.last
                {
                    // Lines put all their leading below the baseline, so center the bar
                    // on the body font's cap height instead, one line height per line.
                    let capMiddle = defaultFont.capHeight / 2
                    let halfLine = style.size * style.lineSpacing / 2
                    let barTop = placed.origin.y + first.origin.y - capMiddle - halfLine
                    let barBottom = placed.origin.y + last.origin.y - capMiddle + halfLine
                    for depth in 0..<max(1, block.level) {
                        let x = left + CGFloat(depth) * quoteStep + markerInset + 1.5
                        rules.append(
                            PaintedRule(
                                start: CGPoint(x: x, y: barTop), end: CGPoint(x: x, y: barBottom),
                                color: style.ruleColor, width: 3))
                    }
                }
                if bodyParagraph { firstBodyParagraph = false }
                if isCode {
                    y += 10
                    backgrounds.append(
                        PaintedRect(
                            rect: CGRect(x: left, y: top, width: measure, height: y - top),
                            color: theme.color("code_block_background")!))
                }
                let next = blockIndex + 1 < document.blocks.count ? document.blocks[blockIndex + 1] : nil
                let nextIsBody =
                    next?.kind == .paragraph && next?.level == 0 && next?.prefix.isEmpty == true
                    && next?.footnoteLabel == nil
                y +=
                    style.size
                    * (bodyParagraph
                        ? (nextIsBody ? style.paraSpaceBetween : style.paraSpaceAfter) : style.paraSpaceAfter)
            }
        }
        let semantic = buildSemanticContent ? preparation?.semanticContent(paragraphs: paragraphs, storage: storage) : nil
        let textMap = buildSemanticContent
            ? (semantic?.textMap ?? DocumentTextMap(storage)) : DocumentTextMap(NSAttributedString(string: ""))
        return DocumentLayout(
            width: width, height: y + insets.bottom, text: storage,
            textMap: textMap,
            paragraphs: paragraphs, backgrounds: backgrounds, rules: rules, headingPositions: headings,
            anchorPositions: anchors, imageBounds: imageBounds, paginationGroups: paginationGroups, tables: tables,
            semanticContent: semantic)
    }

    static func anchorSlug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let filtered = String(text.lowercased().unicodeScalars.filter { allowed.contains($0) })
        return filtered.split(whereSeparator: \.isWhitespace).joined(separator: "-")
    }

    /// Draw in a top-left, downward-positive graphics coordinate space.
    static func draw(
        _ layout: DocumentLayout, in context: CGContext, sourceRange: Range<CGFloat>? = nil,
        excludingScrollableTables: Bool = false, tableIndex: Int? = nil
    ) {
        func include(_ index: Int?) -> Bool {
            if let tableIndex { return index == tableIndex }
            if excludingScrollableTables, let index { return !layout.tables[index].isScrollable }
            return true
        }
        func clipTable(_ index: Int?) {
            if tableIndex == nil, let index, layout.tables[index].isScrollable {
                context.clip(to: layout.tables[index].frame)
            }
        }
        let clip = context.boundingBoxOfClipPath
        for background in layout.backgrounds where include(background.tableIndex) && background.rect.intersects(clip) {
            context.saveGState()
            defer { context.restoreGState() }
            clipTable(background.tableIndex)
            context.setFillColor(background.color.cgColor)
            if background.radius > 0 {
                context.addPath(
                    CGPath(
                        roundedRect: background.rect, cornerWidth: background.radius, cornerHeight: background.radius,
                        transform: nil))
                context.fillPath()
            } else {
                context.fill(background.rect)
            }
        }
        for rule in layout.rules where include(rule.tableIndex) {
            let bounds = CGRect(
                x: min(rule.start.x, rule.end.x), y: min(rule.start.y, rule.end.y),
                width: abs(rule.end.x - rule.start.x), height: abs(rule.end.y - rule.start.y)
            ).insetBy(dx: -rule.width / 2, dy: -rule.width / 2)
            guard bounds.intersects(clip) else { continue }
            context.saveGState()
            defer { context.restoreGState() }
            clipTable(rule.tableIndex)
            context.setStrokeColor(rule.color.cgColor)
            context.setLineWidth(rule.width)
            context.move(to: rule.start)
            context.addLine(to: rule.end)
            context.strokePath()
        }
        for item in layout.paragraphs where include(item.tableIndex) {
            context.saveGState()
            defer { context.restoreGState() }
            clipTable(item.tableIndex)
            for line in item.paragraph.lines {
                if let sourceRange {
                    let top = item.origin.y + line.origin.y - line.ascent
                    let bottom = item.origin.y + line.origin.y + line.descent
                    guard bottom > sourceRange.lowerBound, top < sourceRange.upperBound else { continue }
                }
                // Include a generous em-sized allowance for italic glyph ink
                // beyond advances, accents and decoration. This keeps a page
                // export from repainting every off-page CTLine in the document.
                let ink = CGRect(
                    x: item.origin.x + line.origin.x, y: item.origin.y + line.origin.y - line.ascent, width: line.width,
                    height: line.ascent + line.descent
                ).insetBy(dx: -max(4, line.ascent), dy: -4)
                guard ink.intersects(clip) else { continue }
                context.saveGState()
                context.translateBy(x: item.origin.x + line.origin.x, y: item.origin.y + line.origin.y)
                context.scaleBy(x: 1, y: -1)
                context.textPosition = .zero
                let attributes = item.paragraph.attributed
                func decorationRect(_ range: NSRange, ascent: CGFloat, descent: CGFloat) -> CGRect {
                    let start = line.offset(forStringIndex: range.location)
                    let end = line.offset(forStringIndex: NSMaxRange(range), affinity: .precedingFragment)
                    return CGRect(
                        x: min(start, end), y: -descent - 1, width: abs(end - start), height: ascent + descent + 2)
                }
                attributes.enumerateAttribute(.backgroundColor, in: line.range) { value, range, _ in
                    guard let color = value as? PlatformColor else { return }
                    var ascent: CGFloat = 0
                    var descent: CGFloat = 0
                    attributes.enumerateAttributes(in: range) { values, _, _ in
                        guard let font = values[.font] as? PlatformFont else { return }
                        let baseline = values[.baselineOffset] as? CGFloat ?? 0
                        ascent = max(ascent, font.ascender + baseline)
                        descent = max(descent, -font.descender - baseline)
                    }
                    context.setFillColor(color.cgColor)
                    context.fill(decorationRect(range, ascent: ascent, descent: descent))
                }
                attributes.enumerateAttribute(.kasumiCodeCapsule, in: line.range) { value, range, _ in
                    guard let capsule = value as? InlineCodeCapsule else { return }
                    context.setFillColor(capsule.color.cgColor)
                    var rect = decorationRect(range, ascent: capsule.ascent, descent: capsule.descent)
                    let fragments = line.fragments.filter { NSIntersectionRange($0.range, range).length > 0 }
                    if let left = fragments.map({ $0.x - $0.capsuleLeft }).min(),
                        let right = fragments.map({ $0.x + $0.width + $0.capsuleRight }).max()
                    {
                        rect.origin.x = left
                        rect.size.width = max(0, right - left)
                    }
                    context.addPath(
                        CGPath(
                            roundedRect: rect, cornerWidth: capsule.radius, cornerHeight: capsule.radius, transform: nil
                        ))
                    context.fillPath()
                }
                if line.fragments.isEmpty {
                    CTLineDraw(line.line, context)
                } else {
                    ParagraphGlyphDrawing.draw(line, attributed: attributes, in: context)
                }
                attributes.enumerateAttribute(.kasumiImage, in: line.range) { value, range, _ in
                    guard let image = value as? ImageAttachment else { return }
                    let x = line.offset(forStringIndex: range.location)
                    context.saveGState()
                    context.translateBy(x: x, y: 0)
                    image.draw(in: context)
                    context.restoreGState()
                }
                attributes.enumerateAttribute(.kasumiMath, in: line.range) { value, range, _ in
                    guard let math = value as? MathAttachment else { return }
                    let x = line.offset(forStringIndex: range.location)
                    context.saveGState()
                    context.translateBy(x: x, y: 0)
                    // Formula glyphs inherit the current document foreground.
                    let color =
                        attributes.attribute(.kasumiMathColor, at: range.location, effectiveRange: nil)
                        as? PlatformColor ?? .black
                    math.result.box.draw(in: context, color: color.cgColor)
                    context.restoreGState()
                }
                attributes.enumerateAttribute(.kasumiDiagram, in: line.range) { value, range, _ in
                    guard let diagram = value as? MermaidAttachment else { return }
                    let x = line.offset(forStringIndex: range.location)
                    context.saveGState()
                    context.translateBy(x: x, y: 0)
                    diagram.draw(in: context)
                    context.restoreGState()
                }
                context.restoreGState()
            }
            for underline in item.paragraph.underlines {
                let rect = underline.rect.offsetBy(dx: item.origin.x, dy: item.origin.y)
                guard rect.intersects(clip) else { continue }
                context.setFillColor(underline.color.cgColor)
                context.fill(rect)
            }
        }
    }
}
