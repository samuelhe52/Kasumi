import Foundation

/// A caller-selectable light/dark palette pair; appearance selection stays in the client.
public struct DocumentThemePair: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let light: DocumentTheme
    public let dark: DocumentTheme

    public static let builtin: [DocumentThemePair] = {
        let themes = DocumentTheme.builtin
        return themes.filter { $0.appearance == .light }.compactMap { light in
            let id = String(light.id.dropLast("-light".count))
            guard light.id.hasSuffix("-light"), let dark = themes.first(where: { $0.id == id + "-dark" }) else { return nil }
            var name = light.name
            for suffix in [" (Light)", " Light"] where name.hasSuffix(suffix) { name.removeLast(suffix.count) }
            return DocumentThemePair(id: id, name: name, light: light, dark: dark)
        }
    }()
}
