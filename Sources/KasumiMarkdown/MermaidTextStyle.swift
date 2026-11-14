import Foundation
import CoreGraphics
import CoreText

/// Font roles belong to text measurement requests, independently of display
/// command paint roles. Uniform metrics reproduce the frozen core oracle;
/// these metrics match the 14-point label fonts in the reference measurements.
struct MermaidTextStyle {
    private var native: Bool
    private var size: CGFloat
    private var family: String
    private var hanFamily: String
    private var hanScale: CGFloat

    static func uniform(size: CGFloat, fontFamily: String) -> Self {
        Self(native: false, size: size, family: fontFamily, hanFamily: "", hanScale: 1)
    }
    static func native(_ typography: Typography) -> Self {
        Self(native: true, size: 14, family: typography.latinFamily, hanFamily: typography.hanFamily, hanScale: typography.hanScale)
    }
    private func pointSize(_ role: Int) -> CGFloat {
        guard native else { return size }
        switch role {
        case 3: return 10.5
        case 4: return 7.875
        case 5: return 6.125
        case 10: return 15.75
        case 11: return 12.25
        case 12: return 9.625
        case 13: return 14.875
        case 14: return 21.875
        default: return 14
        }
    }
    private func attributed(_ text: String, role: Int, color: CGColor) -> NSAttributedString {
        var typography = Typography()
        typography.latinFamily = family.isEmpty ? "New York" : family
        if typography.latinFamily == "SF Pro Text" { typography.latinFamily = "SF Pro" }
        let pointSize = pointSize(role)
        let bold = native && (role == 8 || role == 9)
        let string = NSMutableAttributedString(string: text, attributes: [.font: typography.font(size: pointSize, strong: bold), NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
        if native && !hanFamily.isEmpty {
            typography.hanFamily = hanFamily
            var offset = 0
            for character in text {
                let count = String(character).utf16.count
                if ParagraphBreaker.isCJK(character) {
                    string.addAttribute(.font, value: typography.font(size: pointSize * hanScale, strong: bold, cjk: true), range: NSRange(location: offset, length: count))
                }
                offset += count
            }
        }
        return string
    }
    func measure(_ text: String, role: Int) -> CGSize {
        let line = CTLineCreateWithAttributedString(attributed(text, role: role, color: CGColor(gray: 0, alpha: 1)))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        var width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        if native { width -= CTLineGetTrailingWhitespaceWidth(line) }
        let natural = ascent + descent + (native ? leading : 0)
        let minimum: CGFloat = native ? ((role == 7 || role == 9 || role == 16) ? 21 : 0) : size
        return CGSize(width: max(0, width), height: max(minimum, natural))
    }
    func draw(_ text: String, in rect: CGRect, role: Int, color: CGColor, context: CGContext) {
        let line = CTLineCreateWithAttributedString(attributed(text, role: role, color: color))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let extra = native ? max(0, rect.height - ascent - descent - leading) / 2 : 0
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY + ascent + extra)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity; context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
