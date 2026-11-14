import CoreGraphics
import CoreText
import Foundation

/// Unmodified bundled math faces, loaded without global font registration or
/// dependence on user-installed fonts. Every access names an immutable face.
public enum MathFont {
    public static var resourceURL: URL { resourceURL(for: .newCMRegular) }

    public static func resourceURL(for face: MathFontChoice) -> URL {
        let name: String
        switch face {
        case .newCMRegular: name = "NewCMMath-Regular"
        case .newCMBook: name = "NewCMMath-Book"
        case .pagellaMath: name = "texgyrepagella-math"
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "otf", subdirectory: "Bundled") else {
            preconditionFailure("Missing bundled math font: \(name)")
        }
        return url
    }

    public static func font(size: CGFloat, face: MathFontChoice = .newCMRegular) -> CTFont {
        precondition(size.isFinite && size > 0, "Math font size must be finite and positive")
        return CTFontCreateWithGraphicsFont(asset(for: face).face, size, nil, nil)
    }

    public static func metrics(size: CGFloat, face: MathFontChoice = .newCMRegular) -> MathMetrics {
        precondition(size.isFinite && size > 0, "Math font size must be finite and positive")
        let asset = asset(for: face)
        return MathMetrics(table: asset.table, scale: size / CGFloat(asset.unitsPerEm))
    }

    /// First ready-made variant meeting the requested height, or the largest
    /// available variant. Compare `advance` with the request before deciding
    /// whether a glyph assembly is needed. Measurements use the supplied size.
    public static func verticalVariant(glyph: CGGlyph, minimumHeight: CGFloat, size: CGFloat, face: MathFontChoice = .newCMRegular) -> MathGlyphVariant? {
        guard minimumHeight.isFinite, size.isFinite, size > 0 else { return nil }
        let asset = asset(for: face), scale = size / CGFloat(asset.unitsPerEm)
        let variants = asset.table.variants(glyph: glyph, vertical: true)
        guard let chosen = variants.first(where: { CGFloat($0.advance) * scale >= minimumHeight }) ?? variants.last else { return nil }
        return MathGlyphVariant(glyph: chosen.glyph, advance: CGFloat(chosen.advance) * scale)
    }

    public static func horizontalVariant(glyph: CGGlyph, minimumWidth: CGFloat, size: CGFloat, face: MathFontChoice = .newCMRegular) -> MathGlyphVariant? {
        guard minimumWidth.isFinite, size.isFinite, size > 0 else { return nil }
        let asset = asset(for: face), scale = size / CGFloat(asset.unitsPerEm)
        let variants = asset.table.variants(glyph: glyph, vertical: false)
        guard let chosen = variants.first(where: { CGFloat($0.advance) * scale >= minimumWidth }) ?? variants.last else { return nil }
        return MathGlyphVariant(glyph: chosen.glyph, advance: CGFloat(chosen.advance) * scale)
    }

    /// Accents use the widest ready-made glyph that fits over their nucleus.
    public static func horizontalVariant(glyph: CGGlyph, maximumWidth: CGFloat, size: CGFloat, face: MathFontChoice = .newCMRegular) -> MathGlyphVariant? {
        guard maximumWidth.isFinite, size.isFinite, size > 0 else { return nil }
        let asset = asset(for: face), scale = size / CGFloat(asset.unitsPerEm)
        let variants = asset.table.variants(glyph: glyph, vertical: false)
        guard let chosen = variants.last(where: { CGFloat($0.advance) * scale <= maximumWidth }) ?? variants.first else { return nil }
        return MathGlyphVariant(glyph: chosen.glyph, advance: CGFloat(chosen.advance) * scale)
    }

    /// Optical script designs are selected separately from reducing font size.
    public static func scriptVariant(glyph: CGGlyph, level: Int, face: MathFontChoice = .newCMRegular) -> CGGlyph {
        asset(for: face).scriptVariants.substitute(glyph: glyph, level: level)
    }

    public static func italicCorrection(glyph: CGGlyph, size: CGFloat, face: MathFontChoice = .newCMRegular) -> CGFloat {
        let asset = asset(for: face)
        return CGFloat(asset.table.glyphValue(glyph: glyph, infoOffset: 0) ?? 0) * size / CGFloat(asset.unitsPerEm)
    }

    public static func topAccentAttachment(glyph: CGGlyph, size: CGFloat, face: MathFontChoice = .newCMRegular) -> CGFloat? {
        let asset = asset(for: face)
        return asset.table.glyphValue(glyph: glyph, infoOffset: 2).map { CGFloat($0) * size / CGFloat(asset.unitsPerEm) }
    }

    // Immutable after construction. Keep each provider and face alive together,
    // and own copies of table bytes independent of Core Text's mapped data.
    private struct FontAsset: @unchecked Sendable {
        let provider: CGDataProvider
        let face: CGFont
        let unitsPerEm: UInt32
        let table: OpenTypeMathTable
        let scriptVariants: OpenTypeScriptVariants

        init(choice: MathFontChoice) {
            guard let provider = CGDataProvider(url: MathFont.resourceURL(for: choice) as CFURL), let face = CGFont(provider) else {
                preconditionFailure("Invalid bundled math font: \(choice.rawValue)")
            }
            let font = CTFontCreateWithGraphicsFont(face, 1000, nil, nil)
            func ownedTable(_ tag: CTFontTableTag) -> Data? {
                guard let raw = CTFontCopyTable(font, tag, []), let bytes = CFDataGetBytePtr(raw) else { return nil }
                return Data(bytes: bytes, count: CFDataGetLength(raw))
            }
            guard let math = ownedTable(CTFontTableTag(0x4D415448)), let table = OpenTypeMathTable(data: math),
                  let gsub = ownedTable(CTFontTableTag(0x47535542)), let scriptVariants = OpenTypeScriptVariants(data: gsub) else {
                preconditionFailure("Invalid bundled math font tables: \(choice.rawValue)")
            }
            self.provider = provider; self.face = face
            self.unitsPerEm = CTFontGetUnitsPerEm(font)
            self.table = table; self.scriptVariants = scriptVariants
        }
    }

    private static let regular = FontAsset(choice: .newCMRegular)
    private static let book = FontAsset(choice: .newCMBook)
    private static let pagella = FontAsset(choice: .pagellaMath)
    private static func asset(for choice: MathFontChoice) -> FontAsset {
        switch choice {
        case .newCMRegular: regular
        case .newCMBook: book
        case .pagellaMath: pagella
        }
    }
}

public struct MathGlyphVariant: Sendable {
    public let glyph: CGGlyph
    /// Font-declared size in the direction of extension, in points.
    public let advance: CGFloat
}

/// OpenType MATH constants scaled from design units to points. Percent fields
/// are ratios (e.g. 0.7), relative to the original text size, not percentages.
/// Device corrections are deliberately ignored to keep screen/PDF geometry
/// independent of raster resolution, as permitted by the OpenType spec.
public struct MathMetrics: Sendable {
    private let table: OpenTypeMathTable
    private let scale: CGFloat

    fileprivate init(table: OpenTypeMathTable, scale: CGFloat) {
        self.table = table
        self.scale = scale
    }

    public var scriptPercentScaleDown: CGFloat { CGFloat(table.constantInt16(at: 0)) / 100 }
    public var scriptScriptPercentScaleDown: CGFloat { CGFloat(table.constantInt16(at: 2)) / 100 }
    public var delimitedSubFormulaMinHeight: CGFloat { CGFloat(table.constantUInt16(at: 4)) * scale }
    public var displayOperatorMinHeight: CGFloat { CGFloat(table.constantUInt16(at: 6)) * scale }
    public var mathLeading: CGFloat { value(at: 8) }
    public var axisHeight: CGFloat { value(at: 12) }
    public var accentBaseHeight: CGFloat { value(at: 16) }
    public var flattenedAccentBaseHeight: CGFloat { value(at: 20) }
    public var subscriptShiftDown: CGFloat { value(at: 24) }
    public var subscriptTopMax: CGFloat { value(at: 28) }
    public var subscriptBaselineDropMin: CGFloat { value(at: 32) }
    public var superscriptShiftUp: CGFloat { value(at: 36) }
    public var superscriptShiftUpCramped: CGFloat { value(at: 40) }
    public var superscriptBottomMin: CGFloat { value(at: 44) }
    public var superscriptBaselineDropMax: CGFloat { value(at: 48) }
    public var subSuperscriptGapMin: CGFloat { value(at: 52) }
    public var superscriptBottomMaxWithSubscript: CGFloat { value(at: 56) }
    public var spaceAfterScript: CGFloat { value(at: 60) }
    public var upperLimitGapMin: CGFloat { value(at: 64) }
    public var upperLimitBaselineRiseMin: CGFloat { value(at: 68) }
    public var lowerLimitGapMin: CGFloat { value(at: 72) }
    public var lowerLimitBaselineDropMin: CGFloat { value(at: 76) }
    public var stackTopShiftUp: CGFloat { value(at: 80) }
    public var stackTopDisplayStyleShiftUp: CGFloat { value(at: 84) }
    public var stackBottomShiftDown: CGFloat { value(at: 88) }
    public var stackBottomDisplayStyleShiftDown: CGFloat { value(at: 92) }
    public var stackGapMin: CGFloat { value(at: 96) }
    public var stackDisplayStyleGapMin: CGFloat { value(at: 100) }
    public var stretchStackTopShiftUp: CGFloat { value(at: 104) }
    public var stretchStackBottomShiftDown: CGFloat { value(at: 108) }
    public var stretchStackGapAboveMin: CGFloat { value(at: 112) }
    public var stretchStackGapBelowMin: CGFloat { value(at: 116) }
    public var fractionNumeratorShiftUp: CGFloat { value(at: 120) }
    public var fractionNumeratorDisplayStyleShiftUp: CGFloat { value(at: 124) }
    public var fractionDenominatorShiftDown: CGFloat { value(at: 128) }
    public var fractionDenominatorDisplayStyleShiftDown: CGFloat { value(at: 132) }
    public var fractionNumeratorGapMin: CGFloat { value(at: 136) }
    public var fractionNumDisplayStyleGapMin: CGFloat { value(at: 140) }
    public var fractionRuleThickness: CGFloat { value(at: 144) }
    public var fractionDenominatorGapMin: CGFloat { value(at: 148) }
    public var fractionDenomDisplayStyleGapMin: CGFloat { value(at: 152) }
    public var skewedFractionHorizontalGap: CGFloat { value(at: 156) }
    public var skewedFractionVerticalGap: CGFloat { value(at: 160) }
    public var overbarVerticalGap: CGFloat { value(at: 164) }
    public var overbarRuleThickness: CGFloat { value(at: 168) }
    public var overbarExtraAscender: CGFloat { value(at: 172) }
    public var underbarVerticalGap: CGFloat { value(at: 176) }
    public var underbarRuleThickness: CGFloat { value(at: 180) }
    public var underbarExtraDescender: CGFloat { value(at: 184) }
    public var radicalVerticalGap: CGFloat { value(at: 188) }
    public var radicalDisplayStyleVerticalGap: CGFloat { value(at: 192) }
    public var radicalRuleThickness: CGFloat { value(at: 196) }
    public var radicalExtraAscender: CGFloat { value(at: 200) }
    public var radicalKernBeforeDegree: CGFloat { value(at: 204) }
    public var radicalKernAfterDegree: CGFloat { value(at: 208) }
    public var radicalDegreeBottomRaisePercent: CGFloat { CGFloat(table.constantInt16(at: 212)) / 100 }

    private func value(at offset: Int) -> CGFloat { CGFloat(table.constantInt16(at: offset)) * scale }
}

/// Bounds-checked, alignment-independent OpenType reader. All offsets are
/// validated before use; malformed optional subtables yield no extra data.
/// Table layouts: https://learn.microsoft.com/en-us/typography/opentype/spec/math
struct OpenTypeMathTable: Sendable {
    private let data: Data
    private let constants: Int

    init?(data: Data) {
        guard Self.u16(data, 0) == 1, Self.u16(data, 2) == 0,
              let constants = Self.u16(data, 4), constants > 0,
              Int(constants) <= data.count - 214 else { return nil }
        self.data = data
        self.constants = Int(constants)
    }

    func constantInt16(at offset: Int) -> Int16 {
        Int16(bitPattern: constantUInt16(at: offset))
    }

    func constantUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset <= 212 else { return 0 }
        return u16(constants + offset) ?? 0
    }

    func variants(glyph: CGGlyph, vertical: Bool) -> [(glyph: CGGlyph, advance: UInt16)] {
        guard let base = offset(at: 8, from: 0),
              let coverage = offset(at: base + (vertical ? 2 : 4), from: base),
              let index = coverageIndex(glyph: glyph, at: coverage),
              let verticalCount = u16(base + 6), let horizontalCount = u16(base + 8),
              index < Int(vertical ? verticalCount : horizontalCount) else { return [] }
        let entry = base + 10 + (vertical ? 0 : Int(verticalCount) * 2) + index * 2
        guard let construction = offset(at: entry, from: base),
              let count = u16(construction + 2),
              hasBytes(at: construction + 4, count: Int(count) * 4) else { return [] }
        var result: [(CGGlyph, UInt16)] = []
        for item in 0..<Int(count) {
            let cursor = construction + 4 + item * 4
            if let variant = u16(cursor), let advance = u16(cursor + 2) {
                result.append((variant, advance))
            }
        }
        // The spec orders variant records by advance; sorting also makes a
        // damaged ordering harmless rather than selecting an undersized glyph.
        return result.sorted { $0.1 < $1.1 }
    }

    func glyphValue(glyph: CGGlyph, infoOffset: Int) -> Int16? {
        guard infoOffset == 0 || infoOffset == 2,
              let info = offset(at: 6, from: 0),
              let values = offset(at: info + infoOffset, from: info),
              let coverage = offset(at: values, from: values),
              let index = coverageIndex(glyph: glyph, at: coverage),
              let count = u16(values + 2), index < Int(count),
              hasBytes(at: values + 4, count: Int(count) * 4),
              let value = u16(values + 4 + index * 4) else { return nil }
        return Int16(bitPattern: value)
    }

    private func coverageIndex(glyph: CGGlyph, at base: Int) -> Int? {
        guard let format = u16(base), let count = u16(base + 2) else { return nil }
        switch format {
        case 1:
            guard hasBytes(at: base + 4, count: Int(count) * 2) else { return nil }
            for index in 0..<Int(count) {
                if u16(base + 4 + index * 2) == glyph { return index }
            }
        case 2:
            guard hasBytes(at: base + 4, count: Int(count) * 6) else { return nil }
            for index in 0..<Int(count) {
                let cursor = base + 4 + index * 6
                guard let first = u16(cursor), let last = u16(cursor + 2),
                      let coverageStart = u16(cursor + 4), first <= last else { return nil }
                if glyph >= first && glyph <= last { return Int(coverageStart) + Int(glyph - first) }
            }
        default: break
        }
        return nil
    }

    private func offset(at address: Int, from base: Int) -> Int? {
        guard let relative = u16(address), relative > 0,
              base >= 0, base <= data.count, Int(relative) <= data.count - base else { return nil }
        let result = base + Int(relative)
        return result < data.count ? result : nil
    }

    private func hasBytes(at offset: Int, count: Int) -> Bool {
        offset >= 0 && count >= 0 && offset <= data.count && count <= data.count - offset
    }

    private func u16(_ offset: Int) -> UInt16? { Self.u16(data, offset) }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count, data.count - offset >= 2 else { return nil }
        return UInt16(data[data.startIndex + offset]) << 8 | UInt16(data[data.startIndex + offset + 1])
    }
}

/// The bundled font uses AlternateSubst (`ssty`) for optical script designs.
/// Read the named feature instead of relying on unstable glyph IDs. Supports
/// both direct alternate lookups and extension lookups of that type.
struct OpenTypeScriptVariants: Sendable {
    private let lookups: [[CGGlyph: [CGGlyph]]]

    func substitute(glyph: CGGlyph, level: Int) -> CGGlyph {
        guard level > 0 else { return glyph }
        var result = glyph
        for lookup in lookups {
            if let alternatives = lookup[result], !alternatives.isEmpty {
                result = alternatives[min(level, alternatives.count) - 1]
            }
        }
        return result
    }

    init?(data: Data) {
        let reader = Reader(data: data)
        guard reader.u16(0) == 1,
              let features = reader.offset16(6, from: 0),
              let featureCount = reader.u16(features),
              reader.contains(features + 2, Int(featureCount) * 6),
              let lookupList = reader.offset16(8, from: 0),
              let lookupCount = reader.u16(lookupList),
              reader.contains(lookupList + 2, Int(lookupCount) * 2) else { return nil }
        var results: [[CGGlyph: [CGGlyph]]] = []
        for featureIndex in 0..<Int(featureCount) {
            let record = features + 2 + featureIndex * 6
            guard reader.u16(record) == 0x7373, reader.u16(record + 2) == 0x7479,
                  let feature = reader.offset16(record + 4, from: features),
                  let count = reader.u16(feature + 2),
                  reader.contains(feature + 4, Int(count) * 2) else { continue }
            for index in 0..<Int(count) {
                guard let lookupIndex = reader.u16(feature + 4 + index * 2), lookupIndex < lookupCount,
                      let lookup = reader.offset16(lookupList + 2 + Int(lookupIndex) * 2, from: lookupList),
                      let type = reader.u16(lookup), let subCount = reader.u16(lookup + 4),
                      reader.contains(lookup + 6, Int(subCount) * 2) else { continue }
                var substitutions: [CGGlyph: [CGGlyph]] = [:]
                for subIndex in 0..<Int(subCount) {
                    guard var subtable = reader.offset16(lookup + 6 + subIndex * 2, from: lookup) else { continue }
                    if type == 7 {
                        guard reader.u16(subtable) == 1, reader.u16(subtable + 2) == 3,
                              let extensionOffset = reader.u32(subtable + 4),
                              Int(extensionOffset) <= data.count - subtable else { continue }
                        subtable += Int(extensionOffset)
                    } else if type != 3 { continue }
                    guard reader.u16(subtable) == 1,
                          let coverage = reader.offset16(subtable + 2, from: subtable),
                          let glyphs = reader.coverage(coverage), let setCount = reader.u16(subtable + 4),
                          glyphs.count == Int(setCount),
                          reader.contains(subtable + 6, Int(setCount) * 2) else { continue }
                    for glyphIndex in glyphs.indices {
                        guard let set = reader.offset16(subtable + 6 + glyphIndex * 2, from: subtable),
                              let alternateCount = reader.u16(set),
                              reader.contains(set + 2, Int(alternateCount) * 2) else { continue }
                        let alternates = (0..<Int(alternateCount)).compactMap { reader.u16(set + 2 + $0 * 2) }
                        if substitutions[glyphs[glyphIndex]] == nil { substitutions[glyphs[glyphIndex]] = alternates }
                    }
                }
                results.append(substitutions)
            }
        }
        lookups = results
    }

    private struct Reader {
        let data: Data
        func contains(_ offset: Int, _ count: Int) -> Bool {
            offset >= 0 && count >= 0 && offset <= data.count && count <= data.count - offset
        }
        func u16(_ offset: Int) -> UInt16? {
            guard contains(offset, 2) else { return nil }
            return UInt16(data[data.startIndex + offset]) << 8 | UInt16(data[data.startIndex + offset + 1])
        }
        func u32(_ offset: Int) -> UInt32? {
            guard let high = u16(offset), let low = u16(offset + 2) else { return nil }
            return UInt32(high) << 16 | UInt32(low)
        }
        func offset16(_ offset: Int, from base: Int) -> Int? {
            guard let relative = u16(offset), relative > 0, base >= 0, base <= data.count,
                  Int(relative) < data.count - base else { return nil }
            return base + Int(relative)
        }
        func coverage(_ base: Int) -> [CGGlyph]? {
            guard let format = u16(base), let count = u16(base + 2) else { return nil }
            if format == 1 {
                guard contains(base + 4, Int(count) * 2) else { return nil }
                return (0..<Int(count)).compactMap { u16(base + 4 + $0 * 2) }
            }
            if format == 2 {
                guard contains(base + 4, Int(count) * 6) else { return nil }
                var result: [CGGlyph] = []
                for index in 0..<Int(count) {
                    let cursor = base + 4 + index * 6
                    guard let start = u16(cursor), let end = u16(cursor + 2), let coverageStart = u16(cursor + 4),
                          start <= end, result.count == Int(coverageStart),
                          result.count + Int(end) - Int(start) + 1 <= 65536 else { return nil }
                    result.append(contentsOf: (Int(start)...Int(end)).map(CGGlyph.init))
                }
                return result
            }
            return nil
        }
    }
}
