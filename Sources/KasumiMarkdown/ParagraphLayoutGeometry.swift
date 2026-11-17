import Foundation

/// Width-dependent values only. Core Text lines, typesetters and mutable fragment
/// stores are recreated for each snapshot that uses these measurements.
final class ParagraphLayoutGeometry {
    struct Request: Equatable {
        let width: CGFloat
        let fontSize: CGFloat
        let lineSpacing: CGFloat
        let alignment: ParagraphAlignment
        let indent: CGFloat
        let profileValues: ProfileValues?
        let outerWidth: CGFloat?
        let baseEm: CGFloat?
    }
    private struct Line {
        let range: NSRange
        let origin: CGPoint
        let ascent: CGFloat
        let descent: CGFloat
        let width: CGFloat
        let fragments: [FragmentGeometry]
        let adjustmentRatio: Float
    }
    let request: Request
    private let lines: [Line]
    private let height: CGFloat
    private let autoRagged: Bool
    private let diagnostics: [String]
    private let underlines: [PaintedRect]

    init?(_ paragraph: ParagraphLayout, request: Request) {
        // Hyphen and legacy lines retain their existing snapshot-local path.
        guard paragraph.lines.allSatisfy({ $0.hyphen == nil && !$0.fragments.isEmpty }) else { return nil }
        self.request = request
        lines = paragraph.lines.map {
            Line(range: $0.range, origin: $0.origin, ascent: $0.ascent, descent: $0.descent,
                 width: $0.width, fragments: $0.fragments.geometry, adjustmentRatio: $0.adjustmentRatio)
        }
        height = paragraph.height
        autoRagged = paragraph.autoRagged
        diagnostics = paragraph.diagnostics
        underlines = paragraph.underlines
    }

    func paragraph(_ preparation: ParagraphPreparation) -> ParagraphLayout {
        let factory = ParagraphFragmentFactory(preparation.attributed, glyphPaintCache: preparation.glyphPaintCache)
        let shaped = lines.map { line in
            let fragments = ShapedFragments(geometry: line.fragments, factory: factory)
            return ShapedLine(
                range: line.range, factory: factory, origin: line.origin, ascent: line.ascent,
                descent: line.descent, width: line.width, fragments: fragments, adjustmentRatio: line.adjustmentRatio)
        }
        return ParagraphLayout(
            attributed: preparation.attributed, lines: shaped, height: height, autoRagged: autoRagged,
            diagnostics: diagnostics, underlines: underlines, semanticContent: preparation.semanticContent)
    }
}
