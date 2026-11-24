import CoreGraphics
import Foundation
import KasumiMarkdown

struct ReaderPresetSpacing: RawRepresentable {
    private var edits: [String: TypographySpacing] = [:]

    init() {}

    init?(rawValue: String) {
        guard let edits = try? JSONDecoder().decode([String: TypographySpacing].self, from: Data(rawValue.utf8))
        else { return nil }
        self.edits = edits
    }

    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(edits) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    subscript(preset: TypographyPreset) -> TypographySpacing? {
        get {
            guard let saved = edits[preset.id] else { return nil }
            let spacing = preset.applyingSpacing(saved).spacing
            return spacing == preset.spacing ? nil : spacing
        }
        set {
            let spacing = newValue.map { preset.applyingSpacing($0).spacing }
            edits[preset.id] = spacing == preset.spacing ? nil : spacing
        }
    }
}

/// The reader's typography and theme, resolved from the choices stored in
/// `@AppStorage`. The reading surface and the appearance panel both read it, so
/// they agree on the preset, theme pair, and font size.
struct ReaderAppearance {
    static let fontSizes: ClosedRange<Double> = 12...28
    static let defaultFontSize = 16.0

    let preset: TypographyPreset
    let pair: DocumentThemePair
    let fontSize: Double

    init(presetID: String, pairID: String, fontSize: Double) {
        preset = TypographyPreset.builtin.first { $0.id == presetID } ?? .default
        pair =
            DocumentThemePair.builtin.first { $0.id == pairID }
            ?? DocumentThemePair.builtin.first { $0.id == "mono" }!
        // Existing installations used zero for the preset's size. The reader
        // now gives that value its own default, regardless of the preset.
        self.fontSize =
            fontSize.isFinite && fontSize > 0
            ? min(Self.fontSizes.upperBound, max(Self.fontSizes.lowerBound, fontSize))
            : Self.defaultFontSize
    }

    func theme(dark: Bool) -> DocumentTheme { dark ? pair.dark : pair.light }

    func style(dark: Bool, regular: Bool, preferredOpen: Set<String>, spacing: TypographySpacing?) -> RenderStyle {
        let effectivePreset = spacing.map(preset.applyingSpacing) ?? preset
        var style = RenderStyle(
            preset: effectivePreset, theme: theme(dark: dark), fontSize: fontSize)
        style.codeBlockStyle = ReaderCodeBlockStyle.reading
        style.preferredOpenFamilies = preferredOpen
        style.insets.left = regular ? 40 : 20
        style.insets.right = regular ? 40 : 20
        return style
    }
}
