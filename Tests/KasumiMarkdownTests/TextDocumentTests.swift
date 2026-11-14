import CryptoKit
import Foundation
import Testing
@testable import KasumiMarkdown

private struct TXTSnapshot: Decodable {
    var items: [Item]
    struct Item: Decodable {
        var name: String
        var source: String
        var source_sha256: String
        var mode: TXTParagraphMode
        var chapters: Bool
        var result: Result
    }
    struct Result: Decodable { var blocks: Int; var items: [Block] }
    struct Block: Decodable { var kind: Int; var level: Int; var text: String }
}

@Test func txtParagraphsAndChapterLevelsMatchNativeSnapshot() throws {
    let root = testRepositoryURL
    let snapshot = try JSONDecoder().decode(TXTSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/TXT.core.json")))
    for item in snapshot.items {
        #expect(SHA256.hash(data: Data(item.source.utf8)).map { String(format: "%02x", $0) }.joined() == item.source_sha256)
        let options = PlainTextOptions(paragraphMode: item.mode, detectChapters: item.chapters)
        let document = DocumentParser.parse(item.source, plainText: true, plainTextOptions: options)
        #expect(document.blocks.count == item.result.blocks, "\(item.name) block count")
        for (actual, expected) in zip(document.blocks, item.result.items) {
            #expect(actual.kind == (expected.kind == 1 ? .heading : .paragraph), "\(item.name) kind")
            #expect(actual.level == expected.level, "\(item.name) level")
            #expect(actual.text == expected.text, "\(item.name) text: \(actual.text) vs \(expected.text)")
            #expect(actual.runs.allSatisfy { $0.traits.isEmpty })
        }
    }
}

@Test func txtSourceLinesAndMarkdownOverrideStayExplicit() {
    let input = "\r\nChapter One\r\nfirst\r\nsecond\r\n\r\n  third\r\ncontinued\r\n"
    let parsed = DocumentParser.parse(input, plainText: true, plainTextOptions: .init(paragraphMode: .indent))
    #expect(parsed.blocks.map(\.sourceLines) == [2...2, 3...4, 6...7])
    let markdown = DocumentParser.parse("# Heading\n\n**bold**", plainText: true, plainTextOptions: .init(parseAsMarkdown: true))
    #expect(markdown.headings.first?.text == "Heading")
    #expect(markdown.blocks[1].runs.first?.traits.contains(.strong) == true)
    #expect(PlainTextParser.resolvedParagraphMode(for: "  a.\n  b.\n  c.\nd.\ne.") == .indent)
    #expect(PlainTextParser.resolvedParagraphMode(for: "a.\nb.\nc.") == .line)
    #expect(PlainTextParser.resolvedParagraphMode(for: "a\nb\nc") == .blank)
}

@Test func textDecoderUsesBOMThenUTF8BeforeLegacyGuessing() throws {
    let utf8 = try DocumentDecoder.decode(Data("中文".utf8))
    #expect(utf8.text == "中文" && utf8.encoding == .utf8 && !utf8.isGuessed && !utf8.isLossy)
    let gb = try DocumentDecoder.decode(Data([0xD6, 0xD0, 0xCE, 0xC4]))
    #expect(gb.text == "中文" && gb.encoding == .gb18030 && gb.isGuessed && !gb.isLossy)
    let little = try DocumentDecoder.decode(Data([0xFF, 0xFE, 0x41, 0x00, 0x3D, 0xD8, 0x00, 0xDE]))
    #expect(little.text == "A😀" && little.encoding == .utf16 && little.hadByteOrderMark && !little.isLossy)
    let big = try DocumentDecoder.decode(Data([0xFE, 0xFF, 0x00, 0x41, 0x00, 0x42]))
    #expect(big.text == "AB" && big.encoding == .utf16 && !big.isLossy)
    let withBOM = try DocumentDecoder.decode(Data([0xEF, 0xBB, 0xBF]) + Data("Text".utf8))
    #expect(withBOM.text == "Text" && withBOM.hadByteOrderMark)
    // An even byte count alone is not evidence for UTF-16.
    let noBOM = try DocumentDecoder.decode(Data([0x41, 0, 0x42, 0]))
    #expect(noBOM.encoding == .utf8 && noBOM.text == "A\0B\0")
}

@Test func forcedLegacyDecodingUsesOriginalBytesAndRejectsInvalidInput() throws {
    let cases: [(DocumentTextEncoding, [UInt8], String)] = [
        (.gb18030, [0xD6, 0xD0, 0xCE, 0xC4], "中文"),
        (.big5, [0xA4, 0xA4, 0xA4, 0xE5], "中文"),
        (.shiftJIS, [0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA], "日本語"),
        (.eucKR, [0xC7, 0xD1, 0xB1, 0xB9, 0xBE, 0xEE], "한국어")
    ]
    for (encoding, bytes, expected) in cases {
        let result = try DocumentDecoder.decode(Data(bytes), encoding: encoding)
        #expect(result.text == expected && result.encoding == encoding && !result.isGuessed && !result.isLossy)
    }
    let original = Data([0xD6, 0xD0, 0xCE, 0xC4])
    #expect(try DocumentDecoder.decode(original, encoding: .utf16).text != "中文")
    #expect(try DocumentDecoder.decode(original, encoding: .gb18030).text == "中文")
    #expect(throws: DocumentDecodingError.self) { try DocumentDecoder.decode(original, encoding: .utf8) }
    #expect(try DocumentDecoder.decode(Data([0xFF, 0xFE, 0x41, 0]), encoding: .utf16).text == "A")
}

@Test func lossyDecodingReportsReplacementWithoutFlaggingLiteralReplacementCharacters() throws {
    let lossy = try DocumentDecoder.decode(Data([0xFF]))
    #expect(lossy.text == "�" && lossy.isLossy && lossy.encoding == .utf8)
    let literal = try DocumentDecoder.decode(Data("�".utf8))
    #expect(!literal.isLossy)
    let oddUTF16 = try DocumentDecoder.decode(Data([0xFF, 0xFE, 0x41, 0, 0x42]))
    #expect(oddUTF16.text == "A�" && oddUTF16.isLossy)
}
