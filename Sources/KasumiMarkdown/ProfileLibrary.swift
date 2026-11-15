import Foundation

struct ProfileLibrary: Codable, Equatable, Sendable {
    private(set) var profiles: [TypographyProfile]
    var selectedID: String
    init(profiles: [TypographyProfile] = BuiltinProfiles.all, selectedID: String = "serif") {
        self.profiles = profiles
        self.selectedID = selectedID
    }
    var selected: TypographyProfile {
        profiles.first(where: { $0.id == selectedID }) ?? profiles.first(where: { $0.id == "serif" })
            ?? BuiltinProfiles.all[0]
    }
    var missingSelection: Bool { !profiles.contains(where: { $0.id == selectedID }) }
    init(files: [String: String], selectedID: String, order: [String]? = nil) throws {
        var profiles = BuiltinProfiles.all
        for id in order ?? Array(files.keys) {
            guard let source = files[id] else { continue }
            let delta = try ProfileValues.parse(source)
            if let index = profiles.firstIndex(where: { $0.id == id }) {
                profiles[index].delta = delta
                profiles[index].importedSource = source
            } else {
                let name = try ProfileFileDocument(source).name ?? id
                let anchor = try ProfileValues.parse(source, table: "anchor")
                profiles.append(
                    TypographyProfile(id: id, name: name, factory: anchor, delta: delta, importedSource: source))
            }
        }
        self.init(profiles: profiles, selectedID: selectedID)
    }
    /// Built-in files contain delta only; user files retain their sparse anchor.
    func fileSources() throws -> [String: String] {
        var result: [String: String] = [:]
        for profile in profiles {
            if let source = try profile.storedSource() { result[profile.id] = source }
        }
        return result
    }
    mutating func rebaseBuiltins() {
        let stored = profiles
        // Drop malformed collisions with a reserved built-in ID.
        let builtins = Set(BuiltinProfiles.all.map(\.id))
        var seen = builtins
        profiles =
            BuiltinProfiles.all.map { factory in
                var value = factory
                value.delta = stored.first(where: { $0.origin == .builtin && $0.id == factory.id })?.delta ?? .init()
                return value
            } + stored.filter { $0.origin == .user && !$0.id.isEmpty && seen.insert($0.id).inserted }
    }
    mutating func set(_ value: ProfileValue?, for field: ProfileField) throws {
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        try profiles[index].set(value, for: field)
    }
    mutating func reset() throws {
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        var profile = profiles[index]
        profile.delta = ProfileValues()
        if profile.origin == .builtin { profile.importedSource = nil } else { try profile.synchronizeSource() }
        profiles[index] = profile
    }
    mutating func setAsAnchor() throws {
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }), profiles[index].origin == .user else {
            return
        }
        var profile = profiles[index]
        profile.factory = profile.effective
        profile.delta = ProfileValues()
        try profile.synchronizeSource()
        profiles[index] = profile
    }
    @discardableResult mutating func duplicate(reservedIDs: Set<String> = []) throws -> String {
        let source = selected
        let name = source.name + " copy"
        let id = uniqueID(name, reservedIDs: reservedIDs)
        var copy = TypographyProfile(id: id, name: name, factory: source.effective)
        try copy.synchronizeSource()
        profiles.append(copy)
        selectedID = id
        return id
    }
    @discardableResult mutating func add(name: String, reservedIDs: Set<String> = []) throws -> String {
        let id = uniqueID(name, reservedIDs: reservedIDs)
        // Native Add starts with a blank optional factory and delta. Duplicate
        // is the separate action that snapshots the current profile.
        var profile = TypographyProfile(id: id, name: name)
        try profile.synchronizeSource()
        profiles.append(profile)
        selectedID = id
        return id
    }
    @discardableResult mutating func importProfile(
        _ source: String, suggestedName: String, reservedIDs: Set<String> = []
    ) throws -> String {
        let document = try ProfileFileDocument(source)
        let name = document.name ?? suggestedName
        let id = uniqueID(name, reservedIDs: reservedIDs)
        let anchor = try ProfileValues.parse(source, table: "anchor")
        let delta = try ProfileValues.parse(source)
        profiles.append(
            TypographyProfile(
                id: id, name: name.isEmpty ? suggestedName : name, factory: anchor, delta: delta, importedSource: source
            ))
        selectedID = id
        return id
    }
    mutating func rename(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let i = profiles.firstIndex(where: { $0.id == selectedID }), profiles[i].origin == .user
        else { return }
        var profile = profiles[i]
        profile.name = name
        try profile.synchronizeSource(writeName: true)
        profiles[i] = profile
    }
    mutating func removeSelected() {
        guard selected.origin == .user else { return }
        profiles.removeAll { $0.id == selectedID }
    }
    private func uniqueID(_ name: String, reservedIDs: Set<String> = []) -> String {
        let slug = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            .joined(separator: "-")
        let base = slug.isEmpty ? "profile" : slug
        var candidate = base
        var index = 2
        while profiles.contains(where: { $0.id == candidate }) || reservedIDs.contains(candidate)
            || candidate == "default"
        {
            candidate = base + "-\(index)"
            index += 1
        }
        return candidate
    }
}

extension TypographyProfile {
    func storedSource() throws -> String? {
        if origin == .builtin {
            if let importedSource { return importedSource }
            guard !delta.isEmpty else { return nil }
            var document = try ProfileFileDocument(ProfileFileDocument.template(name: name))
            for field in ProfileField.allCases { if let value = delta[field] { try document.set(value, for: field) } }
            return document.source
        }
        return try exportedSource()
    }
    func editableSource() throws -> String {
        if let source = try storedSource() { return source }
        return ProfileFileDocument.template(name: name)
    }
    mutating func synchronizeSource(writeName: Bool = false) throws {
        let existing = importedSource
        var document = try ProfileFileDocument(existing ?? ProfileFileDocument.template(name: name))
        if writeName { try document.setName(name) }
        let oldFactory = document.values(anchor: true)
        let oldDelta = document.values()
        for field in ProfileField.allCases {
            if oldFactory[field] != factory[field] { try document.set(factory[field], for: field, anchor: true) }
            if oldDelta[field] != delta[field] { try document.set(delta[field], for: field) }
        }
        importedSource = document.source
    }
}
