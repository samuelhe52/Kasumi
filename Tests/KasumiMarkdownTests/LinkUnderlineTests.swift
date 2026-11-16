import CoreGraphics
import Foundation
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

fileprivate func linkBitmap(_ layout: DocumentLayout, extra: [PaintedRect] = [], tiled: Bool = false) throws -> [UInt8] {
    let width = Int(ceil(layout.width * 2))
    let height = Int(ceil(layout.height * 2))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
        let context = try #require(
            CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 2, y: -2)
        func paint() {
            DocumentTypesetter.draw(layout, in: context)
            for paint in extra {
                context.setFillColor(paint.color.cgColor)
                context.fill(paint.rect)
            }
        }
        if tiled {
            for y in stride(from: CGFloat(0), to: layout.height, by: 31) {
                for x in stride(from: CGFloat(0), to: layout.width, by: 79) {
                    context.saveGState()
                    context.clip(to: CGRect(x: x, y: y, width: 79, height: 31))
                    paint()
                    context.restoreGState()
                }
            }
        } else {
            paint()
        }
    }
    return pixels
}

@Suite struct LinkUnderlineTests {
    @Test(arguments: [false, true])
    func solidLinksKeepBaseGeometryBetweenDescenders(dark: Bool) throws {
        var style = Typography().applying(ProfileValues([.baseSize: .number(24)]))
        style.dark = dark
        style.lightThemeID = "mono-light"
        style.darkThemeID = "mono-dark"
        let layout = DocumentTypesetter.layout(
            DocumentParser.parse("[More **to** the *middle*](#middle)"), width: 600, style: style)
        let placed = try #require(layout.paragraphs.first)
        let line = try #require(placed.paragraph.lines.first)
        #expect(placed.paragraph.underlines.count == 1)
        let paint = try #require(placed.paragraph.underlines.first)
        let expectedRect = CGRect(
            x: line.origin.x,
            y: line.origin.y + 24 * 0.185,
            width: line.width, height: 24 * 0.07)
        #expect(paint.rect == expectedRect)
        #expect(abs(paint.color.cgColor.alpha - 0.4) < 0.000001)

        // No descenders here: glyph-only paint plus one independently positioned
        // stripe. Separate p/g cases below check contour clearance.
        var paragraph = placed.paragraph
        paragraph.underlines = []
        var reference = layout
        reference.paragraphs = [PlacedText(paragraph: paragraph, origin: placed.origin, textOffset: placed.textOffset)]
        let expected = PaintedRect(
            rect: expectedRect.offsetBy(dx: placed.origin.x, dy: placed.origin.y),
            color: try #require(style.documentTheme.color("link")).withAlphaComponent(0.4))
        #expect(try linkBitmap(layout).elementsEqual(linkBitmap(reference, extra: [expected])))
        #expect(try linkBitmap(layout, tiled: true).elementsEqual(linkBitmap(reference, extra: [expected], tiled: true)))
    }

    @Test func wrappedLinksFollowEngineLineWidthsAcrossStyles() throws {
        let source = "[A **bold** and *italic* link spanning many words and 中文 across several lines](#target)"
        let layout = DocumentTypesetter.layout(DocumentParser.parse(source), width: 280, style: Typography())
        let placed = try #require(layout.paragraphs.first)
        #expect(placed.paragraph.lines.count > 1)
        for line in placed.paragraph.lines {
            let y = line.origin.y + 16 * 0.185
            let paints = placed.paragraph.underlines.filter { abs($0.rect.minY - y) < 0.001 }
            #expect(!paints.isEmpty)
            let left = line.origin.x
            let right = left + max(line.width, line.hyphen.map { $0.x + $0.width } ?? 0)
            for paint in paints {
                #expect(paint.rect.minX >= left - 0.001 && paint.rect.maxX <= right + 0.001)
            }
            for (a, b) in zip(paints, paints.dropFirst()) { #expect(a.rect.maxX <= b.rect.minX) }
        }
    }

    @Test(arguments: ["LinkJumps.md#middle", "file:///tmp/document.md", "mailto:reader@example.com"])
    func nonWebTargetsUseDashedIndicators(destination: String) throws {
        let style = Typography().applying(ProfileValues([.baseSize: .number(20)]))
        let layout = DocumentTypesetter.layout(
            DocumentParser.parse("[A link to file or email](\(destination))"), width: 600, style: style)
        let paints = try #require(layout.paragraphs.first).paragraph.underlines
        #expect(paints.count > 2)
        for (index, paint) in paints.enumerated() {
            #expect(abs(paint.rect.height - 1.4) < 0.001)
            #expect(abs(paint.color.cgColor.alpha - 0.7) < 0.000001)
            if index + 1 < paints.count {
                #expect(abs(paint.rect.width - 6) < 0.001)
                #expect(abs(paints[index + 1].rect.minX - paint.rect.maxX - 3) < 0.001)
            }
        }
    }

    @Test func footnotesAndImagesStayUnmarkedWhileLinkedMathAndCodeAreCovered() async throws {
        let base = testRepositoryURL.appendingPathComponent("fixtures")
        let document = DocumentParser.parse(
            "[`linked code` and $x_i$](#target) ![image](images/tiny.png) [^note]\n\n[^note]: Note.",
            baseURL: base)
        _ = await DocumentImageStore.shared.preload(document)
        let layout = DocumentTypesetter.layout(document, width: 600, style: Typography())
        let placed = try #require(layout.paragraphs.first)
        let line = try #require(placed.paragraph.lines.first)
        let attributes = placed.paragraph.attributed
        var mathRange: NSRange?
        attributes.enumerateAttribute(.kasumiMath, in: line.range) { value, range, _ in
            if value != nil { mathRange = range }
        }
        let math = try #require(mathRange)
        let mathX = line.origin.x + line.offset(forStringIndex: math.location)
        #expect(placed.paragraph.underlines.contains { $0.rect.minX <= mathX && $0.rect.maxX > mathX })
        let codeRange = (attributes.string as NSString).range(of: "linked code")
        let codeX = line.origin.x + line.offset(forStringIndex: codeRange.location)
        #expect(placed.paragraph.underlines.contains { $0.rect.minX <= codeX && $0.rect.maxX > codeX })
        // A standalone linked image and a resolved footnote are both clickable,
        // but neither has the ordinary text-link indicator.
        let excluded = DocumentParser.parse(
            "[![image](images/tiny.png)](#target) [^note]\n\n[^note]: Note.", baseURL: base)
        let excludedLayout = DocumentTypesetter.layout(excluded, width: 600, style: Typography())
        #expect(try #require(excludedLayout.paragraphs.first).paragraph.underlines.isEmpty)
    }

    @Test func ordinaryUnderlinesShareLinkGeometryAndPixels() throws {
        let style = Typography().applying(ProfileValues([.baseSize: .number(32)]))
        let linked = NSMutableAttributedString(
            attributedString: style.attributed([InlineRun("aa p aa g aa", traits: [.link], destination: "#target")]))
        let full = NSRange(location: 0, length: linked.length)
        linked.addAttribute(.foregroundColor, value: PlatformColor.black, range: full)
        let ordinary = NSMutableAttributedString(attributedString: linked)
        ordinary.removeAttribute(.link, range: full)
        ordinary.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: full)
        let link = ParagraphTypesetter.layout(linked, width: 520, fontSize: 32)
        let plain = ParagraphTypesetter.layout(ordinary, width: 520, fontSize: 32)
        #expect(plain.underlines.map(\.rect) == link.underlines.map(\.rect))
        #expect(plain.underlines.count == 3)
        var a = DocumentTypesetter.layout(DocumentParser.parse("aa p aa g aa"), width: 600, style: style)
        let origin = try #require(a.paragraphs.first).origin
        a.paragraphs = [PlacedText(paragraph: plain, origin: origin, textOffset: 0)]
        var b = a
        b.paragraphs = [PlacedText(paragraph: link, origin: origin, textOffset: 0)]
        #expect(try linkBitmap(a).elementsEqual(linkBitmap(b)))
        ordinary.addAttribute(.underlineColor, value: PlatformColor.red, range: full)
        let colored = ParagraphTypesetter.layout(ordinary, width: 520, fontSize: 32)
        #expect(colored.underlines.map(\.rect) == plain.underlines.map(\.rect))
        #expect(colored.underlines.allSatisfy { $0.color == PlatformColor.red.withAlphaComponent(0.4) })
    }
}
