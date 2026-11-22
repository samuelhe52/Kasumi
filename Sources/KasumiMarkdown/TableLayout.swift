import CoreText
import Foundation

/// Geometry in document coordinates. Only the table's viewport participates in
/// page width; a reader can host its content in an independent scroll view.
/// IDs belong to this snapshot. Semantic queries use unscrolled coordinates:
/// add the horizontal content offset to input points, subtract it from output
/// rectangles, and clip highlights to `frame`.
public struct RenderedTable: Identifiable, Sendable {
    public let id: Int
    public let frame: CGRect
    public let contentWidth: CGFloat
    let textOffsets: Range<Int>
    public var isScrollable: Bool { contentWidth > frame.width + 0.5 }
}

enum TableColumns {
    /// Short columns keep their natural width. Prose columns get a comfortable
    /// minimum and bounded preferred width, rather than a share of the longest
    /// cell's unwrapped length. Measurements use the same styled cells as paint.
    static func widths(
        cells: [[NSAttributedString]], count: Int, measure: CGFloat, em: CGFloat,
        padding: CGFloat, scrollable: Bool
    ) -> [CGFloat] {
        var minimum = Array(repeating: padding * 2 + 1, count: count)
        var preferred = minimum
        for row in cells {
            for (column, cell) in row.enumerated() where column < count {
                let line = CTLineCreateWithAttributedString(cell)
                let natural = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                // UAX14 permits CJK wrapping without treating a whole sentence
                // as one word. Do not include trailing spaces in word measures.
                let text = cell.string
                var start = text.startIndex
                var word: CGFloat = 0
                for boundary in UnicodeLineBreak.boundaries(in: text) {
                    let utf8 = text.utf8.index(text.utf8.startIndex, offsetBy: boundary.offset)
                    guard let end = String.Index(utf8, within: text), end >= start else { continue }
                    var token = String(text[start..<end])
                    token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !token.isEmpty {
                        let range = NSRange(start..<end, in: text)
                        let trimmed = (text as NSString).range(of: token, options: [], range: range)
                        let run = cell.attributedSubstring(from: trimmed)
                        word = max(
                            word,
                            CGFloat(
                                CTLineGetTypographicBounds(
                                    CTLineCreateWithAttributedString(run), nil, nil, nil)))
                    }
                    start = end
                }
                // Very long URLs/identifiers can still wrap within a cell.
                let lower = min(natural, max(9 * em, min(word, 12 * em))) + padding * 2
                let upper = max(lower, min(natural, max(12 * em, measure * 0.6)) + padding * 2)
                minimum[column] = max(minimum[column], lower)
                preferred[column] = max(preferred[column], upper)
            }
        }
        let lower = minimum.reduce(0, +)
        let upper = preferred.reduce(0, +)
        if lower > measure {
            return scrollable ? minimum : minimum.map { $0 * measure / lower }
        }
        guard upper > lower else { return minimum }
        let fraction = min(1, (measure - lower) / (upper - lower))
        return zip(minimum, preferred).map { $0 + ($1 - $0) * fraction }
    }
}
