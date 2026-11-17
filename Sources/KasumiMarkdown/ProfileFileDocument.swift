import Foundation
import TOMLDecoder

/// A standard TOML document. Typography, anchors and metadata have distinct tables.
/// Imports retain their original source until edited; edits emit canonical TOML.
struct ProfileFileDocument: Sendable {
    enum FileError: LocalizedError {
        case tooLarge, invalidTable(String), unsupportedValue
        var errorDescription: String? {
            switch self {
            case .tooLarge: "The preset exceeds the 4 MiB size limit."
            case .invalidTable(let key): "The preset's \(key) value must be a TOML table."
            case .unsupportedValue: "The preset contains an unsupported TOML value."
            }
        }
    }
    private(set) var source: String
    private var root: TOMLTable

    init(_ source: String) throws {
        guard source.utf8.count <= 4 * 1024 * 1024 else { throw FileError.tooLarge }
        let root = try TOMLTable(source: source)
        // The parser validates leaf values lazily. Validate the entire document,
        // including unknown keys, before accepting it as standard TOML.
        _ = try Dictionary(root)
        for key in ["meta", "profile", "anchor"] where root.contains(key: key) {
            guard (try? root.table(forKey: key)) != nil else { throw FileError.invalidTable(key) }
        }
        self.source = source
        self.root = root
    }

    var name: String? { (try? root.table(forKey: "meta")).flatMap { try? $0.string(forKey: "name") } }

    func values(anchor: Bool = false) -> ProfileValues {
        guard let table = try? root.table(forKey: anchor ? "anchor" : "profile") else { return ProfileValues() }
        var result = ProfileValues()
        for field in ProfileField.allCases {
            let key = field.rawValue
            let value: ProfileValue?
            switch field.specification.kind {
            case .number:
                let number = (try? table.float(forKey: key)) ?? (try? table.integer(forKey: key)).map(Double.init)
                value = number.map(ProfileValue.number)
            case .text, .choice: value = (try? table.string(forKey: key)).map(ProfileValue.string)
            case .flag: value = (try? table.bool(forKey: key)).map(ProfileValue.flag)
            case .numbers:
                if let array = try? table.array(forKey: key) {
                    let numbers = (0..<array.count).compactMap { index in
                        (try? array.float(atIndex: index)) ?? (try? array.integer(atIndex: index)).map(Double.init)
                    }
                    value = numbers.count == array.count ? .numbers(numbers) : nil
                } else { value = nil }
            case .strings:
                if let array = try? table.array(forKey: key) {
                    let strings = (0..<array.count).compactMap { try? array.string(atIndex: $0) }
                    value = strings.count == array.count ? .strings(strings) : nil
                } else { value = nil }
            }
            result[field] = value
        }
        return result
    }

    mutating func set(_ value: ProfileValue?, for field: ProfileField, anchor: Bool = false) throws {
        var dictionary = try Dictionary(root)
        let key = anchor ? "anchor" : "profile"
        var table = dictionary[key] as? [String: Any] ?? [:]
        table[field.rawValue] = value.flatMap { field.specification.normalized($0) }?.tomlValue
        dictionary[key] = table
        try commit(dictionary)
    }

    mutating func setName(_ name: String) throws {
        var dictionary = try Dictionary(root)
        var meta = dictionary["meta"] as? [String: Any] ?? [:]
        meta["name"] = name
        dictionary["meta"] = meta
        try commit(dictionary)
    }

    private mutating func commit(_ dictionary: [String: Any]) throws {
        var lines: [String] = []
        for key in dictionary.keys.sorted() where !(dictionary[key] is [String: Any]) {
            lines.append(try Self.key(key) + " = " + Self.serialize(dictionary[key]!))
        }
        for key in dictionary.keys.sorted() {
            guard let table = dictionary[key] as? [String: Any] else { continue }
            if !lines.isEmpty { lines.append("") }
            lines.append("[" + Self.key(key) + "]")
            for field in table.keys.sorted() {
                lines.append(try Self.key(field) + " = " + Self.serialize(table[field]!))
            }
        }
        // Reparse before publishing either source or model; failed writes are atomic.
        self = try ProfileFileDocument(lines.joined(separator: "\n") + "\n")
    }

    private static func key(_ value: String) -> String {
        !value.isEmpty && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45 }
            ? value : quote(value)
    }

    private static func serialize(_ value: Any) throws -> String {
        switch value {
        case let value as String: return quote(value)
        case let value as Bool: return value ? "true" : "false"
        case let value as Int64: return String(value)
        case let value as Double:
            if value.isNaN { return "nan" }
            if value == .infinity { return "inf" }
            if value == -.infinity { return "-inf" }
            return String(value)
        case let value as OffsetDateTime: return value.description
        case let value as LocalDateTime: return value.description
        case let value as LocalDate: return value.description
        case let value as LocalTime: return value.description
        case let value as [Any]: return try "[" + value.map(serialize).joined(separator: ", ") + "]"
        case let value as [String: Any]:
            return try "{ " + value.keys.sorted().map { try key($0) + " = " + serialize(value[$0]!) }.joined(separator: ", ") + " }"
        default: throw FileError.unsupportedValue
        }
    }

    static func template(name: String) -> String {
        "[meta]\nname = " + quote(name) + "\n\n[profile]\n"
            + ProfileField.allCases.map { field in
                "# " + field.rawValue + " = " + field.specification.defaultValue.profileText + "  # "
                    + field.specification.label
            }.joined(separator: "\n") + "\n"
    }

    static func quote(_ value: String) -> String {
        "\"" + value.unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 0x22: "\\\""
            case 0x5C: "\\\\"
            case 0x0A: "\\n"
            case 0x0D: "\\r"
            case 0x09: "\\t"
            case 0...0x1F, 0x7F: String(format: "\\u%04X", scalar.value)
            default: String(scalar)
            }
        }.joined() + "\""
    }
}

extension ProfileValue {
    fileprivate var tomlValue: Any {
        switch self {
        case .number(let value): value
        case .string(let value): value
        case .flag(let value): value
        case .numbers(let values): values
        case .strings(let values): values
        }
    }

    var profileText: String {
        switch self {
        case .number(let value): return String(value)
        case .string(let value): return ProfileFileDocument.quote(value)
        case .flag(let value): return value ? "true" : "false"
        case .numbers(let values): return "[" + values.map { String($0) }.joined(separator: ", ") + "]"
        case .strings(let values): return "[" + values.map(ProfileFileDocument.quote).joined(separator: ", ") + "]"
        }
    }
}
