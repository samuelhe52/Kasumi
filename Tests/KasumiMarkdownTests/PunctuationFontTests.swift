import CoreText
import Foundation
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

@Test func punctuationFontClassifierMatchesReferenceScalarBoundariesAndSet() throws {
    struct Reference: Decodable {
        let font_boundaries: [Boundary]
        let punctuation_scalars: [UInt32]
        let scalar_validation: Validation
        struct Boundary: Decodable {
            let scalar: UInt32
            let han: Bool
        }
        struct Validation: Decodable {
            let count: Int
            let han_bitmap_sha256: String
        }
    }
    let root = testRepositoryURL
    let reference = try JSONDecoder().decode(
        Reference.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/PunctuationFonts.json")))
    #expect(reference.scalar_validation.count == 1_112_064)
    #expect(
        reference.scalar_validation.han_bitmap_sha256
            == "c0766a9603506c6b15c9b6135c3eda8ac0fc07c8b63ab602b91fce64d8545090")
    for item in reference.font_boundaries {
        let scalar = try #require(Unicode.Scalar(item.scalar))
        #expect(CJKFontRole.usesHanFont(Character(String(scalar))) == item.han, "U+\(String(item.scalar, radix: 16))")
    }
    #expect(CJKFontRole.punctuationScalars == Set(reference.punctuation_scalars))
    #expect(reference.punctuation_scalars.count == 38)
    #expect(CJKFontRole.usesHanFont("Ａ"))
    #expect(!CJKFontRole.usesHanFont("😀"))
    #expect(!CJKFontRole.usesHanFont("䷀"))  // Yijing is outside the frontend Han ranges.
}

@Test(requiresReferenceFaces("STSongti-SC-Regular", "STSongti-SC-Bold", "SimSong-Regular", "SimSong-Bold"))
func punctuationSimSongSelectionUsesFontEligibilityAndCorrectBaseline() throws {
    let style = Typography()
    let text = style.attributed([InlineRun("汉，字。～")])
    let expected = [
        "STSongti-SC-Regular", "SimSong-Regular", "STSongti-SC-Regular", "SimSong-Regular", "SimSong-Regular"
    ]
    for (index, name) in expected.enumerated() {
        let font = try #require(text.attribute(.font, at: index, effectiveRange: nil) as? PlatformFont)
        #expect(font.fontName == name && font.pointSize == 16)
        let baseline = try #require(text.attribute(.baselineOffset, at: index, effectiveRange: nil) as? Double)
        #expect(abs(baseline - (name.hasPrefix("SimSong") ? -0.24 : 0.64)) < 1e-10)
    }
    let heading = style.attributed([InlineRun("汉，")], size: 24, heading: true, headingLevel: 2)
    #expect((heading.attribute(.font, at: 1, effectiveRange: nil) as? PlatformFont)?.fontName == "SimSong-Bold")
    #expect(abs((heading.attribute(.baselineOffset, at: 1, effectiveRange: nil) as? Double ?? 1) - 0.12) < 1e-10)
}

@Test(
    requiresReferenceFaces(
        "STSongti-SC-Black", "STSongti-SC-Bold", "STSongti-SC-Regular", "SimSong-Bold", "STKaitiSC-Regular", "STHeiti"))
func punctuationRespectsStrongEmphasisNativeAndCodeChoices() throws {
    for (heavy, expected) in [("black", "STSongti-SC-Black"), ("bold", "SimSong-Bold"), ("hei", "STHeiti")] {
        let style = Typography().applying(
            ProfileValues([.hanFamily: .string("Songti SC"), .cjkStrongFace: .string(heavy)]))
        let text = style.attributed([InlineRun("，", traits: [.strong])])
        #expect((text.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.fontName == expected)
    }
    let emphasis = Typography().attributed([InlineRun("，", traits: [.emphasis])])
    #expect((emphasis.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.fontName == "STKaitiSC-Regular")
    var values = BuiltinProfiles.all[0].effective
    values[.cjkPunctFace] = .string("native")
    let native = Typography().applying(values)
    let text = native.attributed([InlineRun("，")])
    #expect((text.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.fontName == "STSongti-SC-Regular")
    #expect((text.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? Double) == 0.64)
}

@Test func punctuationFontRunsPreserveGraphemesLinksAndSemanticRanges() throws {
    let punctuation = Typography().attributed([InlineRun("汉，字。～")])
    #expect(DocumentTextMap(punctuation).string == "汉，字。～")
    let source = "A禰\u{E0100}，B"
    let text = Typography().attributed([InlineRun(source, traits: [.link], destination: "#target")])
    #expect(text.string == source && DocumentTextMap(text).string == source)
    let ns = source as NSString
    let ideograph = ns.range(of: "禰\u{E0100}")
    #expect(ideograph.length == 3)
    for position in 0..<text.length {
        #expect(text.attribute(.link, at: position, effectiveRange: nil) as? String == "#target")
    }
    #expect(DocumentTextMap(text).matches("，B").count == 1)
}

@Test func punctuationCodeChoicesAvoidSimSongSubstitution() throws {
    var values = BuiltinProfiles.all[0].effective
    values[.cjkPunctFace] = .string("native")
    let native = Typography().applying(values)
    let mono = Typography().attributed([InlineRun("，", traits: [.code])])
    let nativeMono = native.attributed([InlineRun("，", traits: [.code])])
    #expect(
        (mono.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.fontName
            == (nativeMono.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.fontName)
}

@Test(requiresReferenceFaces("STSongti-SC-Regular"))
func punctuationFontRunsUseReferenceSongtiForWholeGraphemes() throws {
    let source = "A禰\u{E0100}，B"
    let text = Typography().attributed([InlineRun(source, traits: [.link], destination: "#target")])
    let ns = source as NSString
    let ideograph = ns.range(of: "禰\u{E0100}")
    for position in ideograph.location..<NSMaxRange(ideograph) {
        #expect(
            (text.attribute(.font, at: position, effectiveRange: nil) as? PlatformFont)?.fontName
                == "STSongti-SC-Regular")
    }
}

@Test(requiresReferenceFaces("PingFangSC-Regular"))
func punctuationPingFangAvoidsSimSongSubstitution() throws {
    let family = "PingFang SC"
    let font = try #require(PlatformFont(name: family, size: 16))
    #expect(CJKFontRole.punctuationFont(for: "，", family: family, hanFont: font, enabled: true) == nil)
}

@Test(requiresReferenceFaces("STSongti-TC-Regular"))
func punctuationTraditionalSongtiAvoidsSimSongSubstitution() throws {
    let family = "Songti TC"
    let font = try #require(PlatformFont(name: family, size: 16))
    #expect(CJKFontRole.punctuationFont(for: "，", family: family, hanFont: font, enabled: true) == nil)
}
