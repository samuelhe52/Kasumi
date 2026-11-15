import Foundation
import Testing

@testable import KasumiMarkdown

fileprivate let readingFixtureDirectory = testRepositoryURL.appendingPathComponent("fixtures")

fileprivate func readingLayout(_ source: String, width: CGFloat = 360, size: Double = 16) -> DocumentLayout {
    var style = Typography()
    style.size = size
    return DocumentTypesetter.layout(
        DocumentParser.parse(source, baseURL: readingFixtureDirectory), width: width, style: style)
}

fileprivate func readingY(_ item: PlacedText, line: Int, fraction: CGFloat = 0.35) -> CGFloat {
    let shaped = item.paragraph.lines[line]
    return item.origin.y + shaped.origin.y - shaped.ascent + fraction * max(1, shaped.ascent + shaped.descent)
}

fileprivate func expectedReadingY(_ item: PlacedText, anchor: ReadingAnchor) throws -> CGFloat {
    let map = DocumentTextMap(item.paragraph.attributed)
    let rendered = try #require(map.renderedRange(for: NSRange(location: anchor.offset, length: 1)))
    let index = try #require(item.paragraph.lines.firstIndex { NSLocationInRange(rendered.location, $0.range) })
    return readingY(item, line: index, fraction: anchor.verticalFraction)
}

@Test func readingAnchorSurvivesWidthAndFontChangesWithoutStoringText() throws {
    let paragraph =
        "Astronomy paragraph: "
        + String(repeating: "Stars travel across the night sky, 中文与 English remain readable. ", count: 12)
    let source = "Opening paragraph.\n\n" + paragraph + "\n\nClosing paragraph."
    let narrow = readingLayout(source, width: 300)
    let anchor = try #require(ReadingPositionIndex(layout: narrow).capture(y: readingY(narrow.paragraphs[1], line: 4)))
    #expect(anchor.blockIndex == 1 && anchor.offset > 0)
    let encoded = try JSONEncoder().encode(anchor)
    #expect(try JSONDecoder().decode(ReadingAnchor.self, from: encoded) == anchor)
    let persisted = String(decoding: encoded, as: UTF8.self)
    #expect(!persisted.contains("Astronomy") && !persisted.contains("Stars"))

    let wider = readingLayout(source, width: 520, size: 22)
    let restored = try #require(ReadingPositionIndex(layout: wider).y(for: anchor))
    #expect(abs(restored - (try expectedReadingY(wider.paragraphs[1], anchor: anchor))) < 0.00001)
    let after = try #require(ReadingPositionIndex(layout: wider).capture(y: restored))
    #expect(after.blockKey == anchor.blockKey)
    #expect(after.offset <= anchor.offset)
}

@Test func readingAnchorRelocatesAfterParagraphInsertionsAndEdits() throws {
    let target = "Target paragraph. " + String(repeating: "One two three four five six seven eight. ", count: 8)
    let source = "Previous paragraph.\n\n" + target + "\n\nFollowing paragraph.\n\nTail paragraph."
    let before = readingLayout(source)
    let anchor = try #require(ReadingPositionIndex(layout: before).capture(y: readingY(before.paragraphs[1], line: 2)))

    let inserted = readingLayout("Inserted one.\n\nInserted two.\n\n" + source)
    let insertedY = try #require(ReadingPositionIndex(layout: inserted).y(for: anchor))
    #expect(abs(insertedY - (try expectedReadingY(inserted.paragraphs[3], anchor: anchor))) < 0.00001)

    let edited = readingLayout(
        "Inserted one.\n\nInserted two.\n\nPrevious paragraph.\n\nRevised " + target
            + "\n\nFollowing paragraph.\n\nTail paragraph.")
    let editedIndex = ReadingPositionIndex(layout: edited)
    let editedY = try #require(editedIndex.y(for: anchor))
    let after = try #require(editedIndex.capture(y: editedY))
    #expect(after.blockIndex == 3)
    #expect(after.blockKey != anchor.blockKey)
}

@Test func readingAnchorUsesNeighborContextForRepeatedParagraphs() throws {
    let repeated = "Repeated paragraph. " + String(repeating: "Reading stays at this occurrence. ", count: 5)
    let original = ["Start.", repeated, "Separator.", "Specific previous.", repeated, "Specific next.", "End."]
    let before = readingLayout(original.joined(separator: "\n\n"))
    let anchor = try #require(ReadingPositionIndex(layout: before).capture(y: readingY(before.paragraphs[4], line: 1)))
    let added = (0..<50).map { "New paragraph \($0)." }
    let after = readingLayout((added + original).joined(separator: "\n\n"))
    let index = ReadingPositionIndex(layout: after)
    let restoredY = try #require(index.y(for: anchor))
    #expect(try #require(index.capture(y: restoredY)).blockIndex == 54)
}

@Test func readingOffsetsRemainSemanticAcrossMathAndImageObjects() throws {
    let source =
        "Before the formula $\\frac{1}{3}$ and then an image ![Long image description](images/tiny.png). "
        + String(repeating: "After both objects the reader keeps going. ", count: 12)
    let before = readingLayout(source, width: 260)
    let item = try #require(before.paragraphs.first)
    let rendered = item.paragraph.attributed.string as NSString
    let firstObject = rendered.range(of: "\u{FFFC}")
    let secondObject = rendered.range(
        of: "\u{FFFC}",
        range: NSRange(location: NSMaxRange(firstObject), length: rendered.length - NSMaxRange(firstObject)))
    let lineIndex = try #require(item.paragraph.lines.firstIndex { $0.range.location > secondObject.location })
    let anchor = try #require(ReadingPositionIndex(layout: before).capture(y: readingY(item, line: lineIndex)))
    let prefix = DocumentTextMap(item.paragraph.attributed).substring(
        in: NSRange(location: 0, length: item.paragraph.lines[lineIndex].range.location))
    #expect(prefix.contains("\\frac{1}{3}") && prefix.contains("Long image description"))
    #expect(anchor.offset == prefix.utf16.count)
    #expect(anchor.offset > item.paragraph.lines[lineIndex].range.location)
    let after = readingLayout(source, width: 480, size: 20)
    let restoredY = try #require(ReadingPositionIndex(layout: after).y(for: anchor))
    #expect(abs(restoredY - (try expectedReadingY(after.paragraphs[0], anchor: anchor))) < 0.00001)
}

@Test func readingAnchorHandlesEmptyReplacedAndInvalidPositions() throws {
    let empty = ReadingPositionIndex(layout: readingLayout(""))
    #expect(empty.capture(y: 0) == nil)
    let original = readingLayout("Old first.\n\nOld second.")
    var anchor = try #require(
        ReadingPositionIndex(layout: original).capture(y: readingY(original.paragraphs[1], line: 0)))
    #expect(empty.y(for: anchor) == nil)
    let replacement = ReadingPositionIndex(layout: readingLayout("Entirely different text."))
    #expect(replacement.y(for: anchor)?.isFinite == true)
    #expect(replacement.capture(y: .infinity) == nil)
    anchor.offset = -1
    #expect(replacement.y(for: anchor)?.isFinite == true)
    anchor.blockCount = .min
    #expect(replacement.y(for: anchor)?.isFinite == true)
    anchor.verticalFraction = .nan
    #expect(replacement.y(for: anchor) == nil)
}
