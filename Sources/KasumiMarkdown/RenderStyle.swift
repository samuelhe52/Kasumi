import CoreGraphics
import Foundation

/// A complete preset. The editor's sparse values and inheritance remain internal.
public struct TypographyPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var defaultFontSize: CGFloat { values.resolved(.baseSize).number! }
    let values: ProfileValues

    public static let builtin: [TypographyPreset] = BuiltinProfiles.all.map {
        TypographyPreset(id: $0.id, name: $0.name, values: $0.effective)
    }
    public static let `default` = builtin[0]

    public init(id: String, name: String, toml: String) throws {
        self.id = id
        self.name = name
        values = try ProfileValues.parse(toml)
    }

    private init(id: String, name: String, values: ProfileValues) {
        self.id = id
        self.name = name
        self.values = values
    }
}

extension DocumentTheme {
    public static let builtin: [DocumentTheme] = DocumentThemeCatalog.themes
    public static let `default` = builtin.first { $0.id == "mono-light" }!
}

/// A caller-selected theme and typography; contains no application or UI state.
public struct RenderStyle: Sendable, Equatable {
    public var preset: TypographyPreset
    public var theme: DocumentTheme
    /// Nil uses the preset's reading size. PDF retains the preset's printed size.
    public var fontSize: CGFloat?
    /// Nil allows the full available width after insets.
    public var widthLimit: CGFloat?
    public var insets: DocumentInsets
    public var codeBlockStyle: CodeBlockStyle
    /// Open families to use ahead of the Apple faces they replace, when the
    /// client has registered them: "Noto Serif SC" (Songti SC), "Noto Serif TC"
    /// (Songti TC) and "LXGW WenKai Lite" (Kaiti SC emphasis). Empty uses Apple's
    /// faces whenever they're available. The library never downloads either.
    public var preferredOpenFamilies: Set<String> = []

    public init(
        preset: TypographyPreset = .default, theme: DocumentTheme = .default,
        fontSize: CGFloat? = nil, widthLimit: CGFloat? = 960, insets: DocumentInsets = .reader,
        codeBlockStyle: CodeBlockStyle = .init()
    ) {
        self.preset = preset
        self.theme = theme
        self.fontSize = fontSize
        self.widthLimit = widthLimit
        self.insets = insets
        self.codeBlockStyle = codeBlockStyle
    }

    var typography: Typography {
        var result = Typography().applying(preset.values)
        result.codeBlockStyle = codeBlockStyle
        let appearance = theme.appearance
        result.dark = appearance == .dark
        let base = DocumentThemeCatalog.theme(id: "default-" + appearance.rawValue, dark: result.dark)
        // Sparse themes inherit Classic from the selected theme's appearance.
        result.explicitTheme = DocumentTheme(
            id: theme.id, name: theme.name, appearance: appearance,
            document: base.document.merging(theme.document) { _, selected in selected },
            chrome: theme.chrome, syntax: theme.syntax)
        if let fontSize, fontSize.isFinite, fontSize > 0 { result.size = fontSize }
        result.limitWidth = widthLimit != nil
        if let widthLimit { result.widthLimit = widthLimit.isFinite ? max(1, widthLimit) : 960 }
        result.latinFamily = FontFamilyResolver.resolve(result.latinFamily, role: .latin)
        result.hanFamily = FontFamilyResolver.resolve(result.hanFamily, role: .han, preferring: preferredOpenFamilies)
        result.preferOpenKai = preferredOpenFamilies.contains("LXGW WenKai Lite")
        result.codeFamily = FontFamilyResolver.resolve(result.codeFamily, role: .code)
        return result
    }
}

public enum FontAvailability {
    /// Requested families that are absent, even when a fallback can render them.
    /// This query never starts a font download.
    public static func missingFamilies(for style: RenderStyle) -> [String] {
        let values = style.preset.values
        let latin = values[.latinFamily]?.string ?? ""
        let han = values[.hanFamily]?.string ?? ""
        let families = [
            latin.isEmpty ? "New York" : latin,
            han.isEmpty ? "Songti SC" : han,
            values[.codeFamily]?.string ?? ""
        ]
        var seen = Set<String>()
        var missing: [String] = []
        for name in families where !name.isEmpty && seen.insert(name).inserted {
            if !FontFamilyResolver.isAvailable(name) { missing.append(name) }
        }
        return missing
    }
}
