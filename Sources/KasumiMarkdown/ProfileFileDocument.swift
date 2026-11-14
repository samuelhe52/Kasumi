import Foundation

/// The profile format is line oriented. Only exact anchor sections form
/// a separate namespace; every other section contributes profile overrides.
/// This deliberately does not interpret a profile as a strict TOML document.
struct ProfileFileDocument: Sendable {
    enum FileError: LocalizedError { case tooLarge
        var errorDescription: String? { "The preset exceeds the 4 MiB size limit." }
    }
    private(set) var source: String
    init(_ source: String) throws {
        guard source.utf8.count <= 4 * 1024 * 1024 else { throw FileError.tooLarge }
        self.source = source
    }
    private var lines: [String] { source.components(separatedBy: "\n") }
    private static let duplicateMarker = "# ← 这个键被设了不止一次，解析只认最后一条；这条已失效"
    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces) }

    var name: String? {
        for line in lines {
            if let assignment = Self.assignment(line), assignment.key == "name" {
                // Unlike ordinary fields, the native name reader does not strip
                // inline comments and does not continue past an invalid name.
                return Self.quoted(Self.trim(assignment.value))
            }
        }
        return nil
    }
    func values(anchor: Bool = false) -> ProfileValues {
        var result = ProfileValues(), inAnchor = false
        for line in lines {
            if let header = Self.header(line) { inAnchor = header == "anchor" }
            guard inAnchor == anchor, let assignment = Self.assignment(line),
                  let field = ProfileField(rawValue: assignment.key) else { continue }
            let token = Self.trim(Self.beforeComment(assignment.value))
            let value = Self.parse(token, field: field)
            switch field.specification.kind {
            case .number, .numbers, .strings:
                if let value { result[field] = value }
            default: result[field] = value
            }
        }
        return result
    }
    mutating func set(_ value: ProfileValue?, for field: ProfileField, anchor: Bool = false) throws {
        var edited = lines
        var inAnchor = false, matches: [Int] = [], template: Int?
        for (index, line) in edited.enumerated() {
            if let header = Self.header(line) { inAnchor = header == "anchor" }
            guard inAnchor == anchor else { continue }
            if Self.assignment(line)?.key == field.rawValue { matches.append(index) }
            let trimmed = Self.trim(line)
            if template == nil, trimmed.hasPrefix("#"),
               Self.assignment(Self.trim(String(trimmed.dropFirst())))?.key == field.rawValue { template = index }
        }
        let serialized: String?
        switch value {
        case .numbers(let values) where values.isEmpty: serialized = nil
        case .strings(let values) where values.isEmpty: serialized = nil
        default: serialized = value?.profileText
        }
        if let serialized {
            if let last = matches.last {
                for index in matches.dropLast() { edited[index] = "# " + Self.trim(edited[index]) + "  " + Self.duplicateMarker }
                edited[last] = Self.replacement(edited[last], key: field.rawValue, value: serialized)
            } else if let template {
                edited[template] = field.rawValue + " = " + serialized + Self.inlineComment(edited[template])
            } else {
                let target = anchor ? "anchor" : "profile"
                let line = field.rawValue + " = " + serialized
                if let header = edited.firstIndex(where: { Self.header($0) == target }) {
                    edited.insert(line, at: header + 1)
                } else if anchor {
                    let block = ["[anchor]", line, ""]
                    if let profile = edited.firstIndex(where: { Self.header($0) == "profile" }) { edited.insert(contentsOf: block, at: profile) }
                    else {
                        if edited.last?.isEmpty == false { edited.append("") }
                        edited.append(contentsOf: block)
                    }
                } else { edited.append(contentsOf: ["[profile]", line]) }
            }
        } else {
            for index in matches {
                edited[index] = "# " + Self.trim(edited[index]) + (index == matches.last ? "" : "  " + Self.duplicateMarker)
            }
        }
        try commit(edited)
    }
    mutating func setName(_ name: String) throws {
        var edited = lines
        let value = Self.quote(name)
        if let index = edited.firstIndex(where: { Self.assignment($0)?.key == "name" }) {
            edited[index] = Self.replacement(edited[index], key: "name", value: value)
        } else if let index = edited.firstIndex(where: { Self.trim($0) == "[meta]" }) {
            edited.insert("name = " + value, at: index + 1)
        } else { edited.insert(contentsOf: ["[meta]", "name = " + value, ""], at: 0) }
        try commit(edited)
    }
    static func template(name: String) -> String {
        "[meta]\nname = " + quote(name) + "\n\n[profile]\n" + ProfileField.allCases.map { field in
            "# " + field.rawValue + " = " + field.specification.defaultValue.profileText + "  # " + field.specification.label
        }.joined(separator: "\n") + "\n"
    }
    private mutating func commit(_ lines: [String]) throws {
        let result = lines.joined(separator: "\n")
        guard result.utf8.count <= 4 * 1024 * 1024 else { throw FileError.tooLarge }
        source = result
    }
    private static func assignment(_ line: String) -> (key: String, value: String)? {
        let line = trim(line)
        guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { return nil }
        return (trim(String(line[..<equals])), String(line[line.index(after: equals)...]))
    }
    private static func commentIndex(_ text: String) -> String.Index? {
        var quoted = false, escaped = false
        for index in text.indices {
            let character = text[index]
            if quoted && escaped { escaped = false; continue }
            if quoted && character == "\\" { escaped = true; continue }
            if character == "\"" { quoted.toggle() }
            if character == "#" && !quoted { return index }
        }
        return nil
    }
    private static func beforeComment(_ text: String) -> String {
        commentIndex(text).map { String(text[..<$0]) } ?? text
    }
    private static func header(_ line: String) -> String? {
        guard !trim(line).hasPrefix("#") else { return nil }
        let text = trim(beforeComment(line))
        guard text.hasPrefix("["), text.hasSuffix("]") else { return nil }
        return trim(String(text.dropFirst().dropLast()))
    }
    private static func inlineComment(_ line: String) -> String {
        guard let equals = line.firstIndex(of: "=") else { return "" }
        let value = String(line[line.index(after: equals)...])
        guard let index = commentIndex(value) else { return "" }
        return "  " + trim(String(value[index...]))
    }
    private static func replacement(_ line: String, key: String, value: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" }) + key + " = " + value + inlineComment(line)
    }
    private static func quoted(_ token: String) -> String? {
        guard token.count >= 2, token.first == "\"", token.last == "\"" else { return nil }
        var result = "", escaped = false
        for character in token.dropFirst().dropLast() {
            if escaped { result.append(character == "n" ? "\n" : character); escaped = false }
            else if character == "\\" { escaped = true }
            else { result.append(character) }
        }
        return result
    }
    private static func parse(_ token: String, field: ProfileField) -> ProfileValue? {
        switch field.specification.kind {
        case .number:
            return Double(token).flatMap { field.specification.normalized(.number($0)) }
        case .flag:
            return Bool(token).map(ProfileValue.flag)
        case .text, .choice:
            return quoted(token).flatMap { field.specification.normalized(.string($0)) }
        case .numbers, .strings:
            guard token.hasPrefix("["), token.hasSuffix("]") else { return nil }
            let parts = token.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: true).map { trim(String($0)) }
            guard !parts.isEmpty else { return nil }
            if field.specification.kind == .numbers {
                let values = parts.compactMap(Double.init)
                return values.count == parts.count && values.allSatisfy(\.isFinite) ? .numbers(values) : nil
            }
            let values = parts.compactMap(quoted)
            return values.count == parts.count ? .strings(values) : nil
        }
    }
    static func quote(_ value: String) -> String {
        "\"" + value.map { character -> String in
            switch character { case "\\": "\\\\"; case "\"": "\\\""; case "\n": "\\n"; default: String(character) }
        }.joined() + "\""
    }
}

extension ProfileValue {
    var profileText: String {
        func number(_ value: Double) -> String {
            // Native values are bounded except heading arrays. Avoid its Int
            // conversion trap for enormous finite integral array entries.
            if value.isFinite && value.rounded() == value && value >= Double(Int.min) && value < Double(Int.max) { return String(Int(value)) }
            return String(value)
        }
        switch self {
        case .number(let value): return number(value)
        case .string(let value): return ProfileFileDocument.quote(value)
        case .flag(let value): return value ? "true" : "false"
        case .numbers(let values): return "[" + values.map(number).joined(separator: ", ") + "]"
        case .strings(let values): return "[" + values.map(ProfileFileDocument.quote).joined(separator: ", ") + "]"
        }
    }
}
