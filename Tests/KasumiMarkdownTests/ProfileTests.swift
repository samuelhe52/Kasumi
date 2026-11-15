import Foundation
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

// Independent authored expectations for the built-in presets and schema.
fileprivate struct ProfileFactoryExpectation {
    let id: String
    let name: String
    let latin: String
    let han: String
    let bodyBaseline: Double
    let headingBaseline: Double
    var extra: [ProfileField: ProfileValue] = [:]
    var values: [ProfileField: ProfileValue] {
        var result: [ProfileField: ProfileValue] = [
            .latinFamily: .string(latin), .hanFamily: .string(han),
            .hanBaseline: .number(bodyBaseline), .headingHanBaseline: .number(headingBaseline),
            .lineSpacing: .number(1.7)
        ]
        result.merge(extra) { _, new in new }
        return result
    }
}
fileprivate let nativeProfileFactories: [ProfileFactoryExpectation] = [
    .init(id: "serif", name: "Serif", latin: "New York", han: "Songti SC", bodyBaseline: 0.04, headingBaseline: 0.06),
    .init(
        id: "serif-pagella", name: "Pagella Serif", latin: "TeX Gyre Pagella", han: "Songti SC", bodyBaseline: 0.04,
        headingBaseline: 0.06, extra: [.latinScale: .number(0.97)]),
    .init(id: "sans", name: "Sans", latin: "SF Pro", han: "PingFang SC", bodyBaseline: 0.02, headingBaseline: 0.04),
    .init(
        id: "serif-charter", name: "Charter Serif", latin: "Charter", han: "Songti SC", bodyBaseline: 0.04,
        headingBaseline: 0.02),
    .init(
        id: "sans-avenir", name: "Avenir Sans", latin: "Avenir Next", han: "PingFang SC", bodyBaseline: 0,
        headingBaseline: 0.02),
    .init(
        id: "serif-tc", name: "Traditional Chinese Serif", latin: "New York", han: "Songti TC", bodyBaseline: 0.04,
        headingBaseline: 0.06),
    .init(
        id: "book", name: "Book", latin: "New York", han: "Songti SC", bodyBaseline: 0.04, headingBaseline: 0.06,
        extra: [.paraSeparation: .string("indent"), .cjkItalicFace: .string("kai"), .hangingPunctuation: .flag(true)])
]

@Test func profileFactoriesPreserveAllSevenNativeSparseBundles() throws {
    #expect(BuiltinProfiles.all.map(\.id) == nativeProfileFactories.map(\.id))
    #expect(ProfileField.allCases.count == 49)
    var explicitValues = 0
    for expected in nativeProfileFactories {
        let profile = try #require(BuiltinProfiles.all.first { $0.id == expected.id })
        #expect(profile.name == expected.name)
        #expect(profile.origin == .builtin)
        #expect(profile.delta.isEmpty)
        for field in ProfileField.allCases {
            #expect(profile.factory[field] == expected.values[field], "\(expected.id).\(field.rawValue)")
            if profile.factory[field] != nil { explicitValues += 1 }
        }
    }
    #expect(explicitValues == 39)
    // Explicit zero must survive, while inherited values remain absent.
    let avenir = try #require(BuiltinProfiles.all.first { $0.id == "sans-avenir" })
    #expect(avenir.factory[.hanBaseline] == .number(0))
    #expect(avenir.factory[.baseSize] == nil)
    #expect(avenir.factory[.codeFamily] == nil)
}

@Test func profileSchemaDefaultsMatchNativeReferenceInsteadOfPresetOverrides() {
    let expected: [ProfileField: ProfileValue] = [
        .baseSize: .number(16), .lineSpacing: .number(1.6),
        .paraSpaceBefore: .number(0), .paraSpaceAfter: .number(0.75),
        .headingSpaceBefore: .number(0.8), .headingSpaceAfter: .number(0.4),
        .headingScale: .numbers([1.6, 1.5, 1.4, 1.3, 1.2, 1.1]),
        .headingWeight: .strings(Array(repeating: "semibold", count: 6)),
        .compactness: .number(0.5), .punctSqueeze: .number(0.5), .cjkLatinGap: .number(0.25),
        .interCjkStretch: .number(0.05), .interCjkShrink: .number(0.04), .interCjkNatural: .number(0),
        .scriptScale: .number(0.699999988079071), .superscriptShift: .number(0.3630000054836273),
        .subscriptShift: .number(0.24699999392032623),
        .hanScale: .number(1), .latinScale: .number(1), .codeScale: .number(1),
        .codeCapsulePad: .number(0.2), .codeCapsule: .flag(false), .tableStyle: .string("booktabs"),
        .raggedCodeFraction: .number(0.45), .hanBaseline: .number(0), .headingHanBaseline: .number(0),
        .latinFamily: .string(""), .hanFamily: .string(""), .codeFamily: .string(""),
        .paraSeparation: .string("space"), .firstLineIndent: .number(0), .paraSpaceBetween: .number(0.75),
        .bodyAlign: .string("justify"), .hangingPunctuation: .flag(true), .autoRaggedNarrow: .flag(true),
        .autoRaggedMeasureEm: .number(20), .punctStrategy: .string("faithful"),
        .cjkItalicFace: .string("kai"), .cjkStrongFace: .string("black"), .cjkPunctFace: .string("simsong"),
        .mathFont: .string("newcm-regular"), .mathRadicalGap: .number(1), .mathFracBarOverhang: .number(0),
        .footnoteMarkSep: .number(0.3), .printBodySize: .number(10.5),
        .markerInset: .number(0.5), .listMarkerGap: .number(8), .listBulletSize: .number(0.3), .quoteBarGap: .number(17)
    ]
    #expect(expected.count == 49)
    #expect(ProfileSchema.specifications.count == 49)
    for (field, value) in expected {
        #expect(ProfileValues().resolved(field) == value, "Native nil fallback for \(field.rawValue)")
    }
}

@Test func profileNumericInputClampsNativeRangesWithoutQuantizingGUISteps() {
    var ranges: [ProfileField: ClosedRange<Double>] = [
        .baseSize: 8...48, .lineSpacing: 1...3, .scriptScale: 0.4...1,
        .hanScale: 0.5...2, .latinScale: 0.5...2, .codeScale: 0.5...2,
        .hanBaseline: -0.2...0.2, .headingHanBaseline: -0.2...0.2,
        .interCjkNatural: 0...0.5, .codeCapsulePad: 0...0.5, .mathFracBarOverhang: 0...0.5,
        .printBodySize: 6...24, .autoRaggedMeasureEm: 4...60, .markerInset: 0...2,
        .listMarkerGap: 0...64, .listBulletSize: 0.1...1, .quoteBarGap: 0...64
    ]
    for field: ProfileField in [
        .paraSpaceBefore, .paraSpaceAfter, .headingSpaceBefore, .headingSpaceAfter, .firstLineIndent, .paraSpaceBetween,
        .mathRadicalGap
    ] { ranges[field] = 0...4 }
    for field: ProfileField in [
        .compactness, .punctSqueeze, .cjkLatinGap, .interCjkStretch, .interCjkShrink, .superscriptShift,
        .subscriptShift, .raggedCodeFraction, .footnoteMarkSep
    ] { ranges[field] = 0...1 }
    #expect(ranges.count == 33)
    for (field, range) in ranges {
        #expect(ProfileValues([field: .number(range.lowerBound - 10)])[field] == .number(range.lowerBound))
        #expect(ProfileValues([field: .number(range.upperBound + 10)])[field] == .number(range.upperBound))
        for invalid in [Double.nan, .infinity, -.infinity] {
            #expect(ProfileValues([field: .number(invalid)])[field] == nil)
        }
        #expect(ProfileValues([field: .flag(true)])[field] == nil)
        #expect(ProfileValues([field: .string("1")])[field] == nil)
    }
    let fractional = ProfileValues([
        .baseSize: .number(17.125), .hanBaseline: .number(0.0137), .autoRaggedMeasureEm: .number(19.25),
        .interCjkNatural: .number(0.4)
    ])
    #expect(fractional[.baseSize] == .number(17.125))
    #expect(fractional[.hanBaseline] == .number(0.0137))
    #expect(fractional[.autoRaggedMeasureEm] == .number(19.25))
    #expect(fractional[.interCjkNatural] == .number(0.4))
    #expect(ProfileField.interCjkNatural.specification.guiRange == [0, 0.2])
}

@Test func profileHeadingArraysRemainSparseInputsUntilNativeStyleResolution() throws {
    let scales: [Double] = [-1, 0, 0.5, 1, 5, 100]
    let values = ProfileValues([
        .headingScale: .numbers(scales),
        .headingWeight: .strings(["regular", "medium", "semibold", "bold", "regular", "bold"])
    ])
    #expect(values[.headingScale] == .numbers(scales))
    #expect(try ProfileValues.parse(values.source()) == values)
    let typography = Typography().applying(values)
    #expect((1...6).map { typography.headingScale($0) } == [0.5, 0.5, 0.5, 1, 4, 4])
    #expect((1...6).map { typography.headingWeight($0) } == [.regular, .medium, .semibold, .bold, .regular, .bold])
    let wrongCount = ProfileValues([.headingScale: .numbers([2, 3]), .headingWeight: .strings(["bold"])])
    #expect(wrongCount[.headingScale] == .numbers([2, 3]))
    #expect((1...6).map { Typography().applying(wrongCount).headingScale($0) } == [1.6, 1.5, 1.4, 1.3, 1.2, 1.1])
    for badName in ["unknown", "Regular", "SEMIBOLD"] {
        let weights = ["regular", "medium", "semibold", "bold", badName, "bold"]
        let stored = ProfileValues([.headingWeight: .strings(weights)])
        #expect(stored[.headingWeight] == .strings(weights))
        #expect((1...6).allSatisfy { Typography().applying(stored).headingWeight($0) == .semibold })
    }
    for invalid: ProfileValue in [.numbers([]), .numbers([1, .nan]), .numbers([.infinity])] {
        #expect(ProfileValues([.headingScale: invalid])[.headingScale] == nil)
    }
    #expect(ProfileValues([.headingWeight: .strings([])])[.headingWeight] == nil)
}

@Test func profileParagraphModeDerivesGeometryAndHonorsExplicitOverrides() throws {
    let book = try #require(BuiltinProfiles.all.first { $0.id == "book" })
    let typography = Typography().applying(book.effective)
    #expect(typography.paragraphIndent && typography.indentFirstParagraph)
    #expect(typography.firstLineIndent == 2)
    #expect(typography.paraSpaceBetween == 0)
    #expect(typography.paraSpaceAfter == 0.75)
    #expect(typography.lineSpacing == 1.7)
    #expect(typography.headingSpaceBefore == 0.8 && typography.headingSpaceAfter == 0.4)
    #expect(typography.codeFamily.isEmpty)
    let explicit = book.effective.merging(
        ProfileValues([.firstLineIndent: .number(0.5), .paraSpaceBetween: .number(0.4)]))
    let overridden = Typography().applying(explicit)
    #expect(overridden.firstLineIndent == 0.5 && overridden.paraSpaceBetween == 0.4)
    #expect(overridden.indentFirstParagraph)
    let spaced = Typography().applying(ProfileValues([.paraSpaceAfter: .number(2), .firstLineIndent: .number(2)]))
    #expect(spaced.paraSpaceBetween == 2)
    #expect(spaced.firstLineIndent == 2)
    #expect(!spaced.indentFirstParagraph)
    let between = Typography().applying(ProfileValues([.paraSpaceAfter: .number(2), .paraSpaceBetween: .number(0.4)]))
    #expect(between.paraSpaceBetween == 0.4)
}

@Test func profileSwitchRestoresInheritedSizeRatherThanLeakingPreviousProfile() throws {
    let serif = try #require(BuiltinProfiles.all.first { $0.id == "serif" })
    var prior = Typography().applying(
        ProfileValues([.baseSize: .number(36), .codeFamily: .string("Menlo"), .bodyAlign: .string("left")]))
    prior.dark = true
    prior.widthLimit = 720
    let switched = prior.applying(serif.effective)
    #expect(switched.size == 16)
    #expect(switched.codeFamily.isEmpty)
    #expect(switched.alignment == .justified)
    #expect(switched.dark && switched.widthLimit == 720)
}

@Test func profileFileUsesNativeTypesAndNonAnchorNamespace() throws {
    let source = """
        [profile]
        base_size = nan
        line_spacing = 8
        han_scale = 0.125
        cjk_latin_gap = true
        code_capsule = true
        table_style = "GRID"
        heading_scale = [1, 2, nan]
        heading_weight = ["bold", "Unrecognized"]
        code_family = 'Custom Mono'
        unknown_key = 99
        [other]
        base_size = 25
        """
    let values = try ProfileValues.parse(source)
    #expect(values[.baseSize] == .number(25))
    #expect(values[.lineSpacing] == .number(3))
    #expect(values[.hanScale] == .number(0.5))
    #expect(values[.cjkLatinGap] == nil)
    #expect(values[.codeCapsule] == .flag(true))
    #expect(values[.tableStyle] == nil)
    #expect(values[.headingScale] == nil)
    #expect(values[.headingWeight] == .strings(["bold", "Unrecognized"]))
    #expect(values[.codeFamily] == nil)  // Native strings require double quotes.
    let normalized = try values.source()
    #expect(try ProfileValues.parse(normalized) == values)
    #expect(!normalized.contains("unknown_key"))
    #expect(!normalized.contains("[other]"))
}

@Test func profileImportAndTargetedEditsPreserveCommentsUnknownKeysAndEnvelope() throws {
    let source = """
        # authored external profile — preserve this header
        [meta] # envelope
        name = "Imported Reader"
        author = 'Authored fixture'
        [anchor]
        base_size = 14
        latin_family = "Charter"
        future_anchor = { enabled = true }
        [profile] # overrides
          base_size   =  999  # reading size
        code_capsule = true
        future_feature = ['one', 'two'] # preserve unknown setting
        [extension.vendor]
        literal = '中文 # not a comment'
        """ + "\n"
    var library = ProfileLibrary()
    let id = try library.importProfile(source, suggestedName: "Wrong fallback")
    #expect(library.selectedID == id)
    #expect(library.selected.name == "Imported Reader")
    #expect(library.selected.origin == .user)
    #expect(library.selected.factory[.baseSize] == .number(14))
    #expect(library.selected.delta[.baseSize] == .number(48))
    #expect(try library.selected.exportedSource() == source)
    try library.set(.number(17.125), for: .baseSize)
    let edited = try library.selected.exportedSource()
    #expect(edited.contains("  base_size = 17.125  # reading size"))
    #expect(edited.contains("future_feature = ['one', 'two'] # preserve unknown setting"))
    #expect(edited.contains("future_anchor = { enabled = true }"))
    #expect(edited.contains("[extension.vendor]\nliteral = '中文 # not a comment'"))
    #expect(edited.hasPrefix("# authored external profile — preserve this header\n[meta] # envelope\n"))
    #expect(try ProfileValues.parse(edited)[.baseSize] == .number(17.125))
    try library.set(nil, for: .baseSize)
    #expect(library.selected.delta[.baseSize] == nil)
    #expect(library.selected.effective[.baseSize] == .number(14))
    let output = try library.selected.exportedSource()
    #expect(try ProfileFileDocument(output).name == "Imported Reader")
    #expect(output.contains("# base_size = 17.125  # reading size"))
    #expect(output.contains("future_feature = ['one', 'two'] # preserve unknown setting"))
}

@Test func profileCloneResetAndAnchorUseSparseSnapshotsWithEmptyDeltas() throws {
    var library = ProfileLibrary()
    try library.set(.number(22), for: .baseSize)
    try library.set(.string("left"), for: .bodyAlign)
    let source = library.selected.effective
    let id = try library.duplicate()
    #expect(id == "serif-copy")
    #expect(library.selectedID == id)
    #expect(library.selected.name == "Serif copy")
    #expect(library.selected.origin == .user)
    #expect(library.selected.factory == source)
    #expect(library.selected.delta.isEmpty)
    #expect(library.selected.factory[.headingScale] == nil)
    #expect(library.selected.factory[.codeFamily] == nil)
    var exported = try ProfileFileDocument(library.selected.exportedSource())
    #expect(exported.name == "Serif copy")
    #expect(try ProfileValues.parse(library.selected.exportedSource(), table: "anchor") == source)
    #expect(try ProfileValues.parse(library.selected.exportedSource()).isEmpty)
    try library.set(.number(24), for: .baseSize)
    try library.reset()
    #expect(library.selected.effective[.baseSize] == .number(22))
    #expect(library.selected.delta.isEmpty)
    try library.set(.number(24), for: .baseSize)
    try library.setAsAnchor()
    #expect(library.selected.factory[.baseSize] == .number(24))
    #expect(library.selected.delta.isEmpty)
    try library.set(.number(30), for: .baseSize)
    try library.reset()
    #expect(library.selected.effective[.baseSize] == .number(24))
    try library.rename("阅读 \"A\"\nSecond line")
    #expect(library.selected.id == id)
    exported = try ProfileFileDocument(library.selected.exportedSource())
    #expect(exported.name == "阅读 \"A\"\nSecond line")
    var imported = ProfileLibrary()
    _ = try imported.importProfile(library.selected.exportedSource(), suggestedName: "Unused")
    #expect(imported.selected.factory == library.selected.factory)
    #expect(imported.selected.delta == library.selected.delta)
    #expect(imported.selected.name == library.selected.name)
}

@Test func profileAddStartsBlankAndReservesExistingFileIDs() throws {
    var library = ProfileLibrary(selectedID: "book")
    try library.set(.number(28), for: .baseSize)
    let id = try library.add(name: "Untitled", reservedIDs: ["untitled", "untitled-2"])
    #expect(id == "untitled-3" && library.selectedID == id)
    #expect(library.selected.origin == .user && library.selected.name == "Untitled")
    #expect(library.selected.factory.isEmpty && library.selected.delta.isEmpty)
    let style = Typography().applying(library.selected.effective)
    #expect(style.size == 16 && style.lineSpacing == 1.6 && style.hanBaseline == 0)
    let source = try library.selected.exportedSource()
    #expect(!source.contains("[anchor]"))
    #expect(source.contains("# base_size = 16") && source.contains("# line_spacing = 1.6"))
    #expect(try ProfileFileDocument(source).name == "Untitled")
    #expect(try ProfileValues.parse(source).isEmpty)
    try library.set(.number(1.7), for: .lineSpacing)
    #expect(library.selected.isModified)
    library.selectedID = "serif"
    try library.set(.number(1.7), for: .lineSpacing)
    #expect(!library.selected.isModified)  // Redundant delta is not a native modification.
}

@Test func profileAnchorResetRenamePreserveUserDocumentExtensions() throws {
    let source =
        "# retained header\n[meta]\nname = 'Marked'\nextra = 'meta' # retained\n[anchor]\nbase_size = 14\nfuture = 'anchor' # retained\n[profile]\nbase_size = 20\nfuture = 'delta' # retained\n[vendor]\nkeep = 'verbatim' # retained\n"
    var library = ProfileLibrary()
    _ = try library.importProfile(source, suggestedName: "Unused")
    try library.setAsAnchor()
    #expect(library.selected.factory[.baseSize] == .number(20))
    #expect(library.selected.delta.isEmpty)
    try library.set(.number(32), for: .baseSize)
    try library.reset()
    try library.rename("Renamed")
    let output = try library.selected.exportedSource()
    #expect(output.hasPrefix("# retained header\n"))
    for line in [
        "extra = 'meta' # retained", "future = 'anchor' # retained", "future = 'delta' # retained",
        "keep = 'verbatim' # retained"
    ] { #expect(output.contains(line)) }
    #expect(try ProfileValues.parse(output, table: "anchor")[.baseSize] == .number(20))
    #expect(try ProfileValues.parse(output)[.baseSize] == nil)
}

@Test func profileReservedIDsRemainUniqueAndBuiltinActionsCannotReplaceFactories() throws {
    var library = ProfileLibrary()
    let original = library.selected
    try library.rename("Renamed builtin")
    try library.setAsAnchor()
    library.removeSelected()
    #expect(library.selected == original)
    try library.set(.number(22), for: .baseSize)
    try library.setAsAnchor()
    #expect(library.selected.factory == original.factory)
    #expect(library.selected.delta[.baseSize] == .number(22))
    try library.reset()
    #expect(library.selected.delta.isEmpty)
    #expect(library.selected.factory == original.factory)
    for (name, expected) in [
        ("Serif", "serif-2"), ("Serif", "serif-3"), ("reference", "reference"), ("default", "default-2"),
        ("???", "profile")
    ] {
        let id = try library.importProfile("[meta]\nname = \"\(name)\"\n[profile]\n", suggestedName: "Unused")
        #expect(id == expected)
    }
    #expect(Set(library.profiles.map(\.id)).count == library.profiles.count)
    library.removeSelected()
    #expect(library.selectedID == "profile")
    #expect(library.missingSelection && library.selected.id == "serif")
    #expect(!library.profiles.contains { $0.id == "profile" })
    let invalidValue = "[profile]\nbase_size = ["
    _ = try library.importProfile(invalidValue, suggestedName: "Broken")
    #expect(library.selected.delta.isEmpty)
    #expect(try library.selected.exportedSource() == invalidValue)
}

@Test func profileLibraryCodableAndFactoryRebasePreserveDeltasWithoutTrustingStoredFactories() throws {
    var stale = try #require(BuiltinProfiles.all.first { $0.id == "serif-pagella" })
    stale.factory[.latinFamily] = .string("Stale shipped font")
    stale.delta[.baseSize] = .number(21)
    let user = TypographyProfile(
        id: "personal", name: "Personal", factory: ProfileValues([.baseSize: .number(14)]),
        delta: ProfileValues([.lineSpacing: .number(2)]),
        importedSource: "# original\n[meta]\nname='Personal'\n[anchor]\nbase_size=14\n[profile]\nline_spacing=2\n")
    var library = ProfileLibrary(profiles: [stale, user], selectedID: "personal")
    library = try JSONDecoder().decode(ProfileLibrary.self, from: JSONEncoder().encode(library))
    #expect(library.selected == user)
    library.rebaseBuiltins()
    #expect(library.profiles.count == 8)
    #expect(library.selectedID == "personal")
    #expect(library.selected == user)
    let pagella = try #require(library.profiles.first { $0.id == "serif-pagella" })
    #expect(pagella.factory[.latinFamily] == .string("TeX Gyre Pagella"))
    #expect(pagella.factory[.latinScale] == .number(0.97))
    #expect(pagella.delta[.baseSize] == .number(21))
}

@Test func profileRebaseDiscardsUserRecordsCollidingWithReservedBuiltinIDs() throws {
    let collision = TypographyProfile(
        id: "serif", name: "User collision", delta: ProfileValues([.baseSize: .number(48)]))
    var library = ProfileLibrary(profiles: [collision] + BuiltinProfiles.all, selectedID: "serif")
    library.rebaseBuiltins()
    #expect(library.profiles.count == 7)
    #expect(library.selected.name == "Serif")
    #expect(library.selected.origin == .builtin)
    #expect(library.selected.delta.isEmpty)
}

@Test func profileDocumentMutationFailuresCannotPartiallyChangeLibraryState() throws {
    // Native profiles ignore this unknown scalar. It must not prevent adding
    // an anchor header or updating the recognized fields/name later.
    let source =
        "anchor = 17 # opaque, not a native profile key\n[meta]\nname = \"Recovery\"\n[profile]\nbase_size = 20\n"
    var library = ProfileLibrary()
    let initial = library
    do { _ = try library.importProfile(source, suggestedName: "Recovery") } catch {
        #expect(library == initial)
        return
    }
    let operations: [(String, (inout ProfileLibrary) throws -> Void)] = [
        ("reset", { try $0.reset() }),
        ("anchor", { try $0.setAsAnchor() }),
        ("rename", { try $0.rename("Changed") })
    ]
    for (name, operation) in operations {
        var edited = library
        do {
            try operation(&edited)
            let exported = try edited.selected.exportedSource()
            #expect(
                try ProfileValues.parse(exported, table: "anchor") == edited.selected.factory,
                "\(name) anchor/model coherence")
            #expect(try ProfileValues.parse(exported) == edited.selected.delta, "\(name) delta/model coherence")
            #expect(try ProfileFileDocument(exported).name == edited.selected.name)
            #expect(exported.contains("anchor = 17 # opaque, not a native profile key"))
        } catch {
            let unchanged = edited == library
            #expect(unchanged, "\(name) must leave the imported profile intact when synchronization fails")
        }
    }
}
