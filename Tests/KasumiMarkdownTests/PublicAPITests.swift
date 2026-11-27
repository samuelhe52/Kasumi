import CoreGraphics
import CoreText
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

fileprivate func facadeIsWorkerThread() -> Bool { !Thread.isMainThread }

fileprivate func facadeBitmap(size: CGSize, draw: (CGContext) -> Void) throws -> [UInt8] {
    let width = Int(ceil(size.width))
    let height = Int(ceil(size.height))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
        let context = try #require(
            CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(context)
    }
    return pixels
}

@Suite struct PublicAPITests {
    @Test func fixtureFacadeMatchesInternalLayoutAndTiledPixels() throws {
        let url = testRepositoryURL.appendingPathComponent("fixtures/Rendering.md")
        let source = try String(contentsOf: url, encoding: .utf8)
        let document = MarkdownDocument(markdown: source, baseURL: url.deletingLastPathComponent())
        let style = RenderStyle()
        let rendered = RenderedDocument(document, width: 540, style: style)
        let internalLayout = DocumentTypesetter.layout(
            document.parsed, width: 540, style: style.typography, insets: style.insets)
        #expect(rendered.size == CGSize(width: internalLayout.width, height: internalLayout.height))
        let reference = try facadeBitmap(size: rendered.size) { context in
            context.setFillColor(style.typography.paperColor.cgColor)
            context.fill(CGRect(origin: .zero, size: rendered.size))
            DocumentTypesetter.draw(internalLayout, in: context)
        }
        let full = try facadeBitmap(size: rendered.size) {
            rendered.draw(in: $0, rect: CGRect(origin: .zero, size: rendered.size))
        }
        // Compare each path with the same graphics clip. Core Graphics can
        // quantize clipped vector curves differently from an unclipped pass.
        let tiles = stride(from: CGFloat(0), to: rendered.size.height, by: 117).flatMap { y in
            stride(from: CGFloat(0), to: rendered.size.width, by: 180).map { x in
                CGRect(x: x, y: y, width: 180, height: 117)
            }
        }
        let internalTiled = try facadeBitmap(size: rendered.size) { context in
            for tile in tiles {
                context.saveGState()
                let visible = tile.intersection(CGRect(origin: .zero, size: rendered.size))
                context.clip(to: visible)
                context.setFillColor(style.typography.paperColor.cgColor)
                context.fill(CGRect(origin: .zero, size: rendered.size).integral)
                // No sourceRange culling: this is the existing reference draw.
                DocumentTypesetter.draw(internalLayout, in: context)
                context.restoreGState()
            }
        }
        let tiled = try facadeBitmap(size: rendered.size) { context in
            for tile in tiles { rendered.draw(in: context, rect: tile) }
        }
        func difference(_ actual: [UInt8], _ expected: [UInt8]) -> Int {
            zip(actual, expected).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
        }
        #expect(difference(full, reference) == 0)
        #expect(difference(tiled, internalTiled) == 0)

    }

    @Test func semanticSelectionSearchAndCaretRoundTrips() throws {
        let rendered = RenderedDocument(
            MarkdownDocument(markdown: "Café 中文 $x_i+1$ and **bold**.\n\nNext 👩‍👩‍👧‍👦 line."), width: 260,
            style: RenderStyle())
        #expect(rendered.text(in: rendered.documentRange) == "Café 中文 x_i+1 and bold.\nNext 👩‍👩‍👧‍👦 line.")
        let cjkMath = try #require(rendered.ranges(matching: "中文 x_i+1").first)
        #expect(rendered.text(in: cjkMath) == "中文 x_i+1")
        #expect(!rendered.selectionRects(for: cjkMath).isEmpty)
        let formula = try #require(rendered.ranges(matching: "x_i+1").first)
        #expect(rendered.text(in: formula) == "x_i+1")
        #expect(!rendered.selectionRects(for: formula).isEmpty)
        #expect(rendered.ranges(matching: "CAFE").count == 1)
        #expect(rendered.ranges(matching: "CAFE", options: [.caseSensitive]).isEmpty)
        #expect(rendered.ranges(matching: "Cafe", options: [.diacriticSensitive]).isEmpty)
        #expect(rendered.ranges(matching: "").isEmpty)
        for range in rendered.ranges(matching: "Café") + rendered.ranges(matching: "bold")
            + rendered.ranges(matching: "👩‍👩‍👧‍👦")
        {
            for position in [range.lowerBound, range.upperBound] {
                let caret = rendered.caretRect(for: position)
                #expect(rendered.position(closestTo: CGPoint(x: caret.minX, y: caret.midY)) == position)
            }
        }
        let end = rendered.caretRect(for: rendered.documentRange.upperBound)
        #expect(rendered.position(closestTo: CGPoint(x: end.minX, y: end.midY)) == rendered.documentRange.upperBound)
        let bold = try #require(rendered.ranges(matching: "bold").first)
        let word = try #require(rendered.wordRange(at: bold.lowerBound))
        #expect(rendered.text(in: word) == "bold")
        // The word search is scoped to the paragraph around the position.
        let next = try #require(rendered.ranges(matching: "Next").first)
        #expect(rendered.wordRange(at: next.lowerBound).map(rendered.text(in:)) == "Next")
        let last = try #require(rendered.ranges(matching: "line").first)
        #expect(rendered.wordRange(at: last.lowerBound).map(rendered.text(in:)) == "line")
        let other = RenderedDocument(MarkdownDocument(markdown: "Other"), width: 260, style: .init())
        #expect(other.text(in: cjkMath).isEmpty)
    }

    @Test func textInputPositionArithmeticUsesSnapshotOwnedUTF16Offsets() throws {
        let rendered = RenderedDocument(
            MarkdownDocument(markdown: "A👩‍👩‍👧‍👦e\u{301} 中文 $x_i$"), width: 260, style: .init())
        let text = rendered.text(in: rendered.documentRange)
        let start = rendered.documentRange.lowerBound
        let end = rendered.documentRange.upperBound
        #expect(rendered.offset(from: start, to: end) == text.utf16.count)
        for offset in 0...text.utf16.count {
            let position = try #require(rendered.position(from: start, offset: offset))
            #expect(rendered.offset(from: start, to: position) == offset)
            #expect(rendered.position(from: position, offset: -offset) == start)
        }
        let emoji = try #require(rendered.ranges(matching: "👩‍👩‍👧‍👦").first)
        #expect(rendered.offset(from: emoji.lowerBound, to: emoji.upperBound) == 11)
        #expect(rendered.text(in: emoji) == "👩‍👩‍👧‍👦")
        #expect(rendered.position(from: start, offset: -1) == nil)
        #expect(rendered.position(from: end, offset: 1) == nil)
        #expect(rendered.position(from: end, offset: Int.max) == nil)
        #expect(rendered.position(from: start, offset: Int.min) == nil)
        let foreign = RenderedDocument(MarkdownDocument(markdown: "Other"), width: 260, style: .init())
        #expect(rendered.position(from: foreign.documentRange.lowerBound, offset: 0) == nil)
        #expect(rendered.offset(from: start, to: foreign.documentRange.upperBound) == nil)
        #expect(rendered.offset(from: foreign.documentRange.lowerBound, to: end) == nil)
        let empty = RenderedDocument(MarkdownDocument(markdown: ""), width: 260, style: .init())
        #expect(empty.position(from: empty.documentRange.lowerBound, offset: 0) == empty.documentRange.upperBound)
        #expect(empty.position(from: empty.documentRange.lowerBound, offset: 1) == nil)
    }

    @Test func outlineLinksAndReadingAnchorsUseStableDocumentCoordinates() throws {
        let source =
            "# Same 标题\n\n[Outside](https://example.com) [Inside](#same-标题-1)\n\n## Same 标题\n\n"
            + String(repeating: "Reading words across reflow.\n\n", count: 12)
        let document = MarkdownDocument(markdown: source)
        #expect(document.outline.map(\.id) == ["same-标题", "same-标题-1"])
        let rendered = RenderedDocument(document, width: 400, style: .init())
        let first = try #require(rendered.rect(for: document.outline[0]))
        let second = try #require(rendered.rect(for: document.outline[1]))
        #expect(second.minY > first.minY)
        #expect(rendered.rect(forAnchor: "#same-%E6%A0%87%E9%A2%98-1") == second)
        for (text, expected) in [("Outside", "https://example.com"), ("Inside", "#same-标题-1")] {
            let range = try #require(rendered.ranges(matching: text).first)
            let rect = try #require(rendered.selectionRects(for: range).first)
            for x in [rect.minX + 0.5, rect.midX, rect.maxX - 0.5] {
                let link = try #require(rendered.link(at: CGPoint(x: x, y: rect.midY)))
                #expect(link.absoluteString.removingPercentEncoding == expected)
            }
        }
        let footnotes = RenderedDocument(
            MarkdownDocument(markdown: "Follow this footnote[^reader].\n\n[^reader]: Destination."),
            width: 400, style: .init())
        let marker = try #require(footnotes.ranges(matching: "1").first)
        let markerRect = try #require(footnotes.selectionRects(for: marker).first)
        #expect(footnotes.link(at: CGPoint(x: markerRect.midX, y: markerRect.midY))?.fragment == "fn-reader")
        #expect(footnotes.rect(forAnchor: "fn-reader") != nil)
        let y: CGFloat = second.midY
        let anchor = rendered.readingAnchor(atY: y)
        #expect(abs(try #require(rendered.y(for: anchor)) - y) < 1e-8)
        let reflowed = RenderedDocument(document, width: 260, style: .init())
        #expect(reflowed.y(for: anchor) != nil)
        #expect(try JSONDecoder().decode(ReadingAnchor.self, from: JSONEncoder().encode(anchor)) == anchor)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(anchor)) as? [String: Any])
        #expect(
            Set(encoded.keys)
                == Set([
                    "blockKey", "blockIndex", "offset", "previousKeys", "nextKeys", "blockCount", "verticalFraction"
                ]))
        let legacyData = Data(
            #"{"blockKey":"persisted-key","blockIndex":3,"offset":42,"previousKeys":["before"],"nextKeys":["after"],"blockCount":8,"verticalFraction":0.25}"#
                .utf8)
        let legacy = try JSONDecoder().decode(ReadingAnchor.self, from: legacyData)
        let reencoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? NSDictionary)
        #expect(reencoded == (try JSONSerialization.jsonObject(with: legacyData) as? NSDictionary))
    }

    @Test func dataInitializersAndExportsPreserveTextAndPageGeometry() throws {
        let empty = RenderedDocument(MarkdownDocument(markdown: ""), width: 300, style: .init())
        #expect(empty.documentRange.isEmpty)
        #expect(empty.text(in: empty.documentRange).isEmpty)
        #expect(empty.selectionRects(for: empty.documentRange).isEmpty)
        #expect(empty.position(closestTo: .zero) == empty.documentRange.lowerBound)
        #expect(empty.y(for: empty.readingAnchor(atY: 0)) == 0)
        let plain = try MarkdownDocument(data: Data("# Literal".utf8), fileExtension: ".TXT")
        #expect(plain.outline.isEmpty)
        let markdown = try MarkdownDocument(data: Data("# Heading".utf8), fileExtension: "md")
        #expect(markdown.outline.first?.title == "Heading")
        #expect(throws: DocumentDecodingError.self) {
            try MarkdownDocument(data: Data([0xff]), fileExtension: "md", encoding: .utf8)
        }
        let rendered = RenderedDocument(markdown, width: 300, style: .init())
        let png = try DocumentExport.png(rendered, scale: 2, region: CGRect(x: 20, y: 10, width: 100, height: 80))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 200 && image.height == 160)
        #expect(!png.isEmpty)
        let jpeg = try DocumentExport.jpeg(
            rendered, scale: 1.5, quality: 0.8, region: CGRect(x: 20, y: 10, width: 100, height: 80))
        let jpegSource = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let jpegImage = try #require(CGImageSourceCreateImageAtIndex(jpegSource, 0, nil))
        #expect(CGImageSourceGetType(jpegSource) as String? == "public.jpeg")
        #expect(jpegImage.width == 150 && jpegImage.height == 120)
        let pdfData = try DocumentExport.pdf(markdown, style: .init())
        let pdf = try #require(PDFDocument(data: pdfData))
        #expect(pdf.pageCount == 1)
        #expect(pdf.page(at: 0)?.string?.contains("Heading") == true)
        let long = MarkdownDocument(markdown: String(repeating: "Paragraph retained by PDF pagination.\n\n", count: 25))
        let pageSize = CGSize(width: 300, height: 220)
        let margins = DocumentInsets(top: 20, left: 20, bottom: 20, right: 20)
        let style = RenderStyle()
        var internalOptions = PDFExportOptions()
        internalOptions.paperSize = pageSize
        internalOptions.margins = margins
        let expected = try #require(
            PDFDocument(data: DocumentExporter.pdfData(long.parsed, style: style.typography, options: internalOptions)))
        let multi = try #require(
            PDFDocument(data: DocumentExport.pdf(long, style: style, pageSize: pageSize, margins: margins)))
        #expect(multi.pageCount == expected.pageCount && multi.pageCount > 1)
        #expect(multi.page(at: 0)?.bounds(for: .mediaBox).size == pageSize)
    }

    @Test func detachedBuildAndConcurrentSnapshotUseAreSafe() async throws {
        let document = MarkdownDocument(
            markdown: "# Worker\n\n中文 $x^2$ and `code`.\n\n```mermaid\ngraph LR\n A --> B\n```\n")
        let rendered = await Task.detached {
            #expect(facadeIsWorkerThread())
            return RenderedDocument(document, width: 400, style: .init())
        }.value
        #expect(rendered.size.height > 0)
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    let built = RenderedDocument(document, width: 400, style: .init())
                    #expect(built.size == rendered.size)
                    #expect(rendered.text(in: rendered.documentRange).contains("x^2"))
                    let png = try DocumentExport.png(rendered, scale: 1)
                    return png.count
                }
            }
            for try await count in group { #expect(count > 0) }
        }
    }

    @Test func explicitStyleOverridesAndInstalledMacFamiliesArePreserved() throws {
        let paper = try #require(DocumentColor(hex: "#102030"))
        let theme = DocumentTheme(
            id: "client", name: "Client palette", appearance: .dark,
            document: ["paper": paper])
        let insets = DocumentInsets(top: 12, left: 13, bottom: 14, right: 15)
        let style = RenderStyle(theme: theme, fontSize: 21, widthLimit: nil, insets: insets)
        #expect(style.typography.size == 21)
        #expect(!style.typography.limitWidth && style.typography.dark)
        #expect(style.typography.documentTheme.appearance == theme.appearance)
        #expect(
            style.typography.documentTheme.document["rule"]
                == DocumentThemeCatalog.theme(id: "default-dark", dark: true).document["rule"])
        #expect(style.typography.documentTheme.id == "client")
        let rendered = RenderedDocument(MarkdownDocument(markdown: "Explicit style"), width: 300, style: style)
        #expect(PlatformColors.srgb(rendered.backgroundColor) == paper)
        #expect(rendered.size.width == 300)
        #expect(style == RenderStyle(theme: theme, fontSize: 21, widthLimit: nil, insets: insets))
        #if os(macOS)
            for preset in TypographyPreset.builtin {
                let legacy = Typography().applying(preset.values)
                let mapped = RenderStyle(preset: preset).typography
                #expect(mapped.latinFamily == legacy.latinFamily)
                #expect(mapped.hanFamily == legacy.hanFamily)
                #expect(mapped.codeFamily == legacy.codeFamily)
                #expect(mapped.font().fontName == legacy.font().fontName)
                #expect(mapped.font(cjk: true).fontName == legacy.font(cjk: true).fontName)
                #expect(mapped.documentTheme == legacy.documentTheme)
            }
        #endif
    }

    @Test func editedPresetSpacingReachesReaderAndExport() throws {
        let book = try #require(TypographyPreset.builtin.first { $0.id == "book" })
        #expect(book.spacing.paragraphStyle == .indented)
        #expect(book.applyingSpacing(book.spacing) == book)
        var spacing = book.spacing
        spacing.lineSpacing = 2.4
        spacing.paragraphStyle = .spaced
        spacing.headingSpaceBefore = 4
        spacing.headingSpaceAfter = 3
        let edited = book.applyingSpacing(spacing)
        #expect(edited.id == book.id && edited.name == book.name)
        #expect(edited.printFontSize == book.printFontSize)
        #expect(edited.spacing == spacing)
        #expect(book.spacing.paragraphStyle == .indented)

        let originalStyle = RenderStyle(preset: book, fontSize: 18, insets: .zero)
        let style = RenderStyle(preset: edited, fontSize: 18, insets: .zero)
        let typography = style.typography
        #expect(typography.size == 18)
        #expect(typography.lineSpacing == 2.4)
        #expect(typography.firstLineIndent == 0 && typography.paraSpaceBetween > 0)
        #expect(typography.headingSpaceBefore == 4 && typography.headingSpaceAfter == 3)
        let document = MarkdownDocument(
            markdown: "First paragraph.\n\nSecond paragraph.\n\n## A heading\n\nAfter the heading.")
        let original = RenderedDocument(document, width: 240, style: originalStyle)
        let rendered = RenderedDocument(document, width: 240, style: style)
        #expect(rendered.size.height > original.size.height)

        var pdf = PDFExportOptions()
        pdf.paperSize = CGSize(width: 240, height: 145)
        pdf.margins = .zero
        pdf.pageNumbers = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let originalPDF = folder.appendingPathComponent("original.pdf")
        let editedPDF = folder.appendingPathComponent("edited.pdf")
        try DocumentExport.writePDF(document, style: originalStyle, options: pdf, to: originalPDF)
        try DocumentExport.writePDF(document, style: style, options: pdf, to: editedPDF)
        let originalPages = try #require(PDFDocument(url: originalPDF)).pageCount
        let editedPages = try #require(PDFDocument(url: editedPDF)).pageCount
        #expect(editedPages > originalPages)

        var options = ImageExportOptions()
        options.scale = 1
        let imageURL = folder.appendingPathComponent("edited.png")
        try DocumentExport.writeImage(document, style: style, width: 240, options: options, to: imageURL)
        let imageSource = try #require(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        #expect(image.height == Int(ceil(rendered.size.height)))
    }

    @Test func missingFamilyUsesOrderedFallbackWithoutDownloads() throws {
        let preset = try TypographyPreset(
            id: "missing", name: "Missing family", toml: "[profile]\nhan_family = \"KasumiDeliberatelyMissingFamily\"\n"
        )
        let style = RenderStyle(preset: preset)
        #expect(FontAvailability.missingFamilies(for: style).contains("KasumiDeliberatelyMissingFamily"))
        let bundled = try #require(TypographyPreset.builtin.first { $0.id == "serif-pagella" })
        #expect(!FontAvailability.missingFamilies(for: RenderStyle(preset: bundled)).contains("TeX Gyre Pagella"))
        #expect(style.typography.hanFamily != "KasumiDeliberatelyMissingFamily")
        #expect(
            FontFamilyResolver.firstAvailable(in: ["Missing", "Fallback", "Later"], available: { $0 != "Missing" })
                == "Fallback")
        #expect(FontFamilyResolver.firstAvailable(in: ["Missing"], available: { _ in false }) == nil)
        // An open substitute directly follows its Apple face, so Traditional stays Traditional.
        let traditional = FontFamilyResolver.chain(for: "Songti TC", role: .han)
        #expect(Array(traditional.prefix(3)) == ["Songti TC", "Noto Serif TC", "Songti SC"])
        #expect(
            FontFamilyResolver.firstAvailable(in: traditional, available: { $0.hasPrefix("Noto") }) == "Noto Serif TC")
        // A preferred open substitute moves ahead of its Apple face only.
        let preferred = FontFamilyResolver.chain(for: "Songti SC", role: .han, preferring: ["Noto Serif SC"])
        #expect(Array(preferred.prefix(2)) == ["Noto Serif SC", "Songti SC"])
        #expect(
            FontFamilyResolver.chain(for: "Songti TC", role: .han, preferring: ["Noto Serif SC"]).first == "Songti TC")
        let rendered = RenderedDocument(MarkdownDocument(markdown: "汉字与 fallback"), width: 300, style: style)
        #expect(rendered.text(in: rendered.documentRange) == "汉字与 fallback")
        #expect(rendered.size.height > 0)
    }
}
