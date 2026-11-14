import Foundation

public enum ProfileValue: Codable, Equatable, Sendable {
    case number(Double), string(String), flag(Bool), numbers([Double]), strings([String])
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let v = try? value.decode(Bool.self) { self = .flag(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([Double].self) { self = .numbers(v) }
        else { self = .strings(try value.decode([String].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .number(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .flag(let v): try value.encode(v)
        case .numbers(let v): try value.encode(v)
        case .strings(let v): try value.encode(v)
        }
    }
    public var number: Double? { if case .number(let v) = self { v } else { nil } }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var flag: Bool? { if case .flag(let v) = self { v } else { nil } }
}

public struct ProfileSpecification: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case number, text, flag, choice, numbers, strings }
    public let id: String
    public let label: String
    public let kind: Kind
    public let defaultValue: ProfileValue
    public let choices: [String]
    public let parserRange: [Double]?
    public let guiRange: [Double]?
    public let step: Double?
    /// Native numeric fields clamp finite input; invalid types/nonfinite input
    /// inherit. Enumerated/array fields are validated independently.
    public func normalized(_ value: ProfileValue) -> ProfileValue? {
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

public enum ProfileSchema {
    public static let specifications: [ProfileField: ProfileSpecification] = {
        let values = try! JSONDecoder().decode([ProfileSpecification].self, from: Data(contentsOf: Bundle.module.url(forResource: "ProfileSchema", withExtension: "json", subdirectory: "Bundled")!))
        return Dictionary(uniqueKeysWithValues: values.compactMap { value in ProfileField(rawValue: value.id).map { ($0, value) } })
    }()
}

/// Sparse overrides: absence retains inheritance and survives reset/export.
public struct ProfileValues: Codable, Equatable, Sendable {
    private var values: [String: ProfileValue]
    public init() { values = [:] }
    public init(_ values: [ProfileField: ProfileValue]) {
        self.values = Dictionary(uniqueKeysWithValues: values.compactMap { key,value in key.specification.normalized(value).map { (key.rawValue,$0) } })
    }
    public init(from decoder: Decoder) throws {
        let source = try decoder.singleValueContainer().decode([String: ProfileValue].self)
        values = [:]
        for (key,value) in source { if let field = ProfileField(rawValue:key), let normalized = field.specification.normalized(value) { values[key] = normalized } }
    }
    public func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(values) }
    public subscript(_ field: ProfileField) -> ProfileValue? {
        get { values[field.rawValue] }
        set { values[field.rawValue] = newValue.flatMap { field.specification.normalized($0) } }
    }
    public func merging(_ overrides: ProfileValues) -> ProfileValues {
        var result = self; result.values.merge(overrides.values) { _, new in new }; return result
    }
    public var isEmpty: Bool { values.isEmpty }
    public func resolved(_ field: ProfileField) -> ProfileValue { self[field] ?? field.specification.defaultValue }
    public static func parse(_ source: String, table: String = "profile") throws -> ProfileValues {
        try ProfileFileDocument(source).values(anchor: table == "anchor")
    }
    public func source() throws -> String {
        var document = try ProfileFileDocument("[profile]\n")
        for field in ProfileField.allCases {
            if let value = self[field] { try document.set(value, for: field) }
        }
        return document.source
    }
}

public struct TypographyProfile: Codable, Equatable, Identifiable, Sendable {
    public enum Origin: String, Codable, Sendable { case builtin, user }
    public var id: String
    public var name: String
    public var origin: Origin
    public var factory: ProfileValues
    public var delta: ProfileValues
    /// User imports retain comments and unknown keys. Built-in factory values
    /// are immutable; their editable changes live in delta.
    public var importedSource: String?
    public init(id: String, name: String, origin: Origin = .user, factory: ProfileValues = .init(), delta: ProfileValues = .init(), importedSource: String? = nil) {
        self.id=id; self.name=name; self.origin=origin; self.factory=factory; self.delta=delta; self.importedSource=importedSource
    }
    public var effective: ProfileValues { factory.merging(delta) }
    public var isModified: Bool { effective != factory }
    public mutating func set(_ value: ProfileValue?, for field: ProfileField) throws {
        let normalized=value.flatMap { field.specification.normalized($0) }
        guard delta[field] != normalized else { return }
        if let source=importedSource {
            var document=try ProfileFileDocument(source)
            try document.set(normalized, for: field)
            importedSource=document.source
        }
        delta[field]=normalized
    }
    public func exportedSource() throws -> String {
        if let importedSource { return importedSource }
        var copy=self
        try copy.synchronizeSource()
        return copy.importedSource!
    }
}

public enum BuiltinProfiles {
    public static let all: [TypographyProfile] = {
        struct Entry: Decodable { var id:String; var name:String; var factory:ProfileValues }
        let url=Bundle.module.url(forResource:"BuiltinProfiles",withExtension:"json",subdirectory: "Bundled")!
        return try! JSONDecoder().decode([Entry].self,from:Data(contentsOf:url)).map { TypographyProfile(id:$0.id,name:$0.name,origin:.builtin,factory:$0.factory) }
    }()
}
