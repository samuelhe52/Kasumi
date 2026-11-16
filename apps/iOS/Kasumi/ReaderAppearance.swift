import CoreGraphics
import KasumiMarkdown

/// The reader's typography and theme, resolved from the choices stored in
/// `@AppStorage`. The reading surface and the appearance panel both read it, so
/// they agree on the preset, theme pair, and font size.
struct ReaderAppearance {
    /// Bounds for a manual font size. A stored size of 0 means "use the preset's default".
    static let fontSizes: ClosedRange<Double> = 12...28

    let preset: TypographyPreset
    let pair: DocumentThemePair
    /// The manual size, clamped to `fontSizes`, or nil when the preset default applies.
    private let manualSize: Double?

    init(presetID: String, pairID: String, fontSize: Double) {
        preset = TypographyPreset.builtin.first { $0.id == presetID } ?? .default
        pair =
            DocumentThemePair.builtin.first { $0.id == pairID }
            ?? DocumentThemePair.builtin.first { $0.id == "mono" }!
        manualSize =
            fontSize > 0
            ? min(Self.fontSizes.upperBound, max(Self.fontSizes.lowerBound, fontSize)) : nil
    }

    /// The size in points that the reader renders and the panel shows.
    var fontSize: Double { manualSize ?? Double(preset.defaultFontSize) }

    func theme(dark: Bool) -> DocumentTheme { dark ? pair.dark : pair.light }

    func style(dark: Bool, regular: Bool, preferredOpen: Set<String>) -> RenderStyle {
        var style = RenderStyle(
            preset: preset, theme: theme(dark: dark), fontSize: manualSize.map { CGFloat($0) })
        style.preferredOpenFamilies = preferredOpen
        style.insets.left = regular ? 40 : 20
        style.insets.right = regular ? 40 : 20
        return style
    }
}
