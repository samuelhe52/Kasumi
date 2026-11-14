import Foundation
import Testing
@testable import KasumiMarkdown

// Authored reference expectations, independent of the implementation.
private let profileDuplicateMarker = "# ← 这个键被设了不止一次，解析只认最后一条；这条已失效"

@Test func profileFileNumericDuplicatesRetainEarlierValueOnInvalidLaterToken() throws {
    let source = """
    base_size = 18
    base_size = not-a-number
    line_spacing = 2.25
    line_spacing = inf
    han_baseline = -0.1
    han_baseline = nan
    para_space_before = 0.25
    para_space_before = 999
    """
    let values = try ProfileFileDocument(source).values()
    #expect(values[.baseSize] == .number(18))
    #expect(values[.lineSpacing] == .number(2.25))
    #expect(values[.hanBaseline] == .number(-0.1))
    #expect(values[.paraSpaceBefore] == .number(4))
}

@Test func profileFileInvalidLaterFamilyAssignmentsClearInsteadOfRetaining() throws {
    for field: ProfileField in [.latinFamily, .hanFamily, .codeFamily] {
        let source = "\(field.rawValue) = \"First\"\n\(field.rawValue) = 'single quoted'"
        #expect(try ProfileFileDocument(source).values()[field] == nil)
        let empty = try ProfileFileDocument("\(field.rawValue) = \"\"").values()
        #expect(empty[field] == .string(""))
    }
}

@Test func profileFileUnknownOrMalformedLaterEnumsClearEveryEnumKind() throws {
    let known: [ProfileField: String] = [
        .bodyAlign:"left", .paraSeparation:"indent", .punctStrategy:"spacing",
        .cjkItalicFace:"kai", .cjkStrongFace:"bold", .cjkPunctFace:"native",
        .mathFont:"newcm-regular", .tableStyle:"grid"
    ]
    for (field, value) in known {
        let first = "\(field.rawValue) = \"\(value)\""
        #expect(try ProfileFileDocument(first).values()[field] == .string(value))
        for bad in ["\"unknown\"", "\"\(value.uppercased())\"", value] {
            #expect(try ProfileFileDocument(first + "\n\(field.rawValue) = " + bad).values()[field] == nil)
        }
    }
}

@Test func profileFileBooleansUseTrimmedExactLowercaseTokensAndClearOnInvalid() throws {
    for field: ProfileField in [.hangingPunctuation,.autoRaggedNarrow,.codeCapsule] {
        #expect(try ProfileFileDocument("\(field.rawValue) = \ttrue \t# note").values()[field] == .flag(true))
        #expect(try ProfileFileDocument("\(field.rawValue) = false").values()[field] == .flag(false))
        for bad in ["True", "FALSE", "1", "\"true\"", ""] {
            #expect(try ProfileFileDocument("\(field.rawValue)=true\n\(field.rawValue)=\(bad)").values()[field] == nil)
        }
    }
}

@Test func profileFileNumericLexerFollowsSwiftConversionRatherThanTOMLNumbers() throws {
    for token in ["+16","016","1.6e1","0x10","0x1p4","16."] {
        #expect(try ProfileFileDocument("base_size = \(token)").values()[.baseSize] == .number(16), "\(token)")
    }
    #expect(try ProfileFileDocument("compactness=.5").values()[.compactness] == .number(0.5))
    for token in ["1_6","0o20","0b10000","16px","\"16\"","nan","-inf"] {
        #expect(try ProfileFileDocument("base_size = \(token)").values()[.baseSize] == nil, "\(token)")
    }
}

@Test func profileFileStringLexerDecodesOnlyNativeEscapesAndAcceptsInteriorQuotes() throws {
    let escaped = try ProfileFileDocument(#"latin_family="A\n\t\r\u0041\"\\B""#).values()
    #expect(escaped[.latinFamily] == .string("A\ntru0041\"\\B"))
    #expect(try ProfileFileDocument(#"latin_family="A"B""#).values()[.latinFamily] == .string("A\"B"))
    // The backslash immediately before the closing delimiter is dropped.
    #expect(try ProfileFileDocument(#"latin_family="A\""#).values()[.latinFamily] == .string("A"))
}

@Test func profileFileCommentsProtectDoubleQuotedHashesAndEscapedQuotes() throws {
    let source = #"""
    latin_family = "A#B" # outer comment
    han_family = "A\"#B" # another comment
    code_family = 'A#B'
    base_size = 18 # ignored = 99
    """#
    let values = try ProfileFileDocument(source).values()
    #expect(values[.latinFamily] == .string("A#B"))
    #expect(values[.hanFamily] == .string("A\"#B"))
    #expect(values[.codeFamily] == nil)
    #expect(values[.baseSize] == .number(18))
}

@Test func profileFileArrayLexerOmitsEmptyCommaPiecesButRejectsWhitespacePieces() throws {
    for (token, expected) in [("[1,,2,]",[1.0,2.0]),("[,1]",[1.0]),("[-1, 0, 100]",[-1.0,0.0,100.0])] {
        #expect(try ProfileFileDocument("heading_scale=\(token)").values()[.headingScale] == .numbers(expected))
    }
    for invalid in ["[]","[,]","[1, ,2]","[1,NaN]","[1_0]","[1,\n2]"] {
        #expect(try ProfileFileDocument("heading_scale=[2,3]\nheading_scale=\(invalid)").values()[.headingScale] == .numbers([2,3]), "\(invalid)")
    }
    #expect(try ProfileFileDocument(#"heading_weight=["bold",,"unknown",]"#).values()[.headingWeight] == .strings(["bold","unknown"]))
    #expect(try ProfileFileDocument(#"heading_weight=["bold"]\nheading_weight=["a,b"]"#.replacingOccurrences(of:"\\n",with:"\n")).values()[.headingWeight] == .strings(["bold"]))
}

@Test func profileFileSectionsIsolateOnlyExactAnchorAndFoldOtherKnownKeysIntoDelta() throws {
    let source = """
    base_size=17
    [profile]
    base_size=18
    [anchor] # accepted header comment
    base_size=25
    [unknown]
    base_size=20
    [Anchor]
    line_spacing=2
    ["anchor"]
    han_scale=1.2
    [[anchor]]
    latin_scale=1.1
    [anchor]
    base_size=26
    """
    let document = try ProfileFileDocument(source)
    #expect(document.values()[.baseSize] == .number(20))
    #expect(document.values()[.lineSpacing] == .number(2))
    #expect(document.values()[.hanScale] == .number(1.2))
    #expect(document.values()[.latinScale] == .number(1.1))
    #expect(document.values(anchor:true)[.baseSize] == .number(26))
    #expect(document.values(anchor:true)[.lineSpacing] == nil)
}

@Test func profileFileIgnoresQuotedDottedAndSingleQuotedBareKeys() throws {
    let source = """
    "base_size"=30
    'line_spacing'=2
    profile.base_size=40
    unknown=42
    text that is not TOML
    base_size=18
    """
    let values = try ProfileFileDocument(source).values()
    #expect(values[.baseSize] == .number(18))
    #expect(values[.lineSpacing] == nil)
    #expect(ProfileField.allCases.filter { values[$0] != nil }.count == 1)
}

@Test func profileFileLFSplittingPreservesCRAndDoesNotNormalizeCRLF() throws {
    let source = "[anchor]\r\nbase_size=18\r\nlatin_family=\"X\"\r\nhanging_punctuation=true\r\n"
    let document = try ProfileFileDocument(source)
    #expect(document.source == source)
    #expect(document.values().isEmpty)
    #expect(document.values(anchor:true).isEmpty)
    // CR prevents the first header matching; a following LF-only value is delta.
    let mixed = try ProfileFileDocument("[anchor]\r\nbase_size=18\n")
    #expect(mixed.values()[.baseSize] == .number(18))
    #expect(mixed.values(anchor:true).isEmpty)
    // Comment stripping removes trailing CR together with the comment.
    let commented = try ProfileFileDocument("[anchor] # note\r\nbase_size=18 # note\r\n")
    #expect(commented.values(anchor:true)[.baseSize] == .number(18))
}

@Test func profileFileNameUsesFirstGlobalAssignmentWithoutInlineCommentStripping() throws {
    let source = "[unknown]\nname=\"First\"\n[meta]\nname=\"Later\"\n[anchor]\nname=\"Last\""
    #expect(try ProfileFileDocument(source).name == "First")
    #expect(try ProfileFileDocument("name=invalid\n[meta]\nname=\"Valid later\"").name == nil)
    #expect(try ProfileFileDocument("[meta]\nname=\"A\" # comment").name == nil)
    #expect(try ProfileFileDocument("name=\"A # inner\"").name == "A # inner")
    #expect(try ProfileFileDocument("# name=\"Ignored\"\n\"name\"=\"Ignored\"\nname=\"Found\"").name == "Found")
}

@Test func profileFileWriterCommentsEarlierDuplicatesAndReplacesLastAcrossUnknownSections() throws {
    var document = try ProfileFileDocument("[profile]\n \tbase_size=18 # earlier \t\n[anchor]\nbase_size=25\n[unknown]\n  base_size   = garbage    # last \t\nfuture = { unparsed }")
    try document.set(.number(22), for:.baseSize)
    #expect(document.source == "[profile]\n# base_size=18 # earlier  \(profileDuplicateMarker)\n[anchor]\nbase_size=25\n[unknown]\n  base_size = 22  # last\nfuture = { unparsed }")
    #expect(document.values()[.baseSize] == .number(22))
    #expect(document.values(anchor:true)[.baseSize] == .number(25))
}

@Test func profileFileDeltaClearCommentsAllAssignmentsAndMarksOnlyEarlierOccurrences() throws {
    var document = try ProfileFileDocument("base_size=18\n[anchor]\nbase_size=25\n[unknown]\n \tbase_size = invalid # note \t\n# untouched comment")
    try document.set(nil, for:.baseSize)
    #expect(document.source == "# base_size=18  \(profileDuplicateMarker)\n[anchor]\nbase_size=25\n[unknown]\n# base_size = invalid # note\n# untouched comment")
    #expect(document.values()[.baseSize] == nil)
    #expect(document.values(anchor:true)[.baseSize] == .number(25))
    let previous = document.source
    try document.set(nil, for:.lineSpacing)
    #expect(document.source == previous)
}

@Test func profileFileAnchorWriterUsesSameDuplicateMechanicsWithinAnchorPartition() throws {
    var document = try ProfileFileDocument("[anchor]\nbase_size=20\n[profile]\nbase_size=18\n[anchor]\n\tbase_size=21 # keep")
    try document.set(.number(24), for:.baseSize, anchor:true)
    #expect(document.source == "[anchor]\n# base_size=20  \(profileDuplicateMarker)\n[profile]\nbase_size=18\n[anchor]\n\tbase_size = 24  # keep")
    try document.set(nil, for:.baseSize, anchor:true)
    #expect(document.values(anchor:true)[.baseSize] == nil)
    #expect(document.values()[.baseSize] == .number(18))
    #expect(document.source.hasSuffix("# base_size = 24  # keep"))
}

@Test func profileFileWriterReactivatesFirstCommentedTemplateAndDropsOneHashOnly() throws {
    var document = try ProfileFileDocument("[profile]\n## base_size=99\n  # base_size=16 # first \t\n# base_size=17 # second\n[anchor]\n# base_size=25")
    try document.set(.number(19), for:.baseSize)
    #expect(document.source == "[profile]\n## base_size=99\nbase_size = 19  # first\n# base_size=17 # second\n[anchor]\n# base_size=25")
}

@Test func profileFileWriterInsertsAfterFirstHeaderAndBeforePreviouslyInsertedMissingKeys() throws {
    var document = try ProfileFileDocument("[profile] # first\nunknown=1\n[profile]\nunknown=2")
    try document.set(.number(18), for:.baseSize)
    try document.set(.number(2), for:.lineSpacing)
    #expect(document.source == "[profile] # first\nline_spacing = 2\nbase_size = 18\nunknown=1\n[profile]\nunknown=2")
    var absent = try ProfileFileDocument("future=1")
    try absent.set(.number(18), for:.baseSize)
    #expect(absent.source == "future=1\n[profile]\nbase_size = 18")
}

@Test func profileFileWriterCreatesAnchorBeforeProfileAndOtherwiseAppendsSeparatedBlock() throws {
    var before = try ProfileFileDocument("[meta]\nname=\"A\"\n[profile]\nbase_size=18")
    try before.set(.number(24), for:.baseSize, anchor:true)
    #expect(before.source == "[meta]\nname=\"A\"\n[anchor]\nbase_size = 24\n\n[profile]\nbase_size=18")
    var append = try ProfileFileDocument("future=1")
    try append.set(.number(24), for:.baseSize, anchor:true)
    #expect(append.source == "future=1\n\n[anchor]\nbase_size = 24\n")
}

@Test func profileFileNameWriterChangesFirstGlobalNameAndRetainsLaterNamesAndComments() throws {
    var document = try ProfileFileDocument("[unknown]\n \tname=\"Old\" # note\n[meta]\nname=\"Later\"")
    try document.setName("New")
    #expect(document.source == "[unknown]\n \tname = \"New\"  # note\n[meta]\nname=\"Later\"")
    #expect(document.name == nil) // Native name reader does not strip that comment.
    var absent = try ProfileFileDocument("future=1")
    try absent.setName("Named")
    #expect(absent.source == "[meta]\nname = \"Named\"\n\nfuture=1")
    var header = try ProfileFileDocument("[meta] # not exact for name insertion\nfuture=1")
    try header.setName("Named")
    #expect(header.source.hasPrefix("[meta]\nname = \"Named\"\n\n[meta] # not exact"))
}

@Test func profileFileValueWriterUsesNativeNumberArrayBoolAndStringFormatting() throws {
    var document = try ProfileFileDocument("[profile]\nbase_size=16\nheading_scale=[1]\nheading_weight=[\"bold\"]\ncode_capsule=false\nlatin_family=\"Old\"")
    try document.set(.number(17.5), for:.baseSize)
    try document.set(.numbers([1,1.25,-0.0]), for:.headingScale)
    try document.set(.strings(["regular","unknown"]), for:.headingWeight)
    try document.set(.flag(true), for:.codeCapsule)
    try document.set(.string("A\n\"\\B\t"), for:.latinFamily)
    #expect(document.source == "[profile]\nbase_size = 17.5\nheading_scale = [1, 1.25, 0]\nheading_weight = [\"regular\", \"unknown\"]\ncode_capsule = true\nlatin_family = \"A\\n\\\"\\\\B\t\"")
    try document.set(.numbers([]), for: .headingScale)
    try document.set(.strings([]), for: .headingWeight)
    #expect(document.values()[.headingScale] == nil && document.values()[.headingWeight] == nil)
    #expect(document.source.contains("# heading_scale = [1, 1.25, 0]"))
}

@Test func profileFileAcceptsMalformedAndFutureSyntaxLosslesslyAndEnforcesOnlySizeLimit() throws {
    let source = "[broken\nunknown={future syntax\nbase_size=[\n[unknown]\nline_spacing=2\n"
    let document = try ProfileFileDocument(source)
    #expect(document.source == source)
    #expect(document.values()[.lineSpacing] == .number(2))
    #expect(document.values()[.baseSize] == nil)
    #expect(throws: Never.self) { _ = try ProfileFileDocument(String(repeating:"#",count:4*1024*1024)) }
    #expect(throws: (any Error).self) { _ = try ProfileFileDocument(String(repeating:"#",count:4*1024*1024+1)) }
    var full = try ProfileFileDocument(String(repeating:"#",count:4*1024*1024))
    let original = full.source
    #expect(throws: ProfileFileDocument.FileError.self) { try full.set(.number(18), for:.baseSize) }
    #expect(full.source == original)
    #expect(throws: ProfileFileDocument.FileError.self) { try full.setName("Too large to prepend") }
    #expect(full.source == original)
}
