import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

fileprivate struct PaginationSnapshot: Decodable {
    var atom_format: Format
    var items: [Item]
    struct Format: Decodable {
        var height: Double
        var range_semantics: String
    }
    struct Item: Decodable {
        var height: Double
        var count: Int
        var result: Result
    }
    struct Result: Decodable {
        var page_atom_counts: [Int]
        var boundary_weld_flags: [Int]
    }
}

@Test func nativePaginationPackingMatchesFrozenAtoms() throws {
    let root = testRepositoryURL
    let snapshot = try JSONDecoder().decode(
        PaginationSnapshot.self,
        from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/Pagination.core.json")))
    #expect(snapshot.atom_format.range_semantics == "unverified")
    for item in snapshot.items {
        let h = snapshot.atom_format.height
        let bands = (0..<item.count).map {
            PaginationBand(
                range: Double($0) * h..<Double($0 + 1) * h, keepWithNext: item.result.boundary_weld_flags[$0] != 0)
        }
        let pages = try DocumentPaginator.pages(
            bands: bands, height: Double(item.count) * h, contentHeight: item.height)
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
    try DocumentExport.writePDF(MarkdownDocument(markdown: source), style: RenderStyle(), options: options, to: output)
    let pdf = try #require(PDFDocument(url: output))
    #expect(pdf.pageCount > 2)
    let allText = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: " ")
    for index in 0..<30 {
        #expect(allText.components(separatedBy: "Paragraph_\(index) ").count == 2, "Paragraph \(index) once")
    }
    for word in ["survive", "pagination", "missing", "words"] {
        #expect(allText.components(separatedBy: word).count == 31, "Each paragraph's \(word) appears once")
    }
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
    let layout = DocumentTypesetter.layout(
        DocumentParser.parse("# First\n\nSecond paragraph"), width: 400, style: style)
    // A short document still exports a full viewport, including blank paper.
    try DocumentExporter.writeImage(
        layout, style: style, scale: 2, region: CGRect(x: 0, y: 20, width: 400, height: 300), to: output)
    let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 800 && image.height == 600)
    #expect(throws: DocumentExportError.self) {
        try DocumentExporter.writeImage(layout, style: style, scale: 1e20, to: output)
    }
    var options = PDFExportOptions()
    options.margins = DocumentInsets(top: 1000, left: 0, bottom: 0, right: 0)
    #expect(throws: DocumentExportError.self) {
        try DocumentExporter.writePDF(DocumentParser.parse("Text"), style: style, options: options, to: output)
    }
}

@Test func nextPageTableBackgroundDoesNotLeakIntoPriorPage() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    defer { try? FileManager.default.removeItem(at: output) }
    var options = PDFExportOptions()
    options.paperSize = CGSize(width: 360, height: 168)
    options.margins = DocumentInsets(top: 24, left: 24, bottom: 24, right: 24)
    options.pageNumbers = false
    let document = DocumentParser.parse(
        "Short text.\n\n# Heading\n\n| Feature | Status |\n|---|---|\n| Markdown | Ready |")
    try DocumentExporter.writePDF(document, style: Typography(), options: options, to: output)
    let pdf = try #require(CGPDFDocument(output as CFURL))
    #expect(pdf.numberOfPages >= 2)
    let first = try #require(pdf.page(at: 1))
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try #require(
        CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    // In the old full-height clip, the next page's gray table header appeared
    // here despite its text and heading having moved to page two.
    context.translateBy(x: -180, y: -(168 - 130))
    context.drawPDFPage(first)
    #expect(pixel[0] >= 247 && pixel[1] >= 247 && pixel[2] >= 247)
}

@Suite struct ExportFileTests {
    @Test(arguments: [DocumentImageFormat.png, .jpeg])
    func fileImagesHaveCorrectEncodingGeometryAndPaper(format: DocumentImageFormat) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("image")
        let document = MarkdownDocument(
            markdown: "# Export\n\nTop text\n\n" + String(repeating: "Another paragraph.\n\n", count: 30) + "Last line")
        let style = RenderStyle(
            theme: DocumentTheme(
                id: "export-paper", name: "Export Paper", appearance: .light,
                document: ["paper": DocumentColor(red: 1, green: 0, blue: 0, alpha: 0.5)]))
        var options = ImageExportOptions()
        options.format = format
        options.scale = 1.5
        // Also exercise replacing a destination: the format does not depend on its extension.
        try Data("previous".utf8).write(to: output)
        try DocumentExport.writeImage(document, style: style, width: 320, options: options, to: output)
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == (format == .png ? "public.png" : "public.jpeg"))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let rendered = RenderedDocument(document, width: 320, style: style)
        #expect(image.width == 480)
        #expect(image.height == Int(ceil(rendered.size.height * options.scale)))
        #expect(image.height > image.width)
        // A paper corner must be filled, not JPEG's otherwise undefined alpha backdrop.
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(
            CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Rounded-up fractional-height edge rows must have full paper coverage too.
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if format == .jpeg {
            #expect(
                pixel[0] >= 250 && abs(Int(pixel[1]) - 128) <= 4 && abs(Int(pixel[2]) - 128) <= 4,
                "Paper pixel: \(pixel)")
            #expect(pixel[3] == 255)
        } else {
            #expect(abs(Int(pixel[0]) - 128) <= 1 && pixel[1] == 0 && pixel[2] == 0, "Paper pixel: \(pixel)")
            #expect(abs(Int(pixel[3]) - 128) <= 1)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["image"])
    }

    @Test func imageBudgetAndInvalidQualityPreserveDestination() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("keep.png")
        let original = Data("keep this file".utf8)
        try original.write(to: output)
        let document = MarkdownDocument(markdown: "# Too large")
        var options = ImageExportOptions()
        options.maximumBitmapBytes = 4
        do {
            try DocumentExport.writeImage(document, style: RenderStyle(), width: 320, options: options, to: output)
            Issue.record("Expected the raw bitmap budget to reject this export")
        } catch DocumentExportError.imageTooLarge(let width, let height) {
            #expect(width == 640 && height > 0)
        }
        options.maximumBitmapBytes = 128 * 1024 * 1024
        options.jpegQuality = .nan
        #expect(throws: DocumentExportError.self) {
            try DocumentExport.writeImage(document, style: RenderStyle(), width: 320, options: options, to: output)
        }
        options.jpegQuality = 0.9
        #expect(throws: CocoaError.self) {
            try DocumentExport.writeImage(document, style: RenderStyle(), width: 320, options: options, to: folder)
        }
        #expect(try Data(contentsOf: output) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["keep.png"])
    }

    @Test(arguments: [true, false])
    func cancellationDuringDrawingPreservesDestination(pdf: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("keep")
        let original = Data("keep this file".utf8)
        try original.write(to: output)
        let document = MarkdownDocument(markdown: String(repeating: "Paragraph for cancellation.\n\n", count: 100))
        let task = Task.detached {
            let cancelOnProgress: DocumentExportProgressHandler = { progress in
                if case .rendering = progress { withUnsafeCurrentTask { $0?.cancel() } }
            }
            if pdf {
                var options = PDFExportOptions()
                options.paperSize = CGSize(width: 320, height: 200)
                options.margins = DocumentInsets(top: 20, left: 20, bottom: 20, right: 20)
                try DocumentExport.writePDF(
                    document, style: RenderStyle(), options: options, to: output, progress: cancelOnProgress)
            } else {
                try DocumentExport.writeImage(
                    document, style: RenderStyle(), width: 320, to: output, progress: cancelOnProgress)
            }
        }
        do {
            try await task.value
            Issue.record("Expected cancellation during drawing")
        } catch is CancellationError {}
        #expect(try Data(contentsOf: output) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["keep"])
    }
}
