import Foundation

/// Resolved values consumed by the portable paragraph engine. All arithmetic
/// in the engine uses Float, matching the reference core's measured ABI.
public struct ParagraphProfileOptions: Equatable, Sendable {
    public var tolerance: Float = 10
    public var glueStretch: Float = 1
    public var glueShrink: Float = 1
    public var punctuationCompression: Float = 0.5
    public var cjkLatinGap: Float = 0.25
    public var interCJKStretch: Float = 0.05
    public var interCJKShrink: Float = 0.04
    public var interCJKNatural: Float = 0
    public var hangingPunctuation = true
    public var autoRaggedNarrow = true
    public var autoRaggedMeasureEm: Float = 20
    public var raggedCodeFraction: Float = 0.45
    public var raggedStretch: Float = 2
    public var raggedShrink = false
    public var raggedShortLinePenalty: Float = 0
    public var linePenalty: Float = 1
    public var fitnessDemerits: Float = 100
    public var hyphenationLanguage: String = "auto"
    public var hyphenationPenalty: Float = 50
    public var doubleHyphenDemerits: Float = 200_000
    public var finalHyphenDemerits: Float = 0
    public var codeCapsule = false
    public var codeCapsulePad: Float = 0.2

    public init() {}
    public init(values: ProfileValues) {
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
        codeCapsule = values.resolved(.codeCapsule).flag ?? false
        codeCapsulePad = number(.codeCapsulePad)
    }
}
