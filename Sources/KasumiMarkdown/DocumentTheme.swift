#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Foundation

/// A resolved sRGB color. Codable accepts #RRGGBB/#RRGGBBAA or RGBA components.
public struct DocumentColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    public init?(hex: String) {
        guard hex.first == "#" else { return nil }
        let digits = String(hex.dropFirst())
        guard (digits.count == 6 || digits.count == 8),
              digits.allSatisfy({ $0.isASCII && $0.isHexDigit }), let value = UInt32(digits, radix: 16) else { return nil }
        let rgb = digits.count == 8 ? value >> 8 : value
        self.init(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255,
                  alpha: digits.count == 8 ? Double(value & 255) / 255 : 1)
    }

    var nsColor: PlatformColor {
        PlatformColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }

    public init(from decoder: Decoder) throws {
        if let hex = try? decoder.singleValueContainer().decode(String.self) {
            guard let color = Self(hex: hex) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid hexadecimal color"))
            }
            self = color; return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let red = try values.decode(Double.self, forKey: .red)
        let green = try values.decode(Double.self, forKey: .green)
        let blue = try values.decode(Double.self, forKey: .blue)
        let alpha = try values.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        guard [red, green, blue, alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "RGBA components must be finite values from zero to one"))
        }
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

public struct DocumentTheme: Identifiable, Equatable, Sendable {
    public enum Appearance: String, Codable, Sendable { case light, dark }

    public let id: String
    public let name: String
    public let appearance: Appearance
    var dark: Bool { appearance == .dark }
    public let document: [String: DocumentColor]
    public let chrome: [String: DocumentColor]
    public let syntax: [String: DocumentColor]

    public init(id: String, name: String, appearance: Appearance,
                document: [String: DocumentColor], chrome: [String: DocumentColor] = [:],
                syntax: [String: DocumentColor] = [:]) {
        self.id = id; self.name = name; self.appearance = appearance
        self.document = document; self.chrome = chrome; self.syntax = syntax
    }

    func color(_ key: String) -> PlatformColor? {
        (document[key] ?? chrome[key] ?? syntax[key])?.nsColor
    }
}

enum DocumentThemeCatalog {
    /// The bundled themes retain their sparse overrides. Classic entries expose
    /// the Classic base palette, resolving semantic colors for their appearance.
    static var themes: [DocumentTheme] { definitions.map { $0.materialize() } }

    /// An exact ID wins. An unknown ID selects Classic for the requested appearance.
    static func theme(id: String, dark: Bool) -> DocumentTheme {
        (definitions.first { $0.id == id } ?? classic(dark: dark)).materialize()
    }

    /// Overlay semantics: missing keys inherit Classic, including an
    /// omitted inline_code value inheriting Classic textColor rather than theme text.
    static func resolved(id: String, dark: Bool) -> DocumentTheme {
        let selected = theme(id: id, dark: dark)
        let base = classic(dark: selected.dark).materialize()
        return DocumentTheme(id: selected.id, name: selected.name, appearance: selected.appearance,
            document: base.document.merging(selected.document) { _, selected in selected },
            chrome: base.chrome.merging(selected.chrome) { _, selected in selected },
            syntax: base.syntax.merging(selected.syntax) { _, selected in selected })
    }

    static var resourceURL: URL {
        guard let url = Bundle.module.url(forResource: "DocumentThemes", withExtension: "json", subdirectory: "Bundled") else {
            preconditionFailure("Missing bundled document theme catalog")
        }
        return url
    }

    private static func classic(dark: Bool) -> ThemeDefinition {
        definitions.first { $0.id == (dark ? "default-dark" : "default-light") }!
    }

    private static let definitions: [ThemeDefinition] = {
        do {
            let resource = try JSONDecoder().decode(CatalogResource.self, from: Data(contentsOf: resourceURL))
            guard resource.schema_version == 1, Set(resource.themes.map(\.id)).count == resource.themes.count,
                  resource.themes.contains(where: { $0.id == "default-light" }),
                  resource.themes.contains(where: { $0.id == "default-dark" }) else {
                preconditionFailure("Invalid bundled document theme catalog")
            }
            return resource.themes
        } catch { preconditionFailure("Invalid bundled document theme catalog: \(error)") }
    }()
}

private struct CatalogResource: Decodable, Sendable {
    let schema_version: Int
    let themes: [ThemeDefinition]
}

private struct ThemeDefinition: Decodable, Sendable {
    let id: String
    let name: String
    let appearance: DocumentTheme.Appearance
    let document: [String: ThemeColorDefinition]
    let chrome: [String: ThemeColorDefinition]
    let syntax: [String: ThemeColorDefinition]

    func materialize() -> DocumentTheme {
        func colors(_ values: [String: ThemeColorDefinition]) -> [String: DocumentColor] {
            values.mapValues { $0.resolve(appearance: appearance) }
        }
        return DocumentTheme(id: id, name: name, appearance: appearance,
            document: colors(document), chrome: colors(chrome), syntax: colors(syntax))
    }
}

private enum ThemeColorDefinition: Decodable, Sendable {
    case srgb(DocumentColor)
    case genericRGB([Double])
    case system(SystemColor)

    enum SystemColor: String, Decodable, Sendable {
        case textBackgroundColor, textColor, linkColor, secondaryLabelColor, separatorColor

    }
    private enum CodingKeys: String, CodingKey { case rgba, space, system }

    init(from decoder: Decoder) throws {
        if let hex = try? decoder.singleValueContainer().decode(String.self) {
            guard let color = DocumentColor(hex: hex) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid theme color"))
            }
            self = .srgb(color); return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let system = try values.decodeIfPresent(SystemColor.self, forKey: .system) { self = .system(system); return }
        let rgba = try values.decode([Double].self, forKey: .rgba)
        let space = try values.decode(String.self, forKey: .space)
        guard rgba.count == 4, rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              space == "sRGB" || space == "genericRGB" else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid native color components or space"))
        }
        if space == "genericRGB" { self = .genericRGB(rgba) }
        else { self = .srgb(DocumentColor(red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])) }
    }

    func resolve(appearance: DocumentTheme.Appearance) -> DocumentColor {
        switch self {
        case .srgb(let color): return color
        case .genericRGB(let rgba):
            let generic = CGColorSpace(name: "kCGColorSpaceGenericRGB" as CFString)!
            let color = CGColor(colorSpace: generic, components: rgba.map { CGFloat($0) })!
            return PlatformColors.srgb(color)
        case .system(let role): return PlatformColors.srgb(PlatformColors.semantic(role.rawValue, dark: appearance == .dark))
        }
    }
}
