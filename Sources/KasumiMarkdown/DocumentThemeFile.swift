import Foundation

public enum DocumentThemeFileError: LocalizedError, Sendable {
    case tooLarge
    case unsupportedVersion(Int)
    case invalidIdentity

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "The theme file exceeds the 4 MiB size limit."
        case .unsupportedVersion(let version): "Unsupported theme file schema version: \(version)."
        case .invalidIdentity: "A theme file must have a nonempty id and name."
        }
    }
}

extension DocumentThemePair {
    /// Load a version-1 JSON light/dark pair. Palette maps are sparse and use
    /// the bundled theme color grammar; document colors inherit Classic at render time.
    public init(json: Data) throws {
        guard json.count <= 4 * 1024 * 1024 else { throw DocumentThemeFileError.tooLarge }
        let file = try JSONDecoder().decode(ThemePairFile.self, from: json)
        guard file.schema_version == 1 else { throw DocumentThemeFileError.unsupportedVersion(file.schema_version) }
        guard !file.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !file.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw DocumentThemeFileError.invalidIdentity }
        self.init(
            id: file.id, name: file.name,
            light: file.light.materialize(id: file.id + "-light", name: file.name + " (Light)", appearance: .light),
            dark: file.dark.materialize(id: file.id + "-dark", name: file.name + " (Dark)", appearance: .dark))
    }

    /// Read a custom theme without registering it globally or changing built-in themes.
    public init(contentsOf url: URL) throws {
        try self.init(json: Data(contentsOf: url, options: .mappedIfSafe))
    }
}

private struct ThemePairFile: Decodable {
    let schema_version: Int
    let id: String
    let name: String
    let light: Palette
    let dark: Palette

    struct Palette: Decodable {
        var document: [String: ThemeColorDefinition] = [:]
        var chrome: [String: ThemeColorDefinition] = [:]
        var syntax: [String: ThemeColorDefinition] = [:]

        private enum CodingKeys: String, CodingKey { case document, chrome, syntax }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            document = try values.decodeIfPresent([String: ThemeColorDefinition].self, forKey: .document) ?? [:]
            chrome = try values.decodeIfPresent([String: ThemeColorDefinition].self, forKey: .chrome) ?? [:]
            syntax = try values.decodeIfPresent([String: ThemeColorDefinition].self, forKey: .syntax) ?? [:]
        }

        func materialize(id: String, name: String, appearance: DocumentTheme.Appearance) -> DocumentTheme {
            DocumentTheme(
                id: id, name: name, appearance: appearance,
                document: document.mapValues { $0.resolve(appearance: appearance) },
                chrome: chrome.mapValues { $0.resolve(appearance: appearance) },
                syntax: syntax.mapValues { $0.resolve(appearance: appearance) })
        }
    }
}

extension DocumentTheme {
    /// Shared by the public render style and CLI file selection.
    var inheritingClassicDocument: DocumentTheme {
        let base = DocumentThemeCatalog.theme(id: "default-" + appearance.rawValue, dark: dark)
        return DocumentTheme(
            id: id, name: name, appearance: appearance,
            document: base.document.merging(document) { _, selected in selected },
            chrome: chrome, syntax: syntax)
    }
}
