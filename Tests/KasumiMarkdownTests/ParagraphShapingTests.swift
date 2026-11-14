#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import CoreText
import Foundation
import Testing
@testable import KasumiMarkdown

private func measuredStyle() -> Typography {
    Typography().applying(ProfileValues([.baseSize: .number(20), .latinScale: .number(0.8), .hanScale: .number(1),
        .cjkPunctFace: .string("native"), .punctSqueeze: .number(0.25), .autoRaggedNarrow: .flag(false)]))
}

@Test(requiresReferenceFaces("STSongti-SC-Regular"))
func paragraphShapingKeepsOriginalLatinEmAcrossHanFontSpans() throws {
    let style = measuredStyle(), text = style.attributed([InlineRun("甲，乙")])
    let input = ParagraphShaper.shape(text, fallbackSize: 20)
    #expect(input.clusters.map(\.advance) == [20,20,20])
    let page = ParagraphTypesetter.layout(text, width: 400, fontSize: 20, alignment: .leading, profileValues: style.profileValues)
    let line = try #require(page.lines.first)
    // Reference case: measured20, run-em16, squeeze.25.
    #expect(line.fragments.map(\.x) == [0,20,32])
    #expect(line.fragments.map(\.width) == [20,8,20])
}

@Test(requiresReferenceFaces("STSongti-SC-Regular"))
func paragraphPunctuationDrawingAndHitTestingShareSourceBackedBoxes() throws {
    let style = measuredStyle(), source = "甲（乙）丙"
    let text = style.attributed([InlineRun(source, traits: [.link], destination: "#target")])
    let page = ParagraphTypesetter.layout(text, width: 400, fontSize: 20, alignment: .leading, profileValues: style.profileValues)
    let line = try #require(page.lines.first)
    #expect(line.fragments.map(\.x) == [0,24,32,52,64])
    #expect(line.fragments.map(\.width) == [20,8,20,8,20])
    let opening = try #require(line.fragments.first { $0.range.location == 1 })
    #expect(opening.drawOffset == -12)
    #expect(line.offset(forStringIndex: 1) == 24 && line.offset(forStringIndex: 2) == 32)
    #expect(line.offset(forStringIndex: 1, affinity: .precedingFragment) == 20)
    #expect(line.stringIndex(forPosition: CGPoint(x: 25, y: 0)) == 1)
    #expect(line.stringIndex(forPosition: CGPoint(x: 31, y: 0)) == 2)
}

@Test func paragraphShapingExcludesCapsulePaddingFromCodeDensityInputs() throws {
    let style = Typography().applying(ProfileValues([.codeCapsule: .flag(true), .codeCapsulePad: .number(0.8)]))
    let text = style.attributed([InlineRun("a "), InlineRun("code()", traits: [.code]), InlineRun(" b")])
    let input = ParagraphShaper.shape(text, fallbackSize: 16)
    #expect(input.clusters.map(\.text).joined() == "a code() b")
    #expect(input.metrics.count == 3 && input.metrics[1].isCode)
    #expect(input.metrics[1].flags == 4 && input.metrics[1].em == 14)
    let actualCode = input.clusters.filter { input.metrics[$0.run].isCode }.reduce(Float(0)) { $0 + $1.advance }
    let ordinary = NSAttributedString(string: "code()", attributes: [.font: style.font(size: 16 * 0.88, code: true)])
    let expected = Float(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(ordinary), nil, nil, nil))
    #expect(abs(actualCode - expected) < 0.0001)
    #expect(DocumentTextMap(text).string == "a code() b")
}

@Test func paragraphShapingRetainsAttachmentWidthAndKnownNativeSourceFlags() throws {
    let style = Typography()
    let text = style.attributed([InlineRun("甲"), InlineRun(#"\frac{a}{b}"#, traits: [.math]), InlineRun("乙")])
    let input = ParagraphShaper.shape(text, fallbackSize: 16)
    let math = try #require(text.attribute(.kasumiMath, at: 1, effectiveRange: nil) as? MathAttachment)
    #expect(input.metrics.map(\.flags) == [0,0x40,0])
    #expect(abs(input.clusters[1].advance - Float(math.result.box.width)) < 0.0001)
    let reference = style.attributed([InlineRun("1", traits: [.footnote])])
    let script = ParagraphShaper.shape(reference, fallbackSize: 16)
    #expect(script.metrics.first?.flags == 0x10)
    #expect(script.metrics.first?.em == 11) // round(16×.7), native flag0x10.
}

@Test func paragraphGlyphAggregationPreservesLigaturesAndWholeGraphemes() {
    let source = "fi👩‍👩‍👧‍👦e\u{301}", text = Typography().attributed([InlineRun(source)])
    let input = ParagraphShaper.shape(text, fallbackSize: 16)
    #expect(input.clusters.map(\.text) == source.map(String.init))
    let shaped = Float(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil))
    #expect(abs(input.clusters.reduce(0) { $0 + $1.advance } - shaped) < 0.0001)
    let boundaries = Set(source.indices.map { $0.utf16Offset(in: source) } + [(source as NSString).length])
    let layout = ParagraphTypesetter.layout(text, width: 60, fontSize: 16)
    for line in layout.lines {
        for fragment in line.fragments {
            #expect(boundaries.contains(fragment.range.location) && boundaries.contains(NSMaxRange(fragment.range)))
            for x in stride(from: fragment.x, through: fragment.x + fragment.width, by: 1) {
                #expect(boundaries.contains(line.stringIndex(forPosition: CGPoint(x: x, y: 0))))
            }
        }
    }
}

@Test(requiresReferenceFaces("STSongti-SC-Regular"))
func paragraphGlyphEmNormalizationUsesScalarAndExactSelectedFaces() throws {
    let han = try #require(PlatformFont(name: "STSongti-SC-Regular", size: 20)), latin = PlatformFont.systemFont(ofSize: 16)
    #expect(ParagraphShaper.normalizesToEm(0xff0c, font: han as CTFont, han: han as CTFont, punctuation: nil))
    #expect(!ParagraphShaper.normalizesToEm(0xff0c, font: latin as CTFont, han: han as CTFont, punctuation: nil))
    for scalar: UInt32 in [0x302a,0x302f,0xff61,0xff65,0x1f600] {
        #expect(!ParagraphShaper.normalizesToEm(scalar, font: han as CTFont, han: han as CTFont, punctuation: nil))
    }
}

@Test func paragraphIndentUsesFirstRunEmAndNarrowFallbackUsesOuterMeasure() throws {
    let style = measuredStyle().applying(ProfileValues([.baseSize: .number(20), .latinScale: .number(0.8),
        .paraSeparation: .string("indent"), .firstLineIndent: .number(2), .autoRaggedNarrow: .flag(false)]))
    let page = DocumentTypesetter.layout(DocumentParser.parse("First paragraph"), width: 500, style: style, insets: .zero)
    let line = try #require(page.paragraphs.first?.paragraph.lines.first)
    #expect(line.offset(forStringIndex: 0) == 32) // first run16em, not global20.
    let text = Typography().attributed([InlineRun("甲乙丙丁戊己庚辛壬癸")])
    let narrow = ParagraphTypesetter.layout(text, width: 100, fontSize: 16, outerWidth: 319, baseEm: 16)
    let boundary = ParagraphTypesetter.layout(text, width: 100, fontSize: 16, outerWidth: 320, baseEm: 16)
    #expect(narrow.autoRagged && !boundary.autoRagged)
}

@Test func paragraphCodeDensityDecisionIsIndependentOfCapsulePadding() throws {
    let runs = [InlineRun("AA "), InlineRun("BBBBBB", traits: [.code]), InlineRun(" CC")]
    var values = ProfileValues([.autoRaggedNarrow: .flag(false), .raggedCodeFraction: .number(0.45), .codeCapsule: .flag(true)])
    for padding in [0.0, 0.8] {
        values[.codeCapsulePad] = .number(padding)
        let style = Typography().applying(values)
        let layout = ParagraphTypesetter.layout(style.attributed(runs), width: 400, fontSize: 16, profileValues: values)
        let line = try #require(layout.lines.first)
        #expect(line.adjustmentRatio == 0)
        #expect(!layout.autoRagged) // code-density and narrow flags are distinct.
    }
    values[.raggedCodeFraction] = .number(0)
    let style = Typography().applying(values)
    let disabled = ParagraphTypesetter.layout(style.attributed(runs), width: 400, fontSize: 16, profileValues: values)
    #expect(try #require(disabled.lines.first).adjustmentRatio > 0)
}

@Test func paragraphShapingKeepsRunMetadataAcrossHanFontSpans() {
    let style = measuredStyle(), text = style.attributed([InlineRun("甲，乙")])
    let input = ParagraphShaper.shape(text, fallbackSize: 20)
    #expect(input.metrics.count == 1)
    #expect(input.metrics.first?.em == 16)
    #expect(input.clusters.map(\.run) == [0,0,0])
    #expect(text.string == "甲，乙")
}

@Test func paragraphPunctuationPreservesSourceTextAndLinks() {
    let style = measuredStyle(), source = "甲（乙）丙"
    let text = style.attributed([InlineRun(source, traits: [.link], destination: "#target")])
    #expect(DocumentTextMap(text).string == source)
    for index in 0..<text.length { #expect(text.attribute(.link, at: index, effectiveRange: nil) as? String == "#target") }
}

@Test func paragraphHanScalarsNormalizeWithoutSelectedFace() {
    let latin = PlatformFont.systemFont(ofSize: 16)
    #expect(ParagraphShaper.normalizesToEm(0x20000, font: latin as CTFont, han: nil, punctuation: nil))
}
