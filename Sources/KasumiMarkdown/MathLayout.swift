import Foundation
import CoreText
import CoreGraphics

enum MathDrawing {
    case text(CTLine, CGPoint)
    case glyph(CTFont, CGGlyph, CGPoint)
    case rule(CGRect)
    case colored(UInt32, [MathDrawing])

    func translated(x: CGFloat, y: CGFloat) -> MathDrawing {
        switch self {
        case let .text(line, p): return .text(line, CGPoint(x: p.x + x, y: p.y + y))
        case let .glyph(font, glyph, p): return .glyph(font, glyph, CGPoint(x: p.x + x, y: p.y + y))
        case let .rule(rect): return .rule(rect.offsetBy(dx: x, dy: y))
        case let .colored(color, children): return .colored(color, children.map { $0.translated(x: x, y: y) })
        }
    }
}

struct MathBox {
    var width: CGFloat = 0
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var italicCorrection: CGFloat = 0
    var drawings: [MathDrawing] = []
    var height: CGFloat { ascent + descent }

    mutating func add(_ box: MathBox, x: CGFloat, y: CGFloat = 0) {
        drawings += box.drawings.map { $0.translated(x: x, y: y) }
        width = max(width, x + box.width)
        ascent = max(ascent, y + box.ascent)
        descent = max(descent, box.descent - y)
    }
    func draw(in context: CGContext, color: CGColor) {
        context.saveGState()
        context.setFillColor(color)
        context.setStrokeColor(color)
        context.textMatrix = .identity
        func paint(_ drawings: [MathDrawing]) {
          for drawing in drawings {
            switch drawing {
            case let .text(line, point):
                context.textPosition = point
                CTLineDraw(line, context)
            case let .glyph(font, glyph, point):
                var glyph = glyph, point = point
                CTFontDrawGlyphs(font, &glyph, &point, 1, context)
            case let .rule(rect): context.fill(rect)
            case let .colored(rgba, children):
                context.saveGState()
                context.setFillColor(CGColor(red: CGFloat(rgba >> 24 & 255) / 255, green: CGFloat(rgba >> 16 & 255) / 255, blue: CGFloat(rgba >> 8 & 255) / 255, alpha: CGFloat(rgba & 255) / 255))
                paint(children)
                context.restoreGState()
            }
          }
        }
        paint(drawings)
        context.restoreGState()
    }
}

struct MathLayoutResult {
    let box: MathBox
    let diagnostics: [String]
}

enum MathTypesetter {
    static func layout(_ source: String, size: CGFloat, display: Bool, options: MathProfileOptions = .init()) -> MathLayoutResult {
        MathLayoutEngine(options: options).layout(source, size: size, display: display)
    }
}

/// Each engine captures one document's profile. Paint operations
/// retain their CTFont, so later profile changes cannot alter existing layouts.
private final class MathLayoutEngine {
    let options: MathProfileOptions
    private var diagnostics: [String] = []

    init(options: MathProfileOptions) { self.options = options }

    private func missingGlyph(_ scalar: Unicode.Scalar) {
        diagnostics.append("Math font \(options.font.rawValue) has no glyph for U+\(String(scalar.value, radix: 16, uppercase: true))")
    }

    func layout(_ source: String, size: CGFloat, display: Bool) -> MathLayoutResult {
        var parser = MathParser(source)
        let parsed = parser.parse()
        guard parsed.diagnostics.isEmpty else { return MathLayoutResult(box: MathBox(), diagnostics: parsed.diagnostics) }
        let box = layout(parsed.root, size: size, level: 0, display: display, alphabet: .italic)
        return MathLayoutResult(box: diagnostics.isEmpty ? box : MathBox(), diagnostics: diagnostics)
    }

    private func nextSize(_ size: CGFloat, level: Int) -> CGFloat {
        let metrics = MathFont.metrics(size: size, face: options.font)
        if level == 0 { return size * metrics.scriptPercentScaleDown }
        if level == 1 { return size * metrics.scriptScriptPercentScaleDown / metrics.scriptPercentScaleDown }
        return size
    }

    private func text(_ value: String, size: CGFloat, alphabet: MathAlphabet = .upright, level: Int = 0) -> MathBox {
        let font = MathFont.font(size: size, face: options.font)
        var result = MathBox()
        for scalar in value.unicodeScalars {
            let styled = styled(scalar, alphabet: alphabet)
            let units = Array(String(styled).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            guard CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), glyphs.contains(where: { $0 != 0 }) else {
                missingGlyph(styled)
                return MathBox()
            }
            var g = MathFont.scriptVariant(glyph: glyphs.first(where: { $0 != 0 }) ?? 0, level: level, face: options.font)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &advance, 1)
            let bounds = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &g, nil, 1)
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(scalar)
            let box = MathBox(width: advance.width + (isSpace ? 0 : MathFont.italicCorrection(glyph: g, size: size, face: options.font)), ascent: isSpace ? 0 : max(0, bounds.maxY), descent: isSpace ? 0 : max(0, -bounds.minY), italicCorrection: MathFont.italicCorrection(glyph: g, size: size, face: options.font), drawings: isSpace ? [] : [.glyph(font, g, .zero)])
            let x = result.width
            result.add(box, x: x)
            result.italicCorrection = box.italicCorrection
        }
        return result
    }

    private func glyph(_ value: String, size: CGFloat, minimumHeight: CGFloat = 0, centered: Bool = false) -> MathBox {
        guard !value.isEmpty else { return MathBox() }
        let font = MathFont.font(size: size, face: options.font)
        let units = Array(value.utf16)
        guard units.count == 1 else { return text(value, size: size) }
        var g: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, units, &g, 1) else { return text(value, size: size) }
        if let variant = MathFont.verticalVariant(glyph: g, minimumHeight: minimumHeight, size: size, face: options.font) { g = variant.glyph }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &advance, 1)
        let bounds = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &g, nil, 1)
        let shift = centered ? MathFont.metrics(size: size, face: options.font).axisHeight - bounds.midY : 0
        return MathBox(width: advance.width, ascent: max(0, bounds.maxY + shift), descent: max(0, -bounds.minY - shift), italicCorrection: MathFont.italicCorrection(glyph: g, size: size, face: options.font), drawings: [.glyph(font, g, CGPoint(x: 0, y: shift))])
    }

    private func atomClass(_ node: MathNode) -> MathAtomClass {
        switch node {
        case let .symbol(_, kind): return kind
        case let .scripts(base, _, _, _), let .alphabet(_, base), let .accent(_, base), let .color(_, base), let .style(_, base): return atomClass(base)
        case .delimited, .matrix, .fraction: return .ordinary
        default: return .ordinary
        }
    }

    private func layout(_ node: MathNode, size: CGFloat, level: Int, display: Bool, alphabet: MathAlphabet) -> MathBox {
        let m = MathFont.metrics(size: size, face: options.font)
        switch node {
        case let .symbol(value, kind):
            if kind == .largeOperator { return glyph(value, size: size, minimumHeight: display ? m.displayOperatorMinHeight : 0, centered: true) }
            return text(value == "-" ? "−" : value, size: size, alphabet: kind == .function ? .upright : alphabet, level: level)
        case let .text(value): return text(value, size: size, level: level)
        case let .space(em): return MathBox(width: CGFloat(em) * size)
        case let .alphabet(choice, body): return layout(body, size: size, level: level, display: display, alphabet: choice)
        case let .color(color, body):
            var box = layout(body, size: size, level: level, display: display, alphabet: alphabet)
            box.drawings = [.colored(color, box.drawings)]
            return box
        case let .style(style, body):
            let originalSize = size / (level == 0 ? 1 : level == 1 ? m.scriptPercentScaleDown : m.scriptScriptPercentScaleDown)
            switch style {
            case .display: return layout(body, size: originalSize, level: 0, display: true, alphabet: alphabet)
            case .text: return layout(body, size: originalSize, level: 0, display: false, alphabet: alphabet)
            case .script: return layout(body, size: originalSize * m.scriptPercentScaleDown, level: 1, display: false, alphabet: alphabet)
            case .scriptScript: return layout(body, size: originalSize * m.scriptScriptPercentScaleDown, level: 2, display: false, alphabet: alphabet)
            }
        case let .row(nodes):
            var result = MathBox(), previous: MathAtomClass?
            for (index, child) in nodes.enumerated() {
                let box = layout(child, size: size, level: level, display: display, alphabet: alphabet)
                var kind = atomClass(child)
                if kind == .binary, previous == nil || previous == .binary || previous == .relation || previous == .opening || previous == .punctuation || index == nodes.count - 1 { kind = .ordinary }
                let space: CGFloat
                if let prior = previous, level == 0 {
                    if prior == .opening || kind == .closing || kind == .punctuation { space = 0 }
                    else if kind == .relation || prior == .relation { space = size * 5 / 18 }
                    else if kind == .binary || prior == .binary { space = size * 4 / 18 }
                    else if kind == .function || prior == .function || prior == .largeOperator || prior == .punctuation { space = size * 3 / 18 }
                    else { space = 0 }
                } else { space = 0 }
                let x = result.width + space
                result.add(box, x: x)
                // Explicit negative glue must decrease the pen position.
                result.width = x + box.width
                result.italicCorrection = box.italicCorrection
                if case .space = child {} else { previous = kind }
            }
            return result
        case let .fraction(numerator, denominator, rule, forceDisplay):
            let isDisplay = forceDisplay ?? display
            let childSize = isDisplay ? size : nextSize(size, level: level)
            let childLevel = isDisplay ? level : min(2, level + 1)
            let n = layout(numerator, size: childSize, level: childLevel, display: false, alphabet: alphabet)
            let d = layout(denominator, size: childSize, level: childLevel, display: false, alphabet: alphabet)
            let thickness = rule ? m.fractionRuleThickness : 0
            let nGap = isDisplay ? m.fractionNumDisplayStyleGapMin : m.fractionNumeratorGapMin
            let dGap = isDisplay ? m.fractionDenomDisplayStyleGapMin : m.fractionDenominatorGapMin
            let nShift = max(isDisplay ? m.fractionNumeratorDisplayStyleShiftUp : m.fractionNumeratorShiftUp, m.axisHeight + thickness / 2 + nGap + n.descent)
            let dShift = max(isDisplay ? m.fractionDenominatorDisplayStyleShiftDown : m.fractionDenominatorShiftDown, d.ascent - m.axisHeight + thickness / 2 + dGap)
            let padding = size * 0.12, width = max(n.width, d.width) + padding * 2
            var result = MathBox(width: width)
            result.add(n, x: (width - n.width) / 2, y: nShift)
            result.add(d, x: (width - d.width) / 2, y: -dShift)
            if rule {
                let overhang = options.fractionBarOverhang * size
                result.drawings.append(.rule(CGRect(x: padding - overhang, y: m.axisHeight - thickness / 2, width: width - padding * 2 + overhang * 2, height: thickness)))
            }
            return result
        case let .scripts(base, lower, upper, limits):
            let b = layout(base, size: size, level: level, display: display, alphabet: alphabet)
            let scriptSize = nextSize(size, level: level)
            let lo = lower.map { layout($0, size: scriptSize, level: min(2, level + 1), display: false, alphabet: alphabet) }
            let hi = upper.map { layout($0, size: scriptSize, level: min(2, level + 1), display: false, alphabet: alphabet) }
            let isOperator = atomClass(base) == .largeOperator || atomClass(base) == .function
            let isIntegral: Bool
            if case let .symbol(value, _) = base { isIntegral = "∫∬∭∮".contains(value) } else { isIntegral = false }
            if limits ?? (display && isOperator && !isIntegral) { return limitsBox(b, above: hi, below: lo, size: size) }
            var result = b
            let simpleNucleus = b.drawings.count == 1 && atomClass(base) != .largeOperator
            var up = simpleNucleus ? m.superscriptShiftUp : max(m.superscriptShiftUp, b.ascent - m.superscriptBaselineDropMax)
            if let hi { up = max(up, hi.descent + m.superscriptBottomMin) }
            var down = simpleNucleus ? m.subscriptShiftDown : max(m.subscriptShiftDown, b.descent + m.subscriptBaselineDropMin)
            if let lo { down = max(down, lo.ascent - m.subscriptTopMax) }
            if let hi, let lo {
                let gap = up - hi.descent - (lo.ascent - down)
                if gap < m.subSuperscriptGapMin { down += m.subSuperscriptGapMin - gap }
            }
            if let hi { result.add(hi, x: b.width, y: up) }
            if let lo { result.add(lo, x: b.width - b.italicCorrection, y: -down) }
            if hi != nil || lo != nil { result.width += m.spaceAfterScript }
            result.italicCorrection = 0
            return result
        case let .radical(body, degree):
            let b = layout(body, size: size, level: level, display: display, alphabet: alphabet)
            var gap = (display ? m.radicalDisplayStyleVerticalGap : m.radicalVerticalGap) * options.radicalGap
            let thickness = m.radicalRuleThickness
            let rad = glyph("√", size: size, minimumHeight: b.height + gap + thickness)
            // Variant advances choose a glyph; its actual ink height determines
            // clearance. NewCM includes a one-unit overshoot in these advances.
            let advance = rad.height
            gap += max(0, (advance - b.height - gap - thickness) / 2)
            let shift = b.ascent + gap + thickness - rad.ascent
            var result = MathBox()
            let degreeBox = degree.map { layout($0, size: size * m.scriptScriptPercentScaleDown, level: 2, display: false, alphabet: alphabet) }
            let lead = degreeBox.map { max(0, $0.width + m.radicalKernBeforeDegree + m.radicalKernAfterDegree) } ?? 0
            result.add(rad, x: lead, y: shift)
            result.add(b, x: lead + rad.width)
            result.drawings.append(.rule(CGRect(x: lead + rad.width, y: b.ascent + gap, width: b.width, height: thickness)))
            result.ascent = max(result.ascent, b.ascent + gap + thickness + m.radicalExtraAscender)
            if let degreeBox { result.add(degreeBox, x: m.radicalKernBeforeDegree, y: shift - rad.descent + advance * m.radicalDegreeBottomRaisePercent) }
            return result
        case let .delimited(left, body, right):
            let b = layout(body, size: size, level: level, display: display, alphabet: alphabet)
            return enclose(b, left: left, right: right, size: size)
        case let .overUnder(body, above, below):
            let b = layout(body, size: size, level: level, display: display, alphabet: alphabet)
            let scriptSize = nextSize(size, level: level)
            return limitsBox(b, above: above.map { layout($0, size: scriptSize, level: min(2, level + 1), display: false, alphabet: alphabet) }, below: below.map { layout($0, size: scriptSize, level: min(2, level + 1), display: false, alphabet: alphabet) }, size: size)
        case let .accent(accent, body):
            let b = layout(body, size: size, level: level, display: display, alphabet: alphabet)
            var result = b
            if accent == .overline || accent == .underline {
                let below = accent == .underline
                let thickness = below ? m.underbarRuleThickness : m.overbarRuleThickness
                let y = below ? -b.descent - m.underbarVerticalGap - thickness : b.ascent + m.overbarVerticalGap
                result.drawings.append(.rule(CGRect(x: 0, y: y, width: b.width, height: thickness)))
                if below { result.descent = -y + m.underbarExtraDescender }
                else { result.ascent = y + thickness + m.overbarExtraAscender }
            } else {
                let scalar: UniChar
                switch accent {
                case .hat, .wideHat: scalar = 0x0302
                case .tilde, .wideTilde: scalar = 0x0303
                case .vector: scalar = 0x20D7
                case .dot: scalar = 0x0307
                case .doubleDot: scalar = 0x0308
                case .bar: scalar = 0x0304
                case .overbrace: scalar = 0x23DE
                case .underbrace: scalar = 0x23DF
                default: scalar = 0x0304
                }
                let font = MathFont.font(size: size, face: options.font)
                var g: CGGlyph = 0
                guard CTFontGetGlyphsForCharacters(font, [scalar], &g, 1), g != 0 else {
                    if let missing = Unicode.Scalar(scalar) { missingGlyph(missing) }
                    return MathBox()
                }
                if accent == .wideHat || accent == .wideTilde || accent == .overbrace || accent == .underbrace {
                    g = MathFont.horizontalVariant(glyph: g, maximumWidth: b.width, size: size, face: options.font)?.glyph ?? g
                }
                var advance = CGSize.zero
                CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &advance, 1)
                let bounds = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &g, nil, 1)
                let correction = MathFont.italicCorrection(glyph: g, size: size, face: options.font)
                let accentWidth = advance.width + correction
                let a = MathBox(width: accentWidth, ascent: max(0, bounds.maxY), descent: max(0, -bounds.minY), drawings: [.glyph(font, g, .zero)])
                var bodyAttachment = b.width / 2
                if b.drawings.count == 1, case let .glyph(baseFont, baseGlyph, _) = b.drawings[0] {
                    bodyAttachment = MathFont.topAccentAttachment(glyph: baseGlyph, size: CTFontGetSize(baseFont), face: options.font) ?? bodyAttachment
                }
                let accentAttachment = MathFont.topAccentAttachment(glyph: g, size: size, face: options.font) ?? accentWidth / 2
                let y = accent == .underbrace ? -b.descent : max(0, b.ascent - m.accentBaseHeight)
                result.add(a, x: bodyAttachment - accentAttachment, y: y)
                result.width = b.width
            }

            return result
        case let .matrix(rows, left, right, aligned):
            let boxes = rows.map { row in row.map { layout($0, size: size, level: level, display: false, alphabet: alphabet) } }
            let count = boxes.map(\.count).max() ?? 0
            guard count > 0 else { return MathBox() }
            var widths = [CGFloat](repeating: 0, count: count)
            for row in boxes { for (i, b) in row.enumerated() { widths[i] = max(widths[i], b.width) } }
            var result = MathBox(), down: CGFloat = 0
            for row in boxes {
                let strut = size * 7 / 6
                let ascent = max(strut * 0.7, row.map(\.ascent).max() ?? 0)
                let descent = max(strut * 0.3, row.map(\.descent).max() ?? 0)
                let baseline = -down - ascent
                var x: CGFloat = 0
                for (i, b) in row.enumerated() {
                    let offset = aligned ? (i % 2 == 0 ? widths[i] - b.width : 0) : (widths[i] - b.width) / 2
                    result.add(b, x: x + offset, y: baseline)
                    x += widths[i] + (aligned && i % 2 == 0 ? 0 : size * 0.625)
                }
                result.width = max(result.width, x - size * 0.625)
                down += ascent + descent
            }
            let height = down, shift = height / 2 + m.axisHeight
            result.drawings = result.drawings.map { $0.translated(x: 0, y: shift) }
            result.ascent = height / 2 + m.axisHeight
            result.descent = max(0, height / 2 - m.axisHeight)
            return enclose(result, left: left, right: right, size: size)
        }
    }

    private func enclose(_ body: MathBox, left: String, right: String, size: CGFloat) -> MathBox {
        let axis = MathFont.metrics(size: size, face: options.font).axisHeight
        let height = max(body.ascent - axis, body.descent + axis) * 2 * 0.901
        let l = glyph(left, size: size, minimumHeight: height, centered: true)
        let r = glyph(right, size: size, minimumHeight: height, centered: true)
        var result = MathBox()
        result.add(l, x: 0); result.add(body, x: l.width); result.add(r, x: l.width + body.width)
        return result
    }

    private func limitsBox(_ base: MathBox, above: MathBox?, below: MathBox?, size: CGFloat) -> MathBox {
        let m = MathFont.metrics(size: size, face: options.font)
        let width = max(base.width, above?.width ?? 0, below?.width ?? 0)
        var result = MathBox(width: width)
        result.add(base, x: (width - base.width) / 2)
        if let above { result.add(above, x: (width - above.width) / 2 + base.italicCorrection / 2, y: max(m.upperLimitBaselineRiseMin, base.ascent + m.upperLimitGapMin + above.descent)) }
        if let below { result.add(below, x: (width - below.width) / 2 - base.italicCorrection / 2, y: -max(m.lowerLimitBaselineDropMin, base.descent + m.lowerLimitGapMin + below.ascent)) }
        return result
    }

    private func styled(_ scalar: Unicode.Scalar, alphabet: MathAlphabet) -> Unicode.Scalar {
        let v = scalar.value
        let upper = (65...90).contains(v), lower = (97...122).contains(v), digit = (48...57).contains(v)
        var target: UInt32?
        switch alphabet {
        case .upright: return scalar
        case .italic:
            if upper { target = 0x1D434 + v - 65 }
            else if lower { target = v == 104 ? 0x210E : 0x1D44E + v - 97 }
            else if (0x3B1...0x3C9).contains(v) { target = 0x1D6FC + v - 0x3B1 }
        case .bold:
            if upper { target = 0x1D400 + v - 65 }; if lower { target = 0x1D41A + v - 97 }; if digit { target = 0x1D7CE + v - 48 }
        case .doubleStruck:
            if upper { target = [67: 0x2102, 72: 0x210D, 78: 0x2115, 80: 0x2119, 81: 0x211A, 82: 0x211D, 90: 0x2124][v] ?? (0x1D538 + v - 65) }
            if lower { target = 0x1D552 + v - 97 }; if digit { target = 0x1D7D8 + v - 48 }
        case .script:
            if upper { target = [66: 0x212C, 69: 0x2130, 70: 0x2131, 72: 0x210B, 73: 0x2110, 76: 0x2112, 77: 0x2133, 82: 0x211B][v] ?? (0x1D49C + v - 65) }
            if lower { target = [101: 0x212F, 103: 0x210A, 111: 0x2134][v] ?? (0x1D4B6 + v - 97) }
        case .fraktur:
            if upper { target = [67: 0x212D, 72: 0x210C, 73: 0x2111, 82: 0x211C, 90: 0x2128][v] ?? (0x1D504 + v - 65) }; if lower { target = 0x1D51E + v - 97 }
        case .sans:
            if upper { target = 0x1D5A0 + v - 65 }; if lower { target = 0x1D5BA + v - 97 }; if digit { target = 0x1D7E2 + v - 48 }
        case .monospace:
            if upper { target = 0x1D670 + v - 65 }; if lower { target = 0x1D68A + v - 97 }; if digit { target = 0x1D7F6 + v - 48 }
        }
        return target.flatMap(Unicode.Scalar.init) ?? scalar
    }
}
