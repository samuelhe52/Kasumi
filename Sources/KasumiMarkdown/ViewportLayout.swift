import Foundation

struct ViewportLayoutRequest {
    let height: CGFloat
    let anchor: ReadingAnchor?
}

/// Construction-local exact objects never enter a session cache or another
/// snapshot. Repeated placement passes reuse them while estimate corrections
/// reveal additional paragraphs above/below the anchor.
final class ViewportConstruction {
    var selected = Set<Int>()
    var exact: [Int: ParagraphLayout] = [:]
}

extension DocumentTypesetter {
    static func viewportLayout(
        _ document: ParsedDocument, width: CGFloat, style: Typography, insets: DocumentInsets,
        scrollableTables: Bool, preparation: ReflowPreparation, request: ViewportLayoutRequest
    ) -> DocumentLayout {
        // Tables have coupled cell widths/heights. Attachment dimensions depend
        // on resources and measure. Keep those documents on the exact path.
        let supported = document.blocks.allSatisfy { block in
            block.kind != .table && block.kind != .image && block.kind != .math && block.kind != .diagram
                && !block.runs.contains { !$0.traits.intersection([.image, .math]).isEmpty }
        }
        guard supported else {
            return layout(
                document, width: width, style: style, insets: insets, scrollableTables: scrollableTables,
                preparation: preparation)
        }
        let construction = ViewportConstruction()
        while true {
            let result = layout(
                document, width: width, style: style, insets: insets, scrollableTables: scrollableTables,
                preparation: preparation, viewport: construction)
            let index = ReadingPositionIndex(layout: result)
            let anchorY = request.anchor.flatMap { index.y(for: $0) } ?? 0
            let top = min(max(0, result.height - request.height), max(0, anchorY))
            let overscan = max(128, request.height * 0.5)
            let region = (top - overscan)..<(top + request.height + overscan)
            var selected = construction.selected
            if let anchor = request.anchor, let target = index.blockIndex(for: anchor) { selected.insert(target) }
            for (i, paragraph) in result.paragraphs.enumerated()
            where paragraph.estimatedPaintBounds.maxY > region.lowerBound
                && paragraph.estimatedPaintBounds.minY < region.upperBound
            {
                selected.insert(i)
            }
            guard selected != construction.selected else { return result }
            construction.selected = selected
        }
    }
}
