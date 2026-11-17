import Foundation

/// Resolved values consumed by the portable paragraph engine. All arithmetic
/// in the engine uses Float, matching the reference core's measured ABI.
struct ParagraphProfileOptions: Equatable, Sendable {
    var tolerance: Float = 10
    var glueStretch: Float = 1
    var glueShrink: Float = 1
    var punctuationCompression: Float = 0.5
    var cjkLatinGap: Float = 0.25
    var interCJKStretch: Float = 0.05
    var interCJKShrink: Float = 0.04
    var interCJKNatural: Float = 0
    var hangingPunctuation = true
    var autoRaggedNarrow = true
    var autoRaggedMeasureEm: Float = 20
    var raggedCodeFraction: Float = 0.45
    var raggedStretch: Float = 2
    var raggedShrink = false
    var raggedShortLinePenalty: Float = 0
    var linePenalty: Float = 1
    var fitnessDemerits: Float = 100
    var hyphenationLanguage: String = "auto"
    var hyphenationPenalty: Float = 50
    var doubleHyphenDemerits: Float = 200_000
    var finalHyphenDemerits: Float = 0
    var codeCapsule = false
    var codeCapsulePad: Float = 0.2

    init() {}
    init(values: ProfileValues) {
        self.init()
        func number(_ key: ProfileField) -> Float { Float(values.resolved(key).number ?? 0) }
        if let c = values[.compactness]?.number, c != 0.5 {
            tolerance = Float(c <= 0.5 ? 2.5 + 15 * c : 20 * c)
            glueShrink = Float(c <= 0.5 ? 1.1 - 0.2 * c : 1)
        }
        punctuationCompression = number(.punctSqueeze)
        cjkLatinGap = number(.cjkLatinGap)
        interCJKStretch = number(.interCjkStretch)
        interCJKShrink = number(.interCjkShrink)
        interCJKNatural = number(.interCjkNatural)
        hangingPunctuation = values.resolved(.hangingPunctuation).flag ?? true
        autoRaggedNarrow = values.resolved(.autoRaggedNarrow).flag ?? true
        autoRaggedMeasureEm = number(.autoRaggedMeasureEm)
        raggedCodeFraction = number(.raggedCodeFraction)
        hyphenationLanguage = values.resolved(.hyphenationLanguage).string ?? "auto"
        codeCapsule = values.resolved(.codeCapsule).flag ?? false
        codeCapsulePad = number(.codeCapsulePad)
    }
}
