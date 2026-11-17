import CoreText

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Draw the existing shaped glyphs at the paragraph engine's positions. Keeping
/// compatible adjacent glyphs in one PDF text operation avoids splitting a
/// tracked compound identifier into unrelated PDFKit text blocks.
enum ParagraphGlyphDrawing {
    /// Extract only the values that direct glyph drawing supports. Unsupported
    /// paint retains the original snapshot-local CTLine/CTRun fallback below.
    static func prepare(_ text: CTLine, attributed: NSAttributedString) -> FragmentGlyphPaint? {
        var prepared: [FragmentGlyphPaint.Run] = []
        var inset: CGFloat = 0
        for (index, run) in (CTLineGetGlyphRuns(text) as! [CTRun]).enumerated() {
            let values = CTRunGetAttributes(run) as NSDictionary
            let range = CTRunGetStringRange(run)
            let source =
                range.location >= 0 && range.location < attributed.length
                ? attributed.attributes(at: range.location, effectiveRange: nil) : [:]
            guard values[kCTRunDelegateAttributeName] == nil,
                CTRunGetTextMatrix(run).isIdentity, !hasUnsupportedPaint(source, values: values)
            else { return nil }
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            guard let fontValue = values[kCTFontAttributeName] ?? values[NSAttributedString.Key.font.rawValue],
                CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID()
            else { return nil }
            let color =
                resolvedColor(source[.foregroundColor])
                ?? resolvedColor(values[NSAttributedString.Key.foregroundColor.rawValue])
                ?? resolvedColor(values[kCTForegroundColorAttributeName]) ?? CGColor(gray: 0, alpha: 1)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            if index == 0 { inset = max(0, positions[0].x) }
            prepared.append(.init(font: fontValue as! CTFont, color: color, glyphs: glyphs, positions: positions))
        }
        return FragmentGlyphPaint(runs: prepared, leadingInset: inset)
    }

    static func draw(_ line: ShapedLine, attributed: NSAttributedString, in context: CGContext) {
        var batchFont: CTFont?
        var batchColor: CGColor?
        var glyphs: [CGGlyph] = []
        var positions: [CGPoint] = []

        func flush() {
            guard let font = batchFont, let color = batchColor, !glyphs.isEmpty else { return }
            context.saveGState()
            context.setFillColor(color)
            // CTFontDrawGlyphs adds the current text position to these explicit
            // positions. A delegated run may have changed that text position.
            let previousPosition = context.textPosition
            context.textPosition = .zero
            CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)
            context.textPosition = previousPosition
            context.restoreGState()
            glyphs.removeAll(keepingCapacity: true)
            positions.removeAll(keepingCapacity: true)
            batchFont = nil
            batchColor = nil
        }

        func append(_ text: CTLine, at x: CGFloat, usesSourceAttributes: Bool) {
            let runs = CTLineGetGlyphRuns(text) as! [CTRun]
            let containsDelegate = runs.contains {
                (CTRunGetAttributes($0) as NSDictionary)[kCTRunDelegateAttributeName] != nil
            }
            let requiresLinePaint = runs.contains { run in
                let range = CTRunGetStringRange(run)
                let source =
                    usesSourceAttributes && range.location >= 0 && range.location < attributed.length
                    ? attributed.attributes(at: range.location, effectiveRange: nil) : [:]
                return hasUnsupportedPaint(source, values: CTRunGetAttributes(run) as NSDictionary)
            }
            // Underlines are painted by CTLineDraw, not CTRunDraw. Delegate the
            // original whole line when it has no manually painted attachments.
            if requiresLinePaint && !containsDelegate {
                flush()
                context.saveGState()
                context.textPosition = CGPoint(x: x, y: 0)
                CTLineDraw(text, context)
                context.restoreGState()
                return
            }
            for run in runs {
                let values = CTRunGetAttributes(run) as NSDictionary
                // Attachment glyphs are painted by their image/math/diagram
                // owners after paragraph text, and capsule spacers have no ink.
                guard values[kCTRunDelegateAttributeName] == nil else { continue }
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                let range = CTRunGetStringRange(run)
                let source: [NSAttributedString.Key: Any]
                if usesSourceAttributes, range.location >= 0, range.location < attributed.length {
                    source = attributed.attributes(at: range.location, effectiveRange: nil)
                } else {
                    source = [:]
                }

                let fontValue = values[kCTFontAttributeName] ?? values[NSAttributedString.Key.font.rawValue]
                let color =
                    resolvedColor(source[.foregroundColor])
                    ?? resolvedColor(values[NSAttributedString.Key.foregroundColor.rawValue])
                    ?? resolvedColor(values[kCTForegroundColorAttributeName])
                    ?? CGColor(gray: 0, alpha: 1)
                let requiresDelegation =
                    !CTRunGetTextMatrix(run).isIdentity
                    || hasUnsupportedPaint(source, values: values)
                guard let fontValue, CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID(), !requiresDelegation
                else {
                    flush()
                    context.saveGState()
                    context.textPosition = CGPoint(x: x, y: 0)
                    // Retain run-specific paint and matrices that direct glyph
                    // drawing cannot reproduce. Production attachment runs are
                    // isolated from decorated text by their inline run identity.
                    CTRunDraw(run, context, CFRange(location: 0, length: 0))
                    context.restoreGState()
                    continue
                }
                let font = fontValue as! CTFont
                if let previous = batchFont,
                    !CFEqual(previous, font) || batchColor != color
                {
                    flush()
                }
                batchFont = font
                batchColor = color
                var runGlyphs = [CGGlyph](repeating: 0, count: count)
                var runPositions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &runGlyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &runPositions)
                // CTRun positions already include baseline offsets. The parent
                // has established this line's baseline and coordinate flip.
                for index in runPositions.indices { runPositions[index].x += x }
                glyphs.append(contentsOf: runGlyphs)
                positions.append(contentsOf: runPositions)
            }
        }

        for fragment in line.fragments {
            let paint = fragment.materialized
            let x = fragment.x + fragment.drawOffset - paint.glyphInset
            if let prepared = paint.glyphPaint {
                for run in prepared.runs {
                    if let previous = batchFont, !CFEqual(previous, run.font) || batchColor != run.color { flush() }
                    batchFont = run.font
                    batchColor = run.color
                    glyphs.append(contentsOf: run.glyphs)
                    for position in run.positions {
                        positions.append(CGPoint(x: position.x + x, y: position.y))
                    }
                }
            } else {
                append(paint.line, at: x, usesSourceAttributes: true)
            }
        }
        if let hyphen = line.hyphen { append(hyphen.line, at: hyphen.x, usesSourceAttributes: false) }
        flush()
    }

    private static func resolvedColor(_ value: Any?) -> CGColor? {
        guard let value else { return nil }
        if let color = value as? PlatformColor { return color.cgColor }
        guard CFGetTypeID(value as CFTypeRef) == CGColor.typeID else { return nil }
        return (value as! CGColor)
    }

    private static func hasUnsupportedPaint(_ source: [NSAttributedString.Key: Any], values: NSDictionary) -> Bool {
        // Delegate even explicitly zero-valued attributes: retaining an extra
        // Core Text call is preferable to changing an unsupported paint style.
        let keys: [NSAttributedString.Key] = [
            .underlineStyle, .underlineColor, .strikethroughStyle, .strikethroughColor,
            .strokeWidth, .strokeColor, .shadow, .obliqueness, .expansion,
            .verticalGlyphForm, NSAttributedString.Key("NSSuperscript"), .textEffect
        ]
        if keys.contains(where: { source[$0] != nil || values[$0.rawValue] != nil }) { return true }
        return [
            kCTStrokeWidthAttributeName, kCTStrokeColorAttributeName, kCTUnderlineStyleAttributeName,
            kCTUnderlineColorAttributeName, kCTForegroundColorFromContextAttributeName,
            kCTVerticalFormsAttributeName
        ].contains { values[$0] != nil }
    }
}
