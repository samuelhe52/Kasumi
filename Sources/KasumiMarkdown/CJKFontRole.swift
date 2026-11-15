import CoreText

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Font classification for CJK text. This is distinct from the core's
/// line-breaking classes; font assignment must not use a broad CJK heuristic.
enum CJKFontRole {
    static func usesHanFont(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        return hanRanges.contains { $0.contains(value) }
    }
    private static let hanRanges: [ClosedRange<UInt32>] = [
        0x2e80...0x2fdf, 0x2ff0...0x4dbf, 0x4e00...0x9fff,
        0xac00...0xd7af, 0xf900...0xfaff, 0xfe10...0xfe1f,
        0xfe30...0xfe6f, 0xff00...0xffef, 0x20000...0x3ffff
    ]
    /// FF5E plus the full-width candidates whose recorded punctuation-side
    /// classification is nonzero.
    static let punctuationScalars = Set("、。〈〉《》「」『』【】〔〕〖〗〘〙〚〛〝〞〟！（），．：；？［］｛｝～｟｠".unicodeScalars.map(\.value))

    static func punctuationFont(for character: Character, family: String, hanFont: PlatformFont, enabled: Bool)
        -> PlatformFont?
    {
        guard enabled, family == "Songti SC", let scalar = character.unicodeScalars.first,
            punctuationScalars.contains(scalar.value)
        else { return nil }
        let name: String
        switch hanFont.fontName {
        case "STSongti-SC-Regular": name = "SimSong-Regular"
        case "STSongti-SC-Bold": name = "SimSong-Bold"
        default: return nil
        }
        guard let font = PlatformFonts.named(name, size: hanFont.pointSize), font.fontName == name else { return nil }
        let units = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font as CTFont, units, &glyphs, units.count), glyphs.allSatisfy({ $0 != 0 })
        else { return nil }
        return font
    }
}
