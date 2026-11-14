import AppKit
import CoreText
import CryptoKit
import Foundation
import Testing
@testable import KasumiMarkdown

private struct MathSnapshot: Decodable {
    var font_sha256: String
    var items: [Item]
    struct Item: Decodable {
        var tex: String
        var display: Bool
        var size: Double
        var result: Result
    }
    struct Result: Decodable {
        var width: Double
        var ascent: Double
        var descent: Double
        var status: Int
        var glyphs: [Glyph]
        var rules: [Rule]
    }
    struct Glyph: Decodable { var glyph: UInt16; var size: Double; var x: Double; var y: Double; var color: UInt32 }
    struct Rule: Decodable { var x: Double; var y: Double; var width: Double; var height: Double; var color: UInt32 }
}

@Test func nativeMathGeometry() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let snapshot = try JSONDecoder().decode(MathSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/Math.core.json")))
    let font = try Data(contentsOf: MathFont.resourceURL)
    #expect(SHA256.hash(data: font).map { String(format: "%02x", $0) }.joined() == snapshot.font_sha256)
    for item in snapshot.items {
        let actual = MathTypesetter.layout(item.tex, size: item.size, display: item.display)
        let label = "\(item.tex), display=\(item.display)"
        #expect(abs(actual.box.width - item.result.width) < 0.0001, "\(label) width")
        #expect(abs(actual.box.ascent - item.result.ascent) < 0.0001, "\(label) ascent")
        #expect(abs(actual.box.descent - item.result.descent) < 0.0001, "\(label) descent")
        #expect(actual.diagnostics.isEmpty == (item.result.status == 0), "\(label) parsing status")
        var glyphs: [MathSnapshot.Glyph] = [], rules: [MathSnapshot.Rule] = []
        func collect(_ drawings: [MathDrawing], color: UInt32 = 0) {
            for drawing in drawings {
                switch drawing {
                case let .glyph(font, g, p): glyphs.append(.init(glyph: g, size: CTFontGetSize(font), x: p.x, y: actual.box.ascent - p.y, color: color))
                case let .rule(r): rules.append(.init(x: r.minX, y: actual.box.ascent - r.maxY, width: r.width, height: r.height, color: color))
                case let .colored(rgba, children): collect(children, color: rgba)
                case .text: Issue.record("Unexpected text paint in native glyph comparison")
                }
            }
        }
        collect(actual.box.drawings)
        #expect(glyphs.count == item.result.glyphs.count, "\(label) glyph count")
        for expected in item.result.glyphs {
            let found = glyphs.firstIndex { $0.glyph == expected.glyph && abs($0.size - expected.size) < 0.0001 && abs($0.x - expected.x) < 0.0001 && abs($0.y - expected.y) < 0.0001 && $0.color == expected.color }
            #expect(found != nil, "\(label) glyph \(expected.glyph) at (\(expected.x), \(expected.y))")
            if let found { glyphs.remove(at: found) }
        }
        #expect(rules.count == item.result.rules.count, "\(label) rule count")
        for expected in item.result.rules {
            let found = rules.firstIndex { abs($0.x - expected.x) < 0.0001 && abs($0.y - expected.y) < 0.0001 && abs($0.width - expected.width) < 0.0001 && abs($0.height - expected.height) < 0.0001 && $0.color == expected.color }
            #expect(found != nil, "\(label) rule at (\(expected.x), \(expected.y))")
            if let found { rules.remove(at: found) }
        }
    }
}

@Test func mathObjectsPreserveCopySearchAndAccessibilityText() {
    let source = "Before $x_i^2 + \\alpha$ after.\n\n$$\n\\frac{1}{3}\n$$\n"
    let document = DocumentParser.parse(source)
    let page = DocumentTypesetter.layout(document, width: 400, style: Typography())
    #expect(page.text.string.contains("\u{FFFC}"))
    #expect(!page.textMap.string.contains("\u{FFFC}"))
    #expect(page.textMap.string == "Before x_i^2 + \\alpha after.\n\n\\frac{1}{3}\n\n")
    #expect(page.textMap.substring(in: NSRange(location: 0, length: page.text.length)) == page.textMap.string)
    let matches = page.textMap.matches("alpha")
    #expect(matches.count == 1)
    #expect(matches.first.map { page.textMap.substring(in: $0) } == "x_i^2 + \\alpha")
    #expect(page.textMap.matches("before").first == NSRange(location: 0, length: 6))
    #expect(page.textMap.matches("alpha after").first?.length == 7)
    let mathLine = page.paragraphs.last?.paragraph.lines.first
    #expect((mathLine?.ascent ?? 0) > 20)
    #expect((mathLine?.descent ?? 0) > 10)
    #expect(page.backgrounds.isEmpty)
}

@Test func mathParsingKeepsGroupsMatricesAndMalformedInputBounded() {
    var parser = MathParser(#"\sqrt[3]{x_i^2}+\frac{a}{b}+\left(\begin{matrix}a&b\\c&d\end{matrix}\right)"#)
    #expect(parser.parse().diagnostics.isEmpty)
    var bad = MathParser(String(repeating: "\\sqrt", count: 1000) + "x")
    #expect(!bad.parse().diagnostics.isEmpty)
    var unknown = MathParser(#"\unknown{x}"#)
    #expect(unknown.parse().diagnostics.contains { $0.contains("Unsupported") })
}

@Test func adjacentEqualObjectsKeepSeparateSemanticCopiesAndOffsets() {
    let object = MathAttachment(source: "x_i", size: 16, display: false).attributed(color: .black)
    let string = NSMutableAttributedString(attributedString: object)
    string.append(object)
    string.append(NSAttributedString(string: " end"))
    let map = DocumentTextMap(string)
    #expect(map.string == "x_ix_i end")
    #expect(map.substring(in: NSRange(location: 0, length: 1)) == "x_i")
    #expect(map.substring(in: NSRange(location: 0, length: 2)) == "x_ix_i")
    #expect(map.matches("x_i") == [NSRange(location: 0, length: 1), NSRange(location: 1, length: 1)])
    #expect(map.semanticOffset(forRenderedOffset: 1) == 3)
    #expect(map.semanticOffset(forRenderedOffset: 3) == 7)
}
