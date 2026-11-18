import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

fileprivate func drawingParagraph(
    _ attributed: NSAttributedString, width: CGFloat = 650, preparation: ParagraphPreparation? = nil,
    deferFragments: Bool = false
) -> ParagraphLayout {
    ParagraphTypesetter.layout(
        attributed, width: width, fontSize: 22, alignment: .justified,
        profileValues: ProfileValues([.autoRaggedNarrow: .flag(false)]), preparation: preparation,
        deferFragments: deferFragments)
}

/// The former renderer is the independent paint reference: retain the existing
/// CTLines and place each at the engine's actual fragment origin. It neither
/// rebuilds glyph batches nor substitutes normalized source text.
fileprivate func priorParagraphPaint(_ line: ShapedLine, in context: CGContext) {
    for fragment in line.fragments {
        context.textPosition = CGPoint(x: fragment.x + fragment.drawOffset, y: 0)
        CTLineDraw(fragment.line, context)
    }
    if let hyphen = line.hyphen {
        context.textPosition = CGPoint(x: hyphen.x, y: 0)
        CTLineDraw(hyphen.line, context)
    }
}

fileprivate func paragraphBitmap(_ paragraph: ParagraphLayout, batched: Bool) throws -> [UInt8] {
    let width = 1400
    let height = 600
    let scale: CGFloat = 2
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    try pixels.withUnsafeMutableBytes { storage in
        let context = try #require(
            CGContext(
                data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 20, y: CGFloat(height) / scale - 20)
        context.textMatrix = .identity
        // A delegated line can leave a nonzero textPosition. Each route must
        // still draw at the supplied fragment positions, rather than add it.
        context.textPosition = CGPoint(x: 17, y: 9)
        for line in paragraph.lines {
            context.saveGState()
            context.translateBy(x: line.origin.x, y: -line.origin.y)
            if batched {
                ParagraphGlyphDrawing.draw(line, attributed: paragraph.attributed, in: context)
            } else {
                priorParagraphPaint(line, in: context)
            }
            context.restoreGState()
        }
        for underline in paragraph.underlines {
            context.setFillColor(underline.color.cgColor)
            let rect = underline.rect
            context.fill(CGRect(x: rect.minX, y: -rect.maxY, width: rect.width, height: rect.height))
        }
    }
    return pixels
}

fileprivate func differingParagraphPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
    stride(from: 0, to: a.count, by: 4).reduce(0) { count, index in
        count + (a[index..<(index + 4)].elementsEqual(b[index..<(index + 4)]) ? 0 : 1)
    }
}

fileprivate func inkParagraphPixels(_ pixels: [UInt8]) -> Int {
    stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 250 || pixels[$0 + 1] < 250 || pixels[$0 + 2] < 250 }
        .count
}

fileprivate func paragraphPDF(_ paragraph: ParagraphLayout) throws -> Data {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ParagraphDrawing-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("authored.pdf")
    let consumer = try #require(CGDataConsumer(url: url as CFURL))
    var box = CGRect(x: 0, y: 0, width: 720, height: 360)
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.translateBy(x: 24, y: 330)
    context.textMatrix = .identity
    for line in paragraph.lines {
        context.saveGState()
        context.translateBy(x: line.origin.x, y: -line.origin.y)
        ParagraphGlyphDrawing.draw(line, attributed: paragraph.attributed, in: context)
        context.restoreGState()
    }
    context.endPDFPage()
    context.closePDF()
    return try Data(contentsOf: url)
}

fileprivate func mixedFontDrawingText() -> NSMutableAttributedString {
    var values = BuiltinProfiles.all[0].effective
    values[.baseSize] = .number(22)
    values[.hanScale] = .number(1.15)
    values[.hanBaseline] = .number(0.12)
    let style = Typography().applying(values)
    let text = NSMutableAttributedString(
        attributedString: style.attributed([
            InlineRun("Latin office "), InlineRun("汉，字。（"),
            InlineRun("Link_20", traits: [.link], destination: "https://example.invalid/authored"),
            InlineRun("） raised"), InlineRun(" tail", traits: [.emphasis]),
            InlineRun(" 🙂 👩‍👩‍👧‍👦 emoji")
        ]))
    let source = text.string as NSString
    text.addAttributes(
        [
            .foregroundColor: PlatformColor(srgbRed: 0.85, green: 0.05, blue: 0.1, alpha: 1),
            .baselineOffset: 4.25
        ], range: source.range(of: "Latin office"))
    text.addAttributes(
        [
            .foregroundColor: PlatformColor(srgbRed: 0.05, green: 0.15, blue: 0.85, alpha: 1),
            .baselineOffset: -2.5
        ], range: source.range(of: "raised"))
    return text
}

@Suite struct ParagraphDrawingTests {
    @Test func linePaintSurvivesSharedCacheEviction() throws {
        let storage = FragmentGlyphPaintCache.Storage()
        let cache = FragmentGlyphPaintCache(storage: storage)
        let text = NSMutableAttributedString(
            string: "abc",
            attributes: [.font: PlatformFont.systemFont(ofSize: 14), .foregroundColor: PlatformColor.black])
        text.addAttribute(
            .foregroundColor, value: PlatformColor.black.withAlphaComponent(0.5),
            range: NSRange(location: 2, length: 1))
        let factory = ParagraphFragmentFactory(text, glyphPaintCache: cache)
        let geometry = (0..<3).map {
            FragmentGeometry(
                range: NSRange(location: $0, length: 1), x: CGFloat($0 * 10), width: 10,
                drawOffset: 0, capsuleLeft: 0, capsuleRight: 0)
        }
        let store = LineFragmentStore(factory: factory, geometry: geometry)
        _ = store.value(at: 0)
        let first = try #require(store.cachedGlyphPaint(at: 0))
        let second = try #require(store.cachedGlyphPaint(at: 1))
        let third = try #require(store.cachedGlyphPaint(at: 2))
        if case .single(let a) = first.storage, case .single(let b) = second.storage,
            case .single(let c) = third.storage
        {
            #expect(a.color === b.color)
            #expect(a.color != c.color && c.color.alpha == 0.5)
        } else {
            Issue.record("Single-glyph paints were not compacted")
        }
        storage.removeAll()
        #expect(cache.cachedValue(for: geometry[0].range) == nil)
        #expect(store.cachedGlyphPaint(at: 0) === first)
        #expect(store.cachedGlyphPaint(at: 1) === second)
        #expect(first.carets?.boundaries == [0, 1])
        #expect(second.carets?.boundaries == [1, 2])
    }

    @Test func sharedGlyphStorageKeepsParagraphNamespacesIndependent() {
        let storage = FragmentGlyphPaintCache.Storage()
        let first = FragmentGlyphPaintCache(storage: storage)
        let second = FragmentGlyphPaintCache(storage: storage)
        let range = NSRange(location: 0, length: 1)
        let paint = FragmentGlyphPaint(runs: [], leadingInset: 1, carets: nil)
        #expect(first.value(for: range) { paint } === paint)
        #expect(second.cachedValue(for: range) == nil)
        #expect(second.value(for: range) { nil } == nil)
        #expect(first.cachedValue(for: range) === paint)
        #expect(second.value(for: range) { paint } == nil)
    }

    @Test func reusedGlyphValuesKeepPixelsAndLayoutObjectsIndependent() throws {
        let text = NSMutableAttributedString(
            attributedString: Typography().attributed(
                [
                    InlineRun("office affinity 汉，字𠀀汉\u{0301} "), InlineRun("raised", traits: [.strong]),
                    InlineRun(" tail 🙂 ", traits: [.emphasis])
                ], size: 22))
        let range = (text.string as NSString).range(of: "office")
        text.addAttributes([.foregroundColor: PlatformColor.red, .baselineOffset: 4.25], range: range)
        let prepared = ParagraphPreparation(text, fontSize: 22, verbatim: false)
        for width: CGFloat in [650, 300, 500, 650] {
            let cached = drawingParagraph(text, width: width, preparation: prepared)
            let uncached = drawingParagraph(text, width: width)
            let actual = try paragraphBitmap(cached, batched: true)
            let expected = try paragraphBitmap(uncached, batched: true)
            #expect(differingParagraphPixels(actual, expected) == 0)
        }
        let factoryA = ParagraphFragmentFactory(prepared.attributed, glyphPaintCache: prepared.glyphPaintCache)
        let factoryB = ParagraphFragmentFactory(prepared.attributed, glyphPaintCache: prepared.glyphPaintCache)
        let a = factoryA.materialize(range)
        let b = factoryB.materialize(range)
        let shared = try #require(a.glyphPaint)
        #expect(shared === b.glyphPaint)
        #expect(a.line as AnyObject !== b.line as AnyObject)
        #expect(a.glyphInset == b.glyphInset && a.boundaries == b.boundaries)
        let unsupported = NSMutableAttributedString(attributedString: text)
        unsupported.addAttribute(.strokeWidth, value: -3, range: range)
        let unsupportedFactory = ParagraphFragmentFactory(unsupported, glyphPaintCache: FragmentGlyphPaintCache())
        #expect(unsupportedFactory.materialize(range).glyphPaint == nil)
    }

    @Test func cachedPaintAndCaretValuesKeepLayoutObjectsLazyAndSnapshotLocal() throws {
        let text = mixedFontDrawingText()
        // Links use the decoration route; this test isolates paint-only hits.
        text.removeAttribute(.link, range: NSRange(location: 0, length: text.length))
        let prepared = ParagraphPreparation(text, fontSize: 22, verbatim: false)
        let cold = drawingParagraph(text, width: 300, preparation: prepared, deferFragments: true)
        #expect(cold.lines.flatMap(\.fragments).allSatisfy { !$0.isMaterialized })
        let expected = try paragraphBitmap(drawingParagraph(text, width: 300), batched: true)
        #expect(try paragraphBitmap(cold, batched: true) == expected)
        #expect(cold.lines.flatMap(\.fragments).contains { $0.isMaterialized })

        let warm = drawingParagraph(text, width: 300, preparation: prepared, deferFragments: true)
        let independent = drawingParagraph(text, width: 300, preparation: prepared, deferFragments: true)
        #expect(try paragraphBitmap(warm, batched: true) == expected)
        #expect(warm.lines.flatMap(\.fragments).allSatisfy { !$0.isMaterialized })
        let reference = drawingParagraph(text, width: 300)
        for (actual, eager) in zip(warm.lines, reference.lines) {
            for fraction: CGFloat in [0, 0.25, 0.6, 1] {
                let point = CGPoint(x: actual.width * fraction, y: 0)
                let index = actual.stringIndex(forPosition: point)
                #expect(index == eager.stringIndex(forPosition: point))
                #expect(actual.offset(forStringIndex: index) == eager.offset(forStringIndex: index))
            }
        }
        let a = try #require(warm.lines.first?.fragments.first)
        let b = try #require(independent.lines.first?.fragments.first)
        #expect(warm.lines.flatMap(\.fragments).allSatisfy { !$0.isMaterialized })
        #expect(!b.isMaterialized)
        #expect(a.line as AnyObject !== b.line as AnyObject)
        #expect(a.isMaterialized && b.isMaterialized)
        #expect(a.boundaries == b.boundaries && a.glyphInset == b.glyphInset)
        // Raw UTF-16 positions inside combining/emoji graphemes are not cached
        // caret boundaries. They must retain the exact CTLine fallback too.
        for (actual, eager) in zip(warm.lines, reference.lines) {
            for index in actual.range.location...NSMaxRange(actual.range) {
                #expect(actual.offset(forStringIndex: index) == eager.offset(forStringIndex: index))
            }
        }
        #expect(try paragraphBitmap(warm, batched: true) == expected)
    }

    @Test func longFragmentPaintKeepsBoundedCaretPreparationAndMaterializationFallback() throws {
        for count in [63, 64] {
            let text = NSAttributedString(
                string: String(repeating: "i", count: count),
                attributes: [.font: PlatformFont.systemFont(ofSize: 12), .foregroundColor: PlatformColor.black])
            let range = NSRange(location: 0, length: text.length)
            let cache = FragmentGlyphPaintCache()
            let first = ParagraphFragmentFactory(text, glyphPaintCache: cache).materialize(range)
            let paint = try #require(first.glyphPaint)
            #expect((paint.carets != nil) == (count == 63))
            let factory = ParagraphFragmentFactory(text, glyphPaintCache: cache)
            let geometry = FragmentGeometry(
                range: range, x: 0, width: 500, drawOffset: 0, capsuleLeft: 0, capsuleRight: 0)
            let store = LineFragmentStore(factory: factory, geometry: [geometry])
            let fragment = ShapedFragment(geometry, store: store, index: 0)
            let line = ShapedLine(
                range: range, line: factory.textLine(range), origin: .zero, ascent: 12, descent: 3, width: 500,
                fragments: .init([fragment]))
            let context = try #require(
                CGContext(
                    data: nil, width: 600, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            #expect(!store.isMaterialized)
            ParagraphGlyphDrawing.draw(line, attributed: text, in: context)
            #expect(store.isMaterialized == (count == 64))
            #expect(fragment.boundaries == first.boundaries)
        }
    }

    @Test(requiresReferenceFaces("STSongti-SC-Regular", "SimSong-Regular"))
    func mixedFontsUseReferenceSongtiAndSimSongFaces() {
        let text = mixedFontDrawingText()
        var fonts = Set<String>()
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { font, _, _ in
            if let font = font as? PlatformFont { fonts.insert(font.fontName) }
        }
        #expect(fonts.contains(where: { $0.hasPrefix("SimSong") }))
        #expect(fonts.contains(where: { $0.hasPrefix("STSongti") }))
    }

    @Test func trackedCompoundHasIdenticalInkAndOneSearchablePDFIdentifier() throws {
        let source = "Paragraph_10"
        let text = Typography().attributed([InlineRun(source)], size: 22)
        let paragraph = drawingParagraph(text)
        #expect(paragraph.lines.count == 1)
        #expect(paragraph.lines[0].fragments.count > 1)
        let previous = try paragraphBitmap(paragraph, batched: false)
        let current = try paragraphBitmap(paragraph, batched: true)
        #expect(inkParagraphPixels(previous) > 100)
        #expect(differingParagraphPixels(previous, current) == 0)
        let pdf = try #require(PDFDocument(data: paragraphPDF(paragraph)))
        let page = try #require(pdf.page(at: 0))
        #expect(pdf.findString(source, withOptions: []).count == 1)
        #expect(page.string?.trimmingCharacters(in: .whitespacesAndNewlines) == source)
        #expect(page.string?.contains("\u{FFFC}") == false)
        // This identifier intentionally has no ligatures. CTFontDrawGlyphs
        // preserves glyph geometry; glyph-cmap PDF extraction is not a promise
        // to reconstruct arbitrary ligature/combining source strings.
    }

    @Test func mixedFontsBaselinesColorsAndLinksRetainEveryPaintedPixel() throws {
        let text = mixedFontDrawingText()
        let source = text.string as NSString
        #expect(text.attribute(.link, at: source.range(of: "Link_20").location, effectiveRange: nil) != nil)
        let emojiRange = source.range(of: "👩‍👩‍👧‍👦")
        text.addAttribute(.baselineOffset, value: 3.5, range: emojiRange)
        let paragraph = drawingParagraph(text, width: 300)
        var shapedFonts = Set<String>()
        for line in paragraph.lines {
            for fragment in line.fragments {
                for run in CTLineGetGlyphRuns(fragment.line) as! [CTRun] {
                    if let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as? PlatformFont {
                        shapedFonts.insert(font.fontName)
                    }
                }
            }
        }
        #expect(shapedFonts.contains(where: { $0.contains("AppleColorEmoji") }))
        let previous = try paragraphBitmap(paragraph, batched: false)
        let current = try paragraphBitmap(paragraph, batched: true)
        #expect(differingParagraphPixels(previous, current) == 0)
        let red = stride(from: 0, to: previous.count, by: 4).filter {
            Int(previous[$0]) > Int(previous[$0 + 2]) + 30 && previous[$0 + 1] < 150
        }.count
        let blue = stride(from: 0, to: previous.count, by: 4).filter {
            Int(previous[$0 + 2]) > Int(previous[$0]) + 30 && previous[$0 + 1] < 150
        }.count
        #expect(red > 25 && blue > 25)
    }

    @Test func decoratedMiddleFragmentFlushesAndPreservesFollowingGlyphPositions() throws {
        let font = PlatformFont.systemFont(ofSize: 22)
        let base = NSAttributedString(
            string: "before underlined after", attributes: [.font: font, .foregroundColor: PlatformColor.black])
        let range = (base.string as NSString).range(of: "underlined")
        let decorations: [[NSAttributedString.Key: Any]] = [
            [.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: PlatformColor.red],
            [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: PlatformColor.blue],
            [.strokeWidth: -3, .strokeColor: PlatformColor.red]
        ]
        let plain = try paragraphBitmap(drawingParagraph(base), batched: false)
        for (index, paint) in decorations.enumerated() {
            let text = NSMutableAttributedString(attributedString: base)
            text.addAttributes(paint, range: range)
            let paragraph = drawingParagraph(text)
            #expect(paragraph.lines[0].fragments.count >= 3)
            let previous = try paragraphBitmap(paragraph, batched: false)
            let current = try paragraphBitmap(paragraph, batched: true)
            #expect(differingParagraphPixels(previous, current) == 0, "Decoration \(index)")
            if index != 1 { #expect(differingParagraphPixels(plain, previous) > 10) }
            let prepared = ParagraphPreparation(text, fontSize: 22, verbatim: false)
            let cold = drawingParagraph(text, preparation: prepared, deferFragments: true)
            #expect(try paragraphBitmap(cold, batched: true) == previous)
            let warm = drawingParagraph(text, preparation: prepared, deferFragments: true)
            #expect(try paragraphBitmap(warm, batched: true) == previous)
        }
    }

    @Test func attachmentDelegatesProduceNeitherPlaceholderInkNorPDFText() throws {
        let math = MathAttachment(source: "\\frac{1}{2}", size: 22, display: false)
        #expect(math.result.diagnostics.isEmpty)
        let bitmap = try #require(
            CGContext(
                data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 32,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(PlatformColor.red.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        let image = DocumentImage(bitmap: try #require(bitmap.makeImage()), size: CGSize(width: 8, height: 6))
        let objects = [
            math.attributed(color: .black),
            ImageAttachment(image: image, maximumWidth: 100, altText: "Authored image").attributed()
        ]
        for object in objects {
            #expect(object.string == "\u{FFFC}")
            #expect(
                object.attribute(
                    NSAttributedString.Key(kCTRunDelegateAttributeName as String), at: 0, effectiveRange: nil) != nil)
            let visible = NSMutableAttributedString(attributedString: object)
            // Make an accidental placeholder visible; skipping cannot pass only
            // because the attachment's usual foreground color is transparent.
            visible.addAttributes(
                [.font: PlatformFont.systemFont(ofSize: 32), .foregroundColor: PlatformColor.magenta],
                range: NSRange(location: 0, length: 1))
            let paragraph = drawingParagraph(visible)
            #expect(!paragraph.lines.isEmpty && !paragraph.lines[0].fragments.isEmpty)
            #expect(inkParagraphPixels(try paragraphBitmap(paragraph, batched: true)) == 0)
            let pdf = try #require(PDFDocument(data: paragraphPDF(paragraph)))
            #expect(pdf.page(at: 0)?.string?.isEmpty ?? true)
            // Math/image owners paint the attachment separately. This helper
            // must not emit even an invisible FFFC glyph or semantic-text copy.
        }
    }
}
