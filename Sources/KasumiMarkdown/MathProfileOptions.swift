import Foundation

enum MathFontChoice: String, CaseIterable, Codable, Sendable {
    case newCMRegular = "newcm-regular"
    case newCMBook = "newcm-book"
    case pagellaMath = "pagella-math"
}

/// Profile values are captured per formula, never selected through global
/// mutable state. Defaults and rejected-value behavior match the recorded reference cases.
struct MathProfileOptions: Equatable, Sendable {
    let font: MathFontChoice
    /// Multiplier of the font's inline and display radical clearance constants.
    let radicalGap: CGFloat
    /// Em extension at each end of a fraction rule; it does not change advance.
    let fractionBarOverhang: CGFloat

    init(font: MathFontChoice = .newCMRegular, radicalGap: CGFloat = 1, fractionBarOverhang: CGFloat = 0) {
        self.font = font
        self.radicalGap = radicalGap.isFinite && (0...4).contains(radicalGap) ? radicalGap : 1
        self.fractionBarOverhang =
            fractionBarOverhang.isFinite && (0...0.5).contains(fractionBarOverhang) ? fractionBarOverhang : 0
    }

    init(fontName: String, radicalGap: CGFloat = 1, fractionBarOverhang: CGFloat = 0) {
        self.init(
            font: MathFontChoice(rawValue: fontName) ?? .newCMRegular, radicalGap: radicalGap,
            fractionBarOverhang: fractionBarOverhang)
    }
}
