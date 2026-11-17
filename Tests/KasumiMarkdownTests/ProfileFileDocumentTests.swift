import Foundation
import Testing
import TOMLDecoder

@testable import KasumiMarkdown

@Test func profileTOMLReadsStandardSyntaxAndIsolatesTables() throws {
    let source = #"""
        base_size = 42
        [meta]
        name = 'A # literal' # comment
        [profile]
        "base_size" = 0x12
        line_spacing = 1_0e-1
        latin_family = """
        A\u0020Font"""
        code_family = 'Literal\Name'
        heading_scale = [
            1, 1.2, 1.3, # comment
        ]
        heading_weight = ['a,b', 'bold']
        hanging_punctuation = false
        [anchor]
        base_size = 24
        [other]
        base_size = 30
        """#
    let document = try ProfileFileDocument(source)
    #expect(document.source == source)
    #expect(document.name == "A # literal")
    let values = document.values()
    #expect(values[.baseSize] == .number(18))
    #expect(values[.lineSpacing] == .number(1))
    #expect(values[.latinFamily] == .string("A Font"))
    #expect(values[.codeFamily] == .string("Literal\\Name"))
    #expect(values[.headingScale] == .numbers([1, 1.2, 1.3]))
    #expect(values[.headingWeight] == .strings(["a,b", "bold"]))
    #expect(values[.hangingPunctuation] == .flag(false))
    #expect(document.values(anchor: true)[.baseSize] == .number(24))
    #expect(try ProfileFileDocument("profile.base_size = 20").values()[.baseSize] == .number(20))
}

@Test func profileTOMLRejectsMalformedSyntaxIncludingUnknownValues() {
    for source in [
        "[broken", "[profile]\nbase_size=18\nbase_size=20", "[profile]\n[profile]",
        "[profile]\nbase_size=01", "unknown=1__0", "unknown=not-a-value",
        "unknown=2025-02-30", "unknown=\"\\q\"", "unknown=[1,,2]", "text that is not TOML",
        "profile=1", "anchor=[]", "meta='name'"
    ] {
        #expect(throws: (any Error).self) { _ = try ProfileFileDocument(source) }
    }
}

@Test func profileTOMLSchemaTypesStaySparseAndNormalizeRanges() throws {
    let source = """
        [profile]
        base_size = 99
        line_spacing = nan
        han_scale = false
        code_capsule = "true"
        body_align = "LEFT"
        heading_scale = [1, "two"]
        heading_weight = []
        hyphenation_language = "fr"
        unknown = 42
        """
    let values = try ProfileFileDocument(source).values()
    #expect(values[.baseSize] == .number(48))
    #expect(values[.hyphenationLanguage] == .string("fr"))
    for field: ProfileField in [.lineSpacing, .hanScale, .codeCapsule, .bodyAlign, .headingScale, .headingWeight] {
        #expect(values[field] == nil)
    }
    #expect(ProfileField.allCases.filter { values[$0] != nil }.count == 2)
}

@Test func profileTOMLEditsRetainUnknownDataAndCanonicalizeAtomically() throws {
    let source = #"""
        # retained until edited
        [meta]
        name = 'Original'
        published = 2026-11-17T01:02:03.123+08:00
        date = 2026-11-17
        time = 01:02:03.123
        local = 2026-11-17T01:02:03
        [profile]
        base_size = 18
        future = { nested = [1, "two", false, { x = "a,b" }] }
        [anchor]
        base_size = 24
        [vendor."a.b"]
        flag = true
        """#
    var document = try ProfileFileDocument(source)
    try document.set(.number(20), for: .baseSize)
    try document.set(nil, for: .baseSize, anchor: true)
    try document.setName("New\n\"\\\t\r\u{0001}")
    let output = try TOMLTable(source: document.source)
    let original = try TOMLTable(source: source)
    #expect(try output.table(forKey: "vendor").table(forKey: "a.b").bool(forKey: "flag"))
    let nested = try output.table(forKey: "profile").table(forKey: "future").array(forKey: "nested")
    #expect(try nested.integer(atIndex: 0) == 1)
    #expect(try nested.string(atIndex: 1) == "two")
    #expect(try nested.bool(atIndex: 2) == false)
    #expect(try nested.table(atIndex: 3).string(forKey: "x") == "a,b")
    for key in ["published", "date", "time", "local"] {
        #expect(try Dictionary(output.table(forKey: "meta"))[key].map { String(describing: $0) }
            == Dictionary(original.table(forKey: "meta"))[key].map { String(describing: $0) })
    }
    #expect(document.values()[.baseSize] == .number(20))
    #expect(document.values(anchor: true)[.baseSize] == nil)
    #expect(document.name == "New\n\"\\\t\r\u{0001}")
    let unchanged = document.source
    #expect(throws: ProfileFileDocument.FileError.self) { try document.setName(String(repeating: "x", count: 4 * 1024 * 1024)) }
    #expect(document.source == unchanged)
    #expect(throws: ProfileFileDocument.FileError.self) { _ = try ProfileFileDocument(String(repeating: "#", count: 4 * 1024 * 1024 + 1)) }
}

@Test func profileTOMLTemplateAndEveryFieldRoundTrip() throws {
    var document = try ProfileFileDocument(ProfileFileDocument.template(name: "Example"))
    for field in ProfileField.allCases { try document.set(field.specification.defaultValue, for: field) }
    let source = document.source
    let reparsed = try ProfileFileDocument(source)
    for field in ProfileField.allCases {
        #expect(reparsed.values()[field] == field.specification.defaultValue)
    }
    #expect(!ProfileFileDocument.template(name: "Example").contains("subscript_shift"))
}
