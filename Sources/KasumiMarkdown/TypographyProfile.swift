import Foundation

enum ProfileValue: Codable, Equatable, Sendable {
    case number(Double)
    case string(String)
    case flag(Bool)
    case numbers([Double])
    case strings([String])
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let v = try? value.decode(Bool.self) {
            self = .flag(v)
        } else if let v = try? value.decode(Double.self) {
            self = .number(v)
        } else if let v = try? value.decode(String.self) {
            self = .string(v)
        } else if let v = try? value.decode([Double].self) {
            self = .numbers(v)
        } else {
            self = .strings(try value.decode([String].self))
        }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .number(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .flag(let v): try value.encode(v)
        case .numbers(let v): try value.encode(v)
        case .strings(let v): try value.encode(v)
        }
    }
    var number: Double? { if case .number(let v) = self { v } else { nil } }
    var string: String? { if case .string(let v) = self { v } else { nil } }
    var flag: Bool? { if case .flag(let v) = self { v } else { nil } }
}

struct ProfileSpecification: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case number, text, flag, choice, numbers, strings }
    let id: String
    let label: String
    let kind: Kind
    let defaultValue: ProfileValue
    let choices: [String]
    let parserRange: [Double]?
    let guiRange: [Double]?
    let step: Double?
    /// Native numeric fields clamp finite input; invalid types/nonfinite input
    /// inherit. Enumerated/array fields are validated independently.
    func normalized(_ value: ProfileValue) -> ProfileValue? {
        switch (kind, value) {
        case (.number, .number(let v)) where v.isFinite:
            if let limits = parserRange { return .number(min(limits[1], max(limits[0], v))) }
            return value
        case (.text, .string), (.flag, .flag): return value
        case (.choice, .string(let v)) where choices.contains(v): return value
        case (.numbers, .numbers(let v)) where !v.isEmpty && v.allSatisfy(\.isFinite): return value
        case (.strings, .strings(let v)) where !v.isEmpty: return value
        default: return nil
        }
    }
}

enum ProfileSchema {
    static let specifications: [ProfileField: ProfileSpecification] = {
        let values = try! JSONDecoder().decode(
            [ProfileSpecification].self,
            from: Data(
                contentsOf: Bundle.module.url(
                    forResource: "ProfileSchema", withExtension: "json", subdirectory: "Bundled")!))
        return Dictionary(
            uniqueKeysWithValues: values.compactMap { value in ProfileField(rawValue: value.id).map { ($0, value) } })
    }()
}

/// Sparse overrides: absence retains inheritance and survives reset/export.
struct ProfileValues: Codable, Equatable, Sendable {
    private var values: [String: ProfileValue]
    init() { values = [:] }
    init(_ values: [ProfileField: ProfileValue]) {
        self.values = Dictionary(
            uniqueKeysWithValues: values.compactMap { key, value in
                key.specification.normalized(value).map { (key.rawValue, $0) }
            })
    }
    init(from decoder: Decoder) throws {
        let source = try decoder.singleValueContainer().decode([String: ProfileValue].self)
        values = [:]
        for (key, value) in source {
            if let field = ProfileField(rawValue: key), let normalized = field.specification.normalized(value) {
                values[key] = normalized
            }
        }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(values)
    }
    subscript(_ field: ProfileField) -> ProfileValue? {
        get { values[field.rawValue] }
        set { values[field.rawValue] = newValue.flatMap { field.specification.normalized($0) } }
    }
    func merging(_ overrides: ProfileValues) -> ProfileValues {
        var result = self
        result.values.merge(overrides.values) { _, new in new }
        return result
    }
    var isEmpty: Bool { values.isEmpty }
    func resolved(_ field: ProfileField) -> ProfileValue { self[field] ?? field.specification.defaultValue }
    static func parse(_ source: String, table: String = "profile") throws -> ProfileValues {
        try ProfileFileDocument(source).values(anchor: table == "anchor")
    }
    func source() throws -> String {
        var document = try ProfileFileDocument("[profile]\n")
        for field in ProfileField.allCases {
            if let value = self[field] { try document.set(value, for: field) }
        }
        return document.source
    }
}

struct TypographyProfile: Codable, Equatable, Identifiable, Sendable {
    enum Origin: String, Codable, Sendable { case builtin, user }
    var id: String
    var name: String
    var origin: Origin
    var factory: ProfileValues
    var delta: ProfileValues
    /// User imports retain comments and unknown keys. Built-in factory values
    /// are immutable; their editable changes live in delta.
    var importedSource: String?
    init(
        id: String, name: String, origin: Origin = .user, factory: ProfileValues = .init(),
        delta: ProfileValues = .init(), importedSource: String? = nil
    ) {
        self.id = id
        self.name = name
        self.origin = origin
        self.factory = factory
        self.delta = delta
        self.importedSource = importedSource
    }
    var effective: ProfileValues { factory.merging(delta) }
    var isModified: Bool { effective != factory }
    mutating func set(_ value: ProfileValue?, for field: ProfileField) throws {
        let normalized = value.flatMap { field.specification.normalized($0) }
        guard delta[field] != normalized else { return }
        if let source = importedSource {
            var document = try ProfileFileDocument(source)
            try document.set(normalized, for: field)
            importedSource = document.source
        }
        delta[field] = normalized
    }
    func exportedSource() throws -> String {
        if let importedSource { return importedSource }
        var copy = self
        try copy.synchronizeSource()
        return copy.importedSource!
    }
}

enum BuiltinProfiles {
    static let all: [TypographyProfile] = {
        struct Entry: Decodable {
            var id: String
            var name: String
            var factory: ProfileValues
        }
        let url = Bundle.module.url(forResource: "BuiltinProfiles", withExtension: "json", subdirectory: "Bundled")!
        return try! JSONDecoder().decode([Entry].self, from: Data(contentsOf: url)).map {
            TypographyProfile(id: $0.id, name: $0.name, origin: .builtin, factory: $0.factory)
        }
    }()
}
