import CoreText
import Foundation
import Testing

@testable import KasumiMarkdown

@Test func bundledMathFaceUsesReferenceFontMetrics() {
    let font = MathFont.font(size: 20)
    #expect(CTFontCopyPostScriptName(font) as String == "NewCMMath-Regular")
    #expect(CTFontGetUnitsPerEm(font) == 1000)
    #expect(FileManager.default.fileExists(atPath: MathFont.resourceURL.path))
    // Independent design-unit values read from the shipped font's MATH table
    // with fontTools. These catch wrong offsets, signedness, and em scaling.
    let m = MathFont.metrics(size: 20)
    #expect(m.scriptPercentScaleDown == 0.7)
    #expect(m.scriptScriptPercentScaleDown == 0.5)
    #expect(m.axisHeight == 5)
    #expect(m.fractionRuleThickness == 0.8)
    #expect(abs(m.fractionNumeratorDisplayStyleShiftUp - 13.54) < 0.000001)
    #expect(m.fractionDenominatorDisplayStyleShiftDown == 13.72)
    #expect(abs(m.radicalKernAfterDegree + 11.12) < 0.000001)
    #expect(m.radicalDegreeBottomRaisePercent == 0.6)
    #expect(MathFont.metrics(size: 40).fractionRuleThickness == m.fractionRuleThickness * 2)
}

@Test func mathVariantsChooseFontGlyphsBeforeStretching() throws {
    let face = MathFont.font(size: 20)
    var character: UniChar = 0x28
    var glyph: CGGlyph = 0
    #expect(CTFontGetGlyphsForCharacters(face, &character, &glyph, 1))
    let small = try #require(MathFont.verticalVariant(glyph: glyph, minimumHeight: 10, size: 20))
    let tall = try #require(MathFont.verticalVariant(glyph: glyph, minimumHeight: 35, size: 20))
    #expect(small.glyph == glyph)
    #expect(small.advance == 19.94)
    #expect(tall.glyph != glyph)
    #expect(tall.advance == 35.86)
    let largest = try #require(MathFont.verticalVariant(glyph: glyph, minimumHeight: 500, size: 20))
    #expect(largest.advance == 59.82)
    #expect(largest.advance < 500)  // Signals that a glyph assembly is required.
    #expect(MathFont.verticalVariant(glyph: glyph, minimumHeight: .infinity, size: 20) == nil)
}

@Test func malformedMathTablesFailWithoutOutOfBoundsReads() throws {
    let face = MathFont.font(size: 20)
    let original = try #require(CTFontCopyTable(face, CTFontTableTag(0x4D41_5448), []) as Data?)
    for size in [0, 1, 4, 9, 64, 213] {
        #expect(OpenTypeMathTable(data: original.prefix(size)) == nil)
    }
    var badOffset = original
    badOffset[4] = 0xFF
    badOffset[5] = 0xFF
    #expect(OpenTypeMathTable(data: badOffset) == nil)
    // A correct required constants table with a truncated variants table
    // remains usable; its optional glyph query must return no result.
    let constants = Int(original[4]) << 8 | Int(original[5])
    let truncated = try #require(OpenTypeMathTable(data: original.prefix(constants + 214)))
    #expect(truncated.constantInt16(at: 12) == 250)
    #expect(truncated.variants(glyph: 9, vertical: true).isEmpty)
    #expect(truncated.glyphValue(glyph: 9, infoOffset: 0) == nil)
}

@Test func mathScriptsUseOpticalVariantsAtBothLevels() {
    let face = MathFont.font(size: 16)
    var character: UniChar = 0x32
    var glyph: CGGlyph = 0
    #expect(CTFontGetGlyphsForCharacters(face, &character, &glyph, 1))
    #expect(glyph == 19)
    #expect(MathFont.scriptVariant(glyph: glyph, level: 0) == glyph)
    #expect(MathFont.scriptVariant(glyph: glyph, level: 1) == 4902)
    #expect(MathFont.scriptVariant(glyph: glyph, level: 2) == 4495)
    #expect(MathFont.scriptVariant(glyph: glyph, level: 10) == 4495)
    #expect(OpenTypeScriptVariants(data: Data([0, 1])) == nil)
}
