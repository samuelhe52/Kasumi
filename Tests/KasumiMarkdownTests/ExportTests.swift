import AppKit
import CoreGraphics
import ImageIO
import PDFKit
import Foundation
import Testing
@testable import KasumiMarkdown

private struct PaginationSnapshot: Decodable {
    var atom_format: Format
    var items: [Item]
    struct Format: Decodable { var height: Double; var range_semantics: String }
    struct Item: Decodable {
        var height: Double
        var count: Int
        var result: Result
    }
    struct Result: Decodable { var page_atom_counts: [Int]; var boundary_weld_flags: [Int] }
}

@Test func nativePaginationPackingMatchesFrozenAtoms() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let snapshot = try JSONDecoder().decode(PaginationSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/Pagination.core.json")))
    #expect(snapshot.atom_format.range_semantics == "unverified")
    for item in snapshot.items {
        let h = snapshot.atom_format.height
        let bands = (0..<item.count).map { PaginationBand(range: Double($0) * h..<Double($0 + 1) * h, keepWithNext: item.result.boundary_weld_flags[$0] != 0) }
        let pages = try DocumentPaginator.pages(bands: bands, height: Double(item.count) * h, contentHeight: item.height)
        #expect(pages.map { Int(($0.range.upperBound - $0.range.lowerBound) / h) } == item.result.page_atom_counts)
    }
}

@Test func paginationNeverCutsAnOccupiedLineOrWeldedHeading() throws {
    let bands = (0..<10).map { PaginationBand(range: CGFloat($0 * 20)..<CGFloat(($0 + 1) * 20)) }
    let pages = try DocumentPaginator.pages(bands: bands, height: 200, contentHeight: 50)
    #expect(pages.map(\.range) == [0..<40, 40..<80, 80..<120, 120..<160, 160..<200])
    var headed = bands
    headed[1].keepWithNext = true
    let welded = try DocumentPaginator.pages(bands: headed, height: 200, contentHeight: 50)
    #expect(welded[0].range == 0..<20)
    #expect(welded[1].range == 20..<60)
    let giant = try DocumentPaginator.pages(bands: [PaginationBand(range: 0..<200)], height: 200, contentHeight: 100)
    #expect(giant.count == 1 && giant[0].scale == 0.5)
}

@Test func pdfPagesRetainEveryParagraphAndFooter() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let paragraphs = (0..<30).map { "Paragraph_\($0) has text that must survive pagination without missing words." }
    let source = "# Export Verification\n\n" + paragraphs.joined(separator: "\n\n")
    var options = PDFExportOptions()
    options.paperSize = CGSize(width: 360, height: 280)
    options.margins = DocumentInsets(top: 24, left: 24, bottom: 24, right: 24)
    options.footerTemplate = "{file} · {page} of {pages}"
    options.title = "Authored Export"
    let output = directory.appendingPathComponent("pages.pdf")
    try DocumentExporter.writePDF(DocumentParser.parse(source), style: Typography(), options: options, to: output)
    let pdf = try #require(PDFDocument(url: output))
    #expect(pdf.pageCount > 2)
    let allText = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: " ")
    for index in 0..<30 { #expect(allText.components(separatedBy: "Paragraph_\(index) ").count == 2, "Paragraph \(index) once") }
    for word in ["survive", "pagination", "missing", "words"] { #expect(allText.components(separatedBy: word).count == 31, "Each paragraph's \(word) appears once") }
    for index in 0..<pdf.pageCount {
        let page = try #require(pdf.page(at: index))
        #expect(page.bounds(for: .mediaBox).size == options.paperSize)
        #expect(page.string?.contains("\(index + 1) of \(pdf.pageCount)") == true)
    }
}

@Test func imageViewportExportKeepsRequestedGeometryAndScale() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: output) }
    let style = Typography()
    let layout = DocumentTypesetter.layout(DocumentParser.parse("# First\n\nSecond paragraph"), width: 400, style: style)
    // A short document still exports a full viewport, including blank paper.
    try DocumentExporter.writeImage(layout, style: style, scale: 2, region: CGRect(x: 0, y: 20, width: 400, height: 300), to: output)
    let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 800 && image.height == 600)
    #expect(throws: DocumentExportError.self) { try DocumentExporter.writeImage(layout, style: style, scale: 1e20, to: output) }
    var options = PDFExportOptions()
    options.margins = DocumentInsets(top: 1000, left: 0, bottom: 0, right: 0)
    #expect(throws: DocumentExportError.self) { try DocumentExporter.writePDF(DocumentParser.parse("Text"), style: style, options: options, to: output) }
}

@Test func nextPageTableBackgroundDoesNotLeakIntoPriorPage() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    defer { try? FileManager.default.removeItem(at: output) }
    var options = PDFExportOptions()
    options.paperSize = CGSize(width: 360, height: 168)
    options.margins = DocumentInsets(top: 24, left: 24, bottom: 24, right: 24)
    options.pageNumbers = false
    let document = DocumentParser.parse("Short text.\n\n# Heading\n\n| Feature | Status |\n|---|---|\n| Markdown | Ready |")
    try DocumentExporter.writePDF(document, style: Typography(), options: options, to: output)
    let pdf = try #require(CGPDFDocument(output as CFURL))
    #expect(pdf.numberOfPages >= 2)
    let first = try #require(pdf.page(at: 1))
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    // In the old full-height clip, the next page's gray table header appeared
    // here despite its text and heading having moved to page two.
    context.translateBy(x: -180, y: -(168 - 130))
    context.drawPDFPage(first)
    #expect(pixel[0] >= 247 && pixel[1] >= 247 && pixel[2] >= 247)
}
