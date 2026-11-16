import CoreText
import Foundation

extension NSAttributedString.Key {
    static let kasumiUnderline = NSAttributedString.Key("KasumiUnderline")
    static let kasumiUnderlineColor = NSAttributedString.Key("KasumiUnderlineColor")
}

/// Shared, cached geometry for ordinary underlines and link indicators.
enum TextUnderline {
    static func normalized(_ attributed: NSAttributedString) -> NSAttributedString {
        let ctStyle = NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)
        let ctColor = NSAttributedString.Key(kCTUnderlineColorAttributeName as String)
        var copy: NSMutableAttributedString?
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { values, range, _ in
            guard let style = (values[.underlineStyle] ?? values[ctStyle]) as? NSNumber else { return }
            if copy == nil { copy = NSMutableAttributedString(attributedString: attributed) }
            copy?.removeAttribute(.underlineStyle, range: range)
            copy?.removeAttribute(.underlineColor, range: range)
            copy?.removeAttribute(ctStyle, range: range)
            copy?.removeAttribute(ctColor, range: range)
            if style.intValue != 0 {
                copy?.addAttribute(.kasumiUnderline, value: true, range: range)
                if let color = values[.underlineColor] ?? values[ctColor] {
                    copy?.addAttribute(.kasumiUnderlineColor, value: color, range: range)
                }
            }
        }
        return copy ?? attributed
    }

    static func applying(to paragraph: ParagraphLayout, fontSize: CGFloat) -> ParagraphLayout {
        var result = paragraph
        result.underlines = layout(paragraph, fontSize: fontSize)
        return result
    }

    private static func color(_ value: Any?) -> PlatformColor? {
        guard let value else { return nil }
        if let color = value as? PlatformColor { return color }
        guard CFGetTypeID(value as CFTypeRef) == CGColor.typeID else { return nil }
        return PlatformColor(cgColor: value as! CGColor)
    }

    private static func layout(_ paragraph: ParagraphLayout, fontSize: CGFloat) -> [PaintedRect] {
        let attributed = paragraph.attributed
        var result: [PaintedRect] = []
        var clearance: UnderlineClearance?
        for line in paragraph.lines {
            var pending: CGRect?
            var pendingColor: PlatformColor?
            var pendingDestination: String?
            var pendingSolid = true
            var pendingEm = fontSize
            var dashOrigin: CGFloat = 0
            var previousEnd: Int?

            func flush() {
                guard let rect = pending, let color = pendingColor else { return }
                let paint = color.withAlphaComponent(pendingSolid ? 0.4 : 0.7)
                if clearance == nil { clearance = UnderlineClearance() }
                clearance?.subtract(from: rect, line: line, attributed: attributed, em: pendingEm) { part in
                    if pendingSolid {
                        result.append(PaintedRect(rect: part, color: paint))
                    } else {
                        let dash = pendingEm * 0.3
                        let period = dash + pendingEm * 0.15
                        var x = dashOrigin + floor((part.minX - dashOrigin) / period) * period
                        while x < part.maxX {
                            let left = max(x, part.minX)
                            let right = min(x + dash, part.maxX)
                            if right > left {
                                result.append(
                                    PaintedRect(
                                        rect: CGRect(x: left, y: part.minY, width: right - left, height: part.height),
                                        color: paint))
                            }
                            x += period
                        }
                    }
                }
                pending = nil
                pendingColor = nil
            }

            attributed.enumerateAttributes(in: line.range) { values, range, _ in
                let run = values[.kasumiParagraphRun] as? ParagraphRunStyle
                let flags = run?.flags ?? 0
                let explicit = (values[.kasumiUnderline] as? NSNumber)?.boolValue == true
                let destination = values[.link] as? String
                let linked = destination != nil && flags & 0x28 == 0x08
                guard explicit || linked, flags & 0x20 == 0, values[.kasumiImage] == nil,
                    let color = color(
                        values[.kasumiUnderlineColor] ?? values[.kasumiMathColor] ?? values[.foregroundColor])
                else {
                    flush()
                    previousEnd = nil
                    return
                }
                let solid: Bool
                switch URL(string: destination ?? "")?.scheme?.lowercased() {
                case "http", "https": solid = true
                default: solid = destination == nil || destination!.hasPrefix("#")
                }
                // Han substitutions share the paragraph's stripe; scripts use their
                // own em and baseline. Raw attributed input also retains its baseline.
                let script = flags & 0x610 != 0
                let em = script ? CTFontGetSize(run!.baseFont) : fontSize
                let baseline = script || run == nil ? (values[.baselineOffset] as? NSNumber)?.doubleValue ?? 0 : 0
                let start = line.offset(forStringIndex: range.location)
                var end = line.offset(forStringIndex: NSMaxRange(range), affinity: .precedingFragment)
                if NSMaxRange(range) == NSMaxRange(line.range), let hyphen = line.hyphen {
                    end = max(end, hyphen.x + hyphen.width)
                }
                let rect = CGRect(
                    x: line.origin.x + min(start, end), y: line.origin.y - baseline + em * 0.185,
                    width: abs(end - start), height: max(0.5, em * 0.07))
                guard rect.width > 0 else { return }
                if let current = pending, pendingDestination == destination, pendingColor == color,
                    current.minY == rect.minY, current.height == rect.height,
                    abs(current.maxX - rect.minX) < 0.001
                {
                    pending = CGRect(
                        x: current.minX, y: current.minY, width: rect.maxX - current.minX, height: current.height)
                } else {
                    let continues = pending != nil && pendingDestination == destination && previousEnd == range.location
                    flush()
                    if !continues { dashOrigin = rect.minX }
                    pending = rect
                    pendingColor = color
                    pendingDestination = destination
                    pendingSolid = solid
                    pendingEm = em
                }
                previousEnd = NSMaxRange(range)
            }
            flush()
        }
        return result
    }
}
