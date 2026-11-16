import CoreText
import Foundation

/// A layout-local cache. Tile painting only consumes the resulting rectangles.
final class UnderlineClearance {
    private struct Bounds {
        var lower = Double.infinity
        var upper = -Double.infinity
        var isEmpty: Bool { lower > upper }
        mutating func include(_ x: Double) { lower = min(lower, x); upper = max(upper, x) }
        mutating func include(_ bounds: Bounds) {
            guard !bounds.isEmpty else { return }
            include(bounds.lower)
            include(bounds.upper)
        }
    }

    private struct Key: Hashable {
        let font: CTFont
        let glyph: CGGlyph
        let lower: Int
        let upper: Int
        let collision: Int
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.glyph == rhs.glyph && lhs.lower == rhs.lower && lhs.upper == rhs.upper
                && lhs.collision == rhs.collision && CFEqual(lhs.font, rhs.font)
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(CFHash(font))
            hasher.combine(glyph)
            hasher.combine(lower)
            hasher.combine(upper)
            hasher.combine(collision)
        }
    }

    private struct ExtentKey: Hashable {
        let font: ObjectIdentifier
        let glyph: CGGlyph
    }

    /// Normalized vertical ink extent (y-down), keyed by font identity so the
    /// common rejection avoids hashing and comparing CTFont values. Each entry
    /// retains its font, so an identifier cannot be reused while cached.
    private struct Extent {
        let font: CTFont
        let top: Double
        let bottom: Double
    }

    private var cache: [Key: Bounds] = [:]
    private var extents: [ExtentKey: Extent] = [:]

    private func extent(_ font: CTFont, _ glyph: CGGlyph, size: CGFloat) -> Extent {
        let key = ExtentKey(font: ObjectIdentifier(font), glyph: glyph)
        if let cached = extents[key] { return cached }
        var glyph = glyph
        let box = CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, nil, 1)
        let extent =
            box.isEmpty
            ? Extent(font: font, top: .infinity, bottom: -.infinity)
            : Extent(font: font, top: -Double(box.maxY / size), bottom: -Double(box.minY / size))
        extents[key] = extent
        return extent
    }

    func subtract(
        from rect: CGRect, line: ShapedLine, attributed: NSAttributedString, em: CGFloat,
        emit: (CGRect) -> Void
    ) {
        var cuts: [ClosedRange<CGFloat>] = []
        func glyph(_ font: CTFont, _ glyph: CGGlyph, _ position: CGPoint) {
            let size = CTFontGetSize(font)
            guard size > 0 else { return }
            let lower = (rect.minY - position.y) / size
            let upper = (rect.maxY - position.y) / size
            guard upper > 0 else { return }
            let collision = min(upper, lower + em * 0.02 / size)
            let quantizedUpper = Int((upper * 10_000).rounded())
            let quantizedCollision = Int((collision * 10_000).rounded())
            // Same early-out as `bounds(_:)`: most glyphs never reach the stripe.
            let ink = extent(font, glyph, size: size)
            guard ink.bottom > Double(quantizedCollision) / 10_000, ink.top < Double(quantizedUpper) / 10_000
            else { return }
            let key = Key(
                font: font, glyph: glyph, lower: Int((lower * 10_000).rounded()),
                upper: quantizedUpper, collision: quantizedCollision)
            let bounds: Bounds
            if let cached = cache[key] {
                bounds = cached
            } else {
                bounds = Self.bounds(key)
                cache[key] = bounds
            }
            guard !bounds.isEmpty else { return }
            let left = position.x + CGFloat(bounds.lower) * size
            let right = position.x + CGFloat(bounds.upper) * size
            if left < rect.maxX && right > rect.minX { cuts.append(left...right) }
        }
        func text(_ text: CTLine, at origin: CGPoint) {
            for run in CTLineGetGlyphRuns(text) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard attributes[kCTRunDelegateAttributeName] == nil,
                    let value = attributes[kCTFontAttributeName],
                    CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
                else { continue }
                let font = value as! CTFont
                let count = CTRunGetGlyphCount(run)
                func visit(_ glyphs: UnsafePointer<CGGlyph>, _ positions: UnsafePointer<CGPoint>) {
                    for index in 0..<count {
                        glyph(
                            font, glyphs[index],
                            CGPoint(x: origin.x + positions[index].x, y: origin.y - positions[index].y))
                    }
                }
                if let glyphs = CTRunGetGlyphsPtr(run), let positions = CTRunGetPositionsPtr(run) {
                    visit(glyphs, positions)
                } else {
                    withUnsafeTemporaryAllocation(of: CGGlyph.self, capacity: count) { glyphs in
                        withUnsafeTemporaryAllocation(of: CGPoint.self, capacity: count) { positions in
                            guard let g = glyphs.baseAddress, let p = positions.baseAddress else { return }
                            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), g)
                            CTRunGetPositions(run, CFRange(location: 0, length: 0), p)
                            visit(g, p)
                        }
                    }
                }
            }
        }
        if line.fragments.isEmpty {
            text(line.line, at: line.origin)
        } else {
            for fragment in line.fragments {
                text(
                    fragment.line,
                    at: CGPoint(
                        x: line.origin.x + fragment.x + fragment.drawOffset - fragment.glyphInset, y: line.origin.y))
            }
        }
        if let hyphen = line.hyphen {
            text(hyphen.line, at: CGPoint(x: line.origin.x + hyphen.x, y: line.origin.y))
        }
        func math(_ drawings: [MathDrawing], at origin: CGPoint) {
            for drawing in drawings {
                switch drawing {
                case .glyph(let font, let g, let position):
                    glyph(font, g, CGPoint(x: origin.x + position.x, y: origin.y - position.y))
                case .text(let ctLine, let position):
                    text(ctLine, at: CGPoint(x: origin.x + position.x, y: origin.y - position.y))
                case .colored(_, let children): math(children, at: origin)
                case .rule: break
                }
            }
        }
        attributed.enumerateAttribute(.kasumiMath, in: line.range) { value, range, _ in
            guard let attachment = value as? MathAttachment else { return }
            math(
                attachment.result.box.drawings,
                at: CGPoint(x: line.origin.x + line.offset(forStringIndex: range.location), y: line.origin.y))
        }
        cuts.sort { $0.lowerBound < $1.lowerBound }
        var left = rect.minX
        for cut in cuts {
            if cut.lowerBound > left {
                emit(CGRect(x: left, y: rect.minY, width: min(cut.lowerBound, rect.maxX) - left, height: rect.height))
            }
            left = max(left, cut.upperBound)
            if left >= rect.maxX { return }
        }
        if left < rect.maxX { emit(CGRect(x: left, y: rect.minY, width: rect.maxX - left, height: rect.height)) }
    }

    private static func bounds(_ key: Key) -> Bounds {
        let size = CTFontGetSize(key.font)
        let lower = Double(key.lower) / 10_000
        let upper = Double(key.upper) / 10_000
        let collision = Double(key.collision) / 10_000
        var glyph = key.glyph
        let box = CTFontGetBoundingRectsForGlyphs(key.font, .default, &glyph, nil, 1)
        guard !box.isEmpty, -Double(box.minY / size) > collision, -Double(box.maxY / size) < upper,
            let path = CTFontCreatePathForGlyph(key.font, key.glyph, nil)
        else { return Bounds() }
        var current = CGPoint.zero
        var start = CGPoint.zero
        var hit = false
        var bounds = Bounds()
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / size, y: -p.y / size) }
        // Curves contribute their control polygon, clipped linearly against the band.
        func add(_ points: [CGPoint]) {
            for (p, q) in zip(points, points.dropFirst()) {
                if !Self.clip(p, q, lower: collision, upper: upper).isEmpty { hit = true }
                bounds.include(Self.clip(p, q, lower: lower - 0.06, upper: upper + 0.06))
            }
        }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points: [CGPoint]
            switch element.type {
            case .moveToPoint:
                current = point(element.points[0])
                start = current
                return
            case .addLineToPoint: points = [current, point(element.points[0])]
            case .addQuadCurveToPoint: points = [current, point(element.points[0]), point(element.points[1])]
            case .addCurveToPoint:
                points = [current, point(element.points[0]), point(element.points[1]), point(element.points[2])]
            case .closeSubpath: points = [current, start]
            @unknown default: return
            }
            add(points)
            current = points[points.count - 1]
        }
        guard hit, !bounds.isEmpty else { return Bounds() }
        bounds.lower -= 0.06
        bounds.upper += 0.06
        return bounds
    }

    /// Horizontal extent of segment `p`–`q` within the vertical band [lower, upper].
    private static func clip(_ p: CGPoint, _ q: CGPoint, lower: Double, upper: Double) -> Bounds {
        var bounds = Bounds()
        if p.y == q.y {
            if p.y >= lower, p.y <= upper {
                bounds.include(p.x)
                bounds.include(q.x)
            }
            return bounds
        }
        let a = (lower - p.y) / (q.y - p.y)
        let b = (upper - p.y) / (q.y - p.y)
        let t0 = max(0, min(a, b))
        let t1 = min(1, max(a, b))
        guard t0 <= t1 else { return bounds }
        bounds.include(p.x + (q.x - p.x) * t0)
        bounds.include(p.x + (q.x - p.x) * t1)
        return bounds
    }
}
