import AppKit
import CoreText
import Foundation
import Testing
@testable import KasumiMarkdown

@Test func profileFontSizesMatchNativeNearestAwayRoundingBeforeFaceScaling() throws {
    // Nearest-away rounding: 14.96 rounds up, and 22.5 rounds away from zero.
    for (size, scale, expected) in [(16.0, 1.0, 14.0), (17.0, 1.0, 15.0), (16.0, 1.25, 18.0)] {
        let style = Typography().applying(ProfileValues([.baseSize: .number(size), .codeScale: .number(scale)]))
        let text = style.attributed([InlineRun("code", traits: [.code])])
        #expect((text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == CGFloat(expected))
    }
    let style = Typography().applying(ProfileValues([.baseSize: .number(15), .latinScale: .number(0.97),
        .scriptScale: .number(0.5), .headingScale: .numbers([1.6,1.5,1.4,1.3,1.2,1.1])]))
    let page = DocumentTypesetter.layout(DocumentParser.parse("## Heading\n\nBody"), width: 500, style: style)
    let heading = try #require(page.paragraphs.first)
    let body = try #require(page.paragraphs.last)
    let headingFont = try #require(heading.paragraph.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    let bodyFont = try #require(body.paragraph.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    #expect(abs(headingFont.pointSize - 22.31) < 1e-8) // round(15×1.5)×.97
    #expect(abs(bodyFont.pointSize - 14.55) < 1e-8) // ordinary body stays unrounded
    #expect(style.font(size: 14.5, code: true).pointSize == 15)
}

@Test func profileFontsUseReferenceSCFacesAndLatinRelativeBaselines() throws {
    // Independent native FaceSpec observations, including the nil trim on
    // PingFang Fangsong/Xihei and Songti's negative Fangsong correction.
    let emphasis: [(String, String, Bool, String, Double)] = [
        ("Songti SC", "kai", false, "STKaitiSC-Regular", 0.006),
        ("Songti SC", "kai", true, "STKaitiSC-Bold", 0),
        ("Songti SC", "fangsong", false, "STFangsong", -0.065),
        ("Songti SC", "fangsong", true, "STFangsong", -0.065),
        ("Songti SC", "xihei", false, "STXihei", -0.065),
        ("Songti SC", "xihei", true, "STHeiti", -0.065),
        ("Songti SC", "none", false, "STSongti-SC-Regular", 0),
        ("Songti SC", "none", true, "STSongti-SC-Black", -0.055),
        ("PingFang SC", "kai", false, "STKaitiSC-Regular", 0.067),
        ("PingFang SC", "kai", true, "STKaitiSC-Bold", 0.06),
        ("PingFang SC", "fangsong", false, "STFangsong", 0),
        ("PingFang SC", "fangsong", true, "STFangsong", 0),
        ("PingFang SC", "xihei", false, "STXihei", 0),
        ("PingFang SC", "xihei", true, "STHeiti", 0),
        ("PingFang SC", "none", false, "PingFangSC-Regular", 0),
        ("PingFang SC", "none", true, "PingFangSC-Semibold", 0)
    ]
    for (family, italic, strong, postScript, trim) in emphasis {
        let values = ProfileValues([.hanFamily: .string(family), .cjkItalicFace: .string(italic),
                                    .hanBaseline: .number(0.04), .latinScale: .number(0.97), .hanScale: .number(1.2)])
        let style = Typography().applying(values)
        let traits: Set<InlineRun.Trait> = strong ? [.emphasis, .strong] : [.emphasis]
        let text = style.attributed([InlineRun("汉", traits: traits)])
        let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.fontName == postScript, "\(family) \(italic) strong=\(strong)")
        #expect(abs(font.pointSize - 19.2) < 1e-10)
        let baseline = try #require(text.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? Double)
        #expect(abs(baseline - (0.04 + trim) * 15.52) < 1e-10)
    }
    let pagella = Typography().applying(BuiltinProfiles.all[1].effective)
    #expect(pagella.font().fontName == "TeXGyrePagella-Regular")
    #expect(pagella.font(strong: true).fontName == "TeXGyrePagella-Bold")
    #expect(pagella.font(emphasis: true).fontName == "TeXGyrePagella-Italic")
    #expect(pagella.font(strong: true, emphasis: true).fontName == "TeXGyrePagella-BoldItalic")
    #expect(abs(pagella.font().pointSize - 15.52) < 1e-10)
    #expect(pagella.font(size: 24, weight: .bold).fontName == "TeXGyrePagella-Bold")
    #expect(pagella.font(size: 24, weight: .semibold).fontName == "TeXGyrePagella-Regular")
    let avenir = Typography().applying(BuiltinProfiles.all[4].effective)
    #expect(avenir.font(size: 24, weight: .bold).fontName == "AvenirNext-Bold")
    #expect(avenir.font(size: 24, weight: .semibold).fontName == "AvenirNext-Regular")
    let empty = Typography().applying(ProfileValues([.latinFamily: .string(""), .hanFamily: .string("")]))
    #expect(empty.latinFamily == "New York" && empty.hanFamily == "Songti SC")
}

@Test func profileHeadingAndTraditionalFacesStaySeparateFromBodySubstitution() throws {
    var style = Typography().applying(ProfileValues([.hanFamily: .string("Songti SC"), .cjkStrongFace: .string("hei"), .headingHanBaseline: .number(0.06)]))
    let heading = style.attributed([InlineRun("汉")], size: 24, heading: true, headingLevel: 2)
    #expect((heading.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "STSongti-SC-Bold")
    #expect(abs((heading.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? Double ?? 0) - 1.44) < 1e-10)
    style.hanFamily = "Songti TC"
    let normal = style.attributed([InlineRun("漢")])
    let italic = style.attributed([InlineRun("漢", traits: [.emphasis])])
    #expect((italic.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == (normal.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName)
    #expect((italic.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? Double) == 0)
}

@Test func profileInlineCapsulesReservePaddingAndKeepTextSearchable() throws {
    let run = InlineRun("code()", traits: [.code])
    let plain = Typography().attributed([run])
    let style = Typography().applying(ProfileValues([.codeCapsule: .flag(true), .codeCapsulePad: .number(0.3)]))
    let capsule = style.attributed([run])
    func width(_ text: NSAttributedString) -> Double { CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil) }
    #expect(abs(width(capsule) - width(plain) - 2 * 14 * 0.3) < 1e-8)
    let mapping = DocumentTextMap(capsule)
    #expect(mapping.string == "code()")
    #expect(mapping.substring(in: NSRange(location: 0, length: capsule.length)) == "code()")
    #expect(mapping.matches("code").count == 1)
    #expect(capsule.attribute(.kasumiCodeCapsule, at: 0, effectiveRange: nil) is InlineCodeCapsule)
    let blockCode = style.attributed([run], size: 14.08, code: true)
    #expect(blockCode.string == "code()")
    #expect(blockCode.attribute(.kasumiCodeCapsule, at: 0, effectiveRange: nil) == nil)
}

@Test func profileListColumnsQuoteBarsAndTableGridRespondToOverrides() throws {
    let document = DocumentParser.parse("9. Nine\n10. Ten\n\n- Bullet\n- More\n\n> A quotation with enough text to wrap onto multiple lines in a very narrow column.\n\n| A | B |\n| - | - |\n| C | D |\n")
    var values = BuiltinProfiles.all[0].effective
    let plain = DocumentTypesetter.layout(document, width: 300, style: Typography().applying(values), insets: .zero)
    let nine = try #require(plain.paragraphs.first { $0.paragraph.attributed.string == "Nine" })
    let ten = try #require(plain.paragraphs.first { $0.paragraph.attributed.string == "Ten" })
    #expect(nine.origin.x == ten.origin.x)
    let bullet = try #require(plain.paragraphs.first { $0.paragraph.attributed.string == "Bullet" })
    values[.listBulletSize] = .number(0.7)
    let larger = DocumentTypesetter.layout(document, width: 300, style: Typography().applying(values), insets: .zero)
    #expect(larger.paragraphs.first { $0.paragraph.attributed.string == "Bullet" }?.origin.x == bullet.origin.x)
    #expect(larger.backgrounds.filter { $0.radius > 0 }.map { $0.rect.width } == [11.2, 11.2])
    values[.listMarkerGap] = .number(20)
    values[.quoteBarGap] = .number(30)
    values[.tableStyle] = .string("grid")
    let changed = DocumentTypesetter.layout(document, width: 300, style: Typography().applying(values), insets: .zero)
    #expect(changed.paragraphs.first { $0.paragraph.attributed.string == "Nine" }?.origin.x == nine.origin.x + 12)
    let quote = try #require(changed.paragraphs.first { $0.paragraph.attributed.string.hasPrefix("A quotation") })
    #expect(quote.origin.x == 41)
    let bar = try #require(changed.rules.first { $0.width == 3 })
    #expect(bar.end.y - bar.start.y == quote.paragraph.height)
    #expect(quote.paragraph.lines.count > 1)
    #expect(changed.rules.filter { $0.start.x == $0.end.x }.count == plain.rules.filter { $0.start.x == $0.end.x }.count + 3)
}

@Test func profileThemeHighlightsAndCapsulesReachTheRaster() throws {
    let document = DocumentParser.parse("==highlight== and `capsule()`")
    var style = Typography().applying(ProfileValues([.codeCapsule: .flag(true)]))
    style.lightThemeID = "solarized-light"
    let layout = DocumentTypesetter.layout(document, width: 400, style: style)
    let width = 400, height = Int(ceil(layout.height))
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
    context.setFillColor(style.paperColor.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    DocumentTypesetter.draw(layout, in: context)
    let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    for key in ["mark_background", "code_capsule_background"] {
        let color = try #require(style.documentTheme.color(key)?.usingColorSpace(.sRGB))
        let rgb = [color.redComponent, color.greenComponent, color.blueComponent].map { Int(round($0 * 255)) }
        let count = stride(from: 0, to: width * height * 4, by: 4).filter { offset in
            (0..<3).allSatisfy { abs(Int(data[offset + $0]) - rgb[$0]) <= 2 }
        }.count
        #expect(count > 20, "The \(key) background must be painted, not only stored as an attributed-string property")
    }
    let mono = DocumentTypesetter.layout(document, width: 400, style: Typography().applying(style.profileValues))
    #expect(layout.height == mono.height)
    #expect(layout.paragraphs.map { $0.paragraph.lines.map(\.width) } == mono.paragraphs.map { $0.paragraph.lines.map(\.width) })
}
