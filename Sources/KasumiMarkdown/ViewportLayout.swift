import Foundation

struct ViewportLayoutRequest {
    let height: CGFloat
    let anchor: ReadingAnchor?
}

/// Construction-local exact objects never enter a session cache or another
/// snapshot. Repeated placement passes reuse them while estimate corrections
/// reveal additional paragraphs above/below the anchor.
final class ViewportConstruction {
    private struct InputKey: Hashable {
        let block: Int
        let slot: Int
    }
    private enum Attachment {
        case rendered(NSAttributedString)
        case unavailable
    }
    var selected = Set<Int>()
    var exact: [Int: ParagraphLayout] = [:]
    var tableWidths: [Int: [CGFloat]] = [:]
    private var inputs: [InputKey: NSAttributedString] = [:]
    private var attachments: [Int: Attachment] = [:]

    func attributed(block: Int, slot: Int, build: () -> NSAttributedString) -> NSAttributedString {
        let key = InputKey(block: block, slot: slot)
        if let value = inputs[key] { return value }
        let value = build()
        inputs[key] = value
        return value
    }

    func attachment(block: Int, build: () -> NSAttributedString?) -> NSAttributedString? {
        if let value = attachments[block] {
            if case .rendered(let attributed) = value { return attributed }
            return nil
        }
        let value = build()
        attachments[block] = value.map(Attachment.rendered) ?? .unavailable
        return value
    }
}

extension DocumentTypesetter {
    static func viewportLayout(
        _ document: ParsedDocument, width: CGFloat, style: Typography, insets: DocumentInsets,
        scrollableTables: Bool, preparation: ReflowPreparation, request: ViewportLayoutRequest
    ) -> DocumentLayout {
        let construction = ViewportConstruction()
        construction.selected = preparation.selectedParagraphs(width: width, request: request)
        while true {
            var result = layout(
                document, width: width, style: style, insets: insets, scrollableTables: scrollableTables,
                preparation: preparation, viewport: construction, buildSemanticContent: false)
            let index = ReadingPositionIndex(layout: result)
            let anchorY = request.anchor.flatMap { index.y(for: $0) } ?? 0
            let top = min(max(0, result.height - request.height), max(0, anchorY))
            // Keep one screen ahead of scrolling. Publication includes prepaint,
            // so a half-screen window can expire while that work is in flight.
            let overscan = max(128, request.height)
            let region = (top - overscan)..<(top + request.height + overscan)
            var selected = Set<Int>()
            if let anchor = request.anchor, let target = index.blockIndex(for: anchor) { selected.insert(target) }
            for (i, paragraph) in result.paragraphs.enumerated()
            where paragraph.estimatedPaintBounds.maxY > region.lowerBound
                && paragraph.estimatedPaintBounds.minY < region.upperBound
            {
                selected.insert(i)
            }
            guard !selected.isSubset(of: construction.selected) else {
                preparation.rememberSelectedParagraphs(selected, width: width, request: request)
                // Intermediate placement passes need paragraph maps for anchors,
                // but only the published result needs the complete storage map.
                let semantic = preparation.semanticContent(paragraphs: result.paragraphs, storage: result.text)
                result.semanticContent = semantic
                result.textMap = semantic.textMap
                return result
            }
            construction.selected.formUnion(selected)
        }
    }
}
