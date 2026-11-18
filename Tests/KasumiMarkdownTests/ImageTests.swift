import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

fileprivate let imageFixtureDirectory = testRepositoryURL.appendingPathComponent("fixtures")

fileprivate func imagePixel(_ bitmap: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
    let crop = try #require(bitmap.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = try #require(
        CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return bytes
}

@Test func imageParserPreservesSourcesLinksAndNativeBlockKinds() throws {
    let source = try String(contentsOf: imageFixtureDirectory.appendingPathComponent("Images.md"), encoding: .utf8)
    let document = DocumentParser.parse(source, baseURL: imageFixtureDirectory)
    let raw = try Data(contentsOf: imageFixtureDirectory.appendingPathComponent("reference/Images.core.json"))
    let snapshot = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
    let native = try #require(snapshot["items"] as? [[String: Any]])
    #expect(
        snapshot["fixture_sha256"] as? String
            == SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined())
    #expect(document.blocks.count == native.count)
    for (block, observation) in zip(document.blocks, native) {
        let kind = block.kind == .heading ? 1 : block.kind == .image ? 5 : block.kind == .table ? 6 : 0
        #expect(observation["kind"] as? Int == kind)
        #expect(observation["text"] as? String == block.text)
    }
    let linked = try #require(document.blocks.first { $0.text == "Linked checkerboard" })
    #expect(linked.kind == .image)
    #expect(linked.runs[0].imageSource == "images/tiny.png")
    #expect(linked.runs[0].destination == "https://example.com")
    #expect(linked.runs[0].traits.contains(.link))
    let inline = try #require(document.blocks.first { $0.text.hasPrefix("Inline image:") })
    #expect(inline.kind == .paragraph)
    #expect(
        inline.runs.contains {
            $0.traits.contains(.image) && $0.imageSource == "images/tiny.png" && $0.text == "Checkerboard"
        })
}

@Test func localDataAndPercentEncodedImagesResolveAndFitWithoutUpscaling() throws {
    let store = DocumentImageStore()
    let wide = try #require(store.image(for: "images/wide%20sample.png", baseURL: imageFixtureDirectory))
    #expect(wide.size == CGSize(width: 640, height: 320))
    #expect(wide.fitted(to: 320) == CGSize(width: 320, height: 160))
    #expect(wide.fitted(to: 1000) == wide.size)
    let url = imageFixtureDirectory.appendingPathComponent("images/tiny.png")
    let tiny = try #require(store.image(for: url.absoluteString, baseURL: nil))
    #expect(tiny.size == CGSize(width: 32, height: 24))
    #expect(store.image(for: url.path, baseURL: nil)?.size == tiny.size)
    let data = try Data(contentsOf: url)
    #expect(store.image(for: "data:image/png;base64," + data.base64EncodedString(), baseURL: nil)?.size == tiny.size)
    let escaped = data.map { String(format: "%%%02X", $0) }.joined()
    #expect(store.image(for: "data:image/png," + escaped, baseURL: nil)?.size == tiny.size)
    #expect(store.image(for: "images/missing.png", baseURL: imageFixtureDirectory) == nil)
    #expect(store.image(for: "data:image/png;base64,not_an_image", baseURL: nil) == nil)
    #expect(store.image(for: "ftp://example.com/image.png", baseURL: nil) == nil)
    #expect(DocumentImageStore.resourceURL("file://other-host/share/image.png", baseURL: nil) == nil)
}

@Test func imageOrientationAndTallLineGeometryRemainCorrect() throws {
    let context = try #require(
        CGContext(
            data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let original = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, original, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let decoded = try #require(DocumentImageStore.decode(data as Data))
    #expect(decoded.size == CGSize(width: 8, height: 12))
    #expect(decoded.bitmap.width == 8 && decoded.bitmap.height == 12)

    let document = DocumentParser.parse(
        "Before ![Tall](images/wide%20sample.png) after.\n", baseURL: imageFixtureDirectory)
    let layout = DocumentTypesetter.layout(document, width: 400, style: Typography())
    let image = try #require(layout.imageBounds.first)
    #expect(image.width == 320 && image.height == 160)
    #expect(layout.height >= image.maxY)
    #expect(!layout.textMap.string.contains("\u{FFFC}"))
    #expect(layout.textMap.string == "Before Tall after.\n")
    let match = try #require(layout.textMap.matches("Tall").first)
    #expect(layout.textMap.substring(in: match) == "Tall")
}

@Test func imagePaintOrientationAndMissingAltSemantics() throws {
    let document = DocumentParser.parse(
        """
        ![Sample](images/wide%20sample.png)

        ![Missing](images/no.png)

        Before ![Inline](images/no.png) after.

        Before ![שלום](images/no.png) עולם after
        """,
        baseURL: imageFixtureDirectory)
    let theme = DocumentTheme(
        id: "test", name: "Test", appearance: .light,
        document: [
            "paper": DocumentColor(red: 1, green: 1, blue: 1),
            "image_placeholder_background": DocumentColor(red: 1, green: 0, blue: 1)
        ])
    let style = RenderStyle(theme: theme).typography
    let layout = DocumentTypesetter.layout(document, width: 400, style: style)
    let imageRect = try #require(layout.imageBounds.first)
    #expect(imageRect == CGRect(x: 40, y: 28, width: 320, height: 160))
    #expect(layout.text.string.contains("Image unavailable: Missing"))
    #expect(layout.textMap.string == "Sample\nMissing\nBefore Inline after.\nBefore שלום עולם after\n")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = folder.appendingPathComponent("images.png")
    try DocumentExporter.writeImage(document, style: style, width: 400, scale: 1, to: output)
    let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
    let bitmap = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    func pixel(_ x: Int, _ y: Int) throws -> [UInt8] {
        try imagePixel(bitmap, x, y)
    }
    let top = try pixel(200, 48)
    let bottom = try pixel(200, 168)
    let corner = try pixel(48, 36)
    #expect(top[0] > 180 && top[1] < 80)
    #expect(bottom[0] < 80 && bottom[1] > 120)
    #expect(corner[0] > 240 && corner[1] > 240 && corner[2] > 240)
    for fallback in ["Image unavailable: Missing", "Image unavailable: Inline"] {
        let placed = try #require(layout.paragraphs.first { $0.paragraph.attributed.string.contains(fallback) })
        let range = (placed.paragraph.attributed.string as NSString).range(of: fallback)
        let space = range.location + "Image".utf16.count
        let line = try #require(placed.paragraph.lines.first { NSLocationInRange(space, $0.range) })
        let x = (line.offset(forStringIndex: space) + line.offset(forStringIndex: space + 1)) / 2
        let painted = try pixel(Int(placed.origin.x + line.origin.x + x), Int(placed.origin.y + line.origin.y))
        #expect(painted[0] > 240 && painted[1] < 15 && painted[2] > 240)
    }
    let placed = try #require(layout.paragraphs.first { $0.paragraph.attributed.string.contains("עולם") })
    let line = try #require(placed.paragraph.lines.first)
    #expect(line.fragments.isEmpty)
    func bidiPixel(under word: String) throws -> [UInt8] {
        let range = (placed.paragraph.attributed.string as NSString).range(of: word)
        let span = try #require(CoreTextRangeGeometry.extents(in: line.line, for: range).first)
        let x = (span.lowerBound + span.upperBound) / 2
        return try pixel(Int(placed.origin.x + line.origin.x + x), Int(placed.origin.y + line.origin.y) + 2)
    }
    let placeholder = try bidiPixel(under: "שלום")
    let neighbor = try bidiPixel(under: "עולם")
    #expect(placeholder[0] > 240 && placeholder[1] < 15 && placeholder[2] > 240)
    #expect(neighbor[0] > 240 && neighbor[1] > 240 && neighbor[2] > 240)
}

@Test func wrappedImagePlaceholderPaintsBehindDiscretionaryHyphen() throws {
    let document = DocumentParser.parse("![Sample photograph](images/no.png)", baseURL: imageFixtureDirectory)
    let theme = DocumentTheme(
        id: "test", name: "Test", appearance: .light,
        document: ["image_placeholder_background": DocumentColor(red: 1, green: 0, blue: 1)])
    let style = RenderStyle(theme: theme).typography
    let layout = DocumentTypesetter.layout(document, width: 205, style: style)
    let placed = try #require(layout.paragraphs.first)
    let line = try #require(placed.paragraph.lines.first { $0.hyphen != nil })
    let hyphen = try #require(line.hyphen)

    let png = try DocumentExporter.imageData(layout, style: style, scale: 1)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let bitmap = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    // Sample below the baseline to read the fill without touching the hyphen glyph.
    let x = Int(placed.origin.x + line.origin.x + hyphen.x + hyphen.width / 2)
    let y = Int(placed.origin.y + line.origin.y) + 2
    let fill = try imagePixel(bitmap, x, y)
    #expect(fill[0] > 240 && fill[1] < 15 && fill[2] > 240)
}

fileprivate final class ImageFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "image-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let large = url.lastPathComponent == "oversized.png"
        let svg = url.pathExtension == "svg"
        let fixture = svg ? "HTMLAndSVG/build.svg" : "images/tiny.png"
        let data = large ? nil : try? Data(contentsOf: imageFixtureDirectory.appendingPathComponent(fixture))
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Length": large ? "30000000" : String(data?.count ?? 0),
                "Content-Type": svg ? "image/svg+xml" : "image/png"
            ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func remoteImagesRequireBoundedAsynchronousPreload() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageFixtureProtocol.self]
    let store = DocumentImageStore(session: URLSession(configuration: configuration))
    let url = "https://image-fixture.invalid/tiny.png"
    let svg = "https://image-fixture.invalid/build.svg"
    let document = DocumentParser.parse("![Remote](\(url))\n\n<p><img src=\"\(svg)\"></p>")
    #expect(store.image(for: url, baseURL: nil) == nil)
    #expect(store.image(for: svg, baseURL: nil) == nil)
    #expect(await store.preload(document))
    #expect(store.image(for: url, baseURL: nil)?.size == CGSize(width: 32, height: 24))
    #expect(store.image(for: svg, baseURL: nil)?.size == CGSize(width: 88, height: 20))
    #expect(await store.preload(document) == false)
    let oversized = "https://image-fixture.invalid/oversized.png"
    #expect(await store.preload(DocumentParser.parse("![Too big](\(oversized))")) == false)
    #expect(store.image(for: oversized, baseURL: nil) == nil)
}

@Test func svgBadgeRasterizesAtThreeTimesSizeWithText() throws {
    let url = imageFixtureDirectory.appendingPathComponent("HTMLAndSVG/build.svg")
    let data = try Data(contentsOf: url)
    let badge = try #require(DocumentImageStore.decode(data))
    #expect(badge.size == CGSize(width: 88, height: 20))
    #expect(badge.bitmap.width == 264 && badge.bitmap.height == 60)

    let raster = try #require(badge.bitmap.dataProvider?.data as Data?)
    var whitePixels = 0
    for row in 0..<badge.bitmap.height {
        for column in 0..<badge.bitmap.width {
            let offset = row * badge.bitmap.bytesPerRow + column * 4
            if raster[offset..<(offset + 4)].allSatisfy({ $0 >= 245 }) { whitePixels += 1 }
        }
    }
    #expect(whitePixels > 20)  // Only the badge lettering is white.
}

@Test func svgReaderRastersFollowFittedSizeAndKeepExportPixels() async throws {
    let store = DocumentImageStore()
    let source = "HTMLAndSVG/logo.svg"
    let cache = ReaderImageCache(displayScale: 3, store: store)
    func request(_ maximumWidth: CGFloat, width: CGFloat? = nil, height: CGFloat? = nil) throws -> ReaderImageRequest {
        try #require(
            cache.request(
                for: source, baseURL: imageFixtureDirectory, maximumWidth: maximumWidth, width: width, height: height))
    }
    let narrow = try request(50)
    #expect(narrow.source.info.size == CGSize(width: 120, height: 96))
    #expect(!cache.hasResult(for: narrow.key))
    #expect(await cache.load(narrow))
    let reader = try #require(cache.bitmap(for: narrow.key))
    #expect(reader.width == 150 && reader.height == 120)

    let authored = try request(100, width: 50)
    #expect(authored.key == narrow.key)
    #expect(await cache.load(authored) == false)
    let stretched = try request(100, width: 50, height: 20)
    #expect(await cache.load(stretched))
    let second = try #require(cache.bitmap(for: stretched.key))
    #expect(second.width == 150 && second.height == 60)

    let export = try #require(store.image(for: source, baseURL: imageFixtureDirectory))
    #expect(export.bitmap.width == 360 && export.bitmap.height == 288)
    #expect(export.fitted(to: 50) == narrow.size)
    #expect(cache.bitmap(for: narrow.key) === reader)
}

@Test func readerRemotePreloadMakesMetadataAvailableBeforePixels() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageFixtureProtocol.self]
    let store = DocumentImageStore(session: URLSession(configuration: configuration))
    let svg = "https://image-fixture.invalid/build.svg"
    let png = "https://image-fixture.invalid/tiny.png"
    let document = DocumentParser.parse("![Badge](\(svg))\n\n![Sample](\(png))")
    let cache = ReaderImageCache(displayScale: 2, store: store)
    #expect(store.readerSource(for: svg, baseURL: nil) == nil)
    #expect(await store.preload(document, forReader: true))
    for (source, size) in [(svg, CGSize(width: 88, height: 20)), (png, CGSize(width: 32, height: 24))] {
        let request = try #require(
            cache.request(
                for: source, baseURL: nil, maximumWidth: 44, width: nil, height: nil))
        #expect(request.source.info.size == size)
        #expect(!cache.hasResult(for: request.key))
        #expect(await cache.load(request))
        let reader = try #require(cache.bitmap(for: request.key))
        #expect(reader.width == (source == svg ? 88 : 32))
    }
    #expect(await store.preload(document, forReader: true) == false)
    let export = try #require(store.image(for: svg, baseURL: nil))
    #expect(export.bitmap.width == 264 && export.bitmap.height == 60)
}

@Test func readerRequestsOnlyVisiblePixelsAndPreservesGeometry() async throws {
    let markdown = """
        <a href="https://example.com"><img src="images/wide%20sample.png" alt="Wide sample"></a>

        \(Array(repeating: "A paragraph before the table.", count: 50).joined(separator: "\n\n"))

        | First | Second |
        | --- | --- |
        | ![Logo](HTMLAndSVG/logo.svg) | ![Badge](HTMLAndSVG/build.svg) |
        """
    let document = MarkdownDocument(markdown: markdown, baseURL: imageFixtureDirectory)
    let style = RenderStyle(widthLimit: nil)
    let cache = ReaderImageCache(displayScale: 1)
    let rendered = RenderedDocument(
        document, width: 200, style: style, scrollableTables: true, preparation: nil, readerImages: cache)
    let first = CGRect(x: 0, y: 0, width: 200, height: 200)
    let start = rendered.readerImageRegions(in: first)
    #expect(start.count == 1)
    let wide = try #require(start.first)
    #expect(wide.rect.size == CGSize(width: 120, height: 60))
    #expect(!rendered.hasReaderImageResult(for: wide))
    func paint() throws -> [UInt8] {
        let context = try #require(
            CGContext(
                data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: 200)
        context.scaleBy(x: 1, y: -1)
        rendered.draw(in: context, rect: first)
        let bitmap = try #require(context.makeImage())
        return try imagePixel(bitmap, Int(wide.rect.midX), Int(wide.rect.minY + 8))
    }
    let before = try paint()
    #expect(!rendered.hasReaderImageResult(for: wide))
    #expect(await rendered.prepareReaderImage(wide))
    #expect(cache.bitmap(for: wide.request.key)?.width == 120)
    #expect(try paint() != before)
    #expect(rendered.readerImageRegions(in: first) == start)
    #expect(rendered.link(at: CGPoint(x: wide.rect.midX, y: wide.rect.midY))?.host == "example.com")
    #expect(rendered.text(in: rendered.documentRange).contains("Wide sample"))

    let table = try #require(rendered.tables.first)
    #expect(table.isScrollable)
    let trailing = rendered.readerImageRegions(
        in: table.frame, tableOffsets: [table.id: table.contentWidth - table.frame.width])
    let leading = rendered.readerImageRegions(in: table.frame)
    #expect(leading.count == 1 && leading.first?.tableID == table.id)
    let badge = try #require(trailing.last)
    #expect(badge.request.source.url.lastPathComponent == "build.svg")
    #expect(!leading.contains(badge))
    #expect(!rendered.hasReaderImageResult(for: badge))
    #expect(await rendered.prepareReaderImage(badge))
}

@Test func readerCacheEvictionLeavesRetainedGeometryRepaintable() async throws {
    let cache = ReaderImageCache(displayScale: 1, byteLimit: 9 * 1024)
    let document = MarkdownDocument(
        markdown: "![Badge](HTMLAndSVG/build.svg)\n\n![Small](images/tiny.png)",
        baseURL: imageFixtureDirectory)
    let snapshot = RenderedDocument(
        document, width: 400, style: RenderStyle(), scrollableTables: false, preparation: nil, readerImages: cache)
    let regions = snapshot.readerImageRegions(in: CGRect(origin: .zero, size: snapshot.size))
    #expect(regions.count == 2)
    let badge = try #require(regions.first)
    let small = try #require(regions.last)
    #expect(await snapshot.prepareReaderImage(badge))
    #expect(await snapshot.prepareReaderImage(small))
    #expect(cache.bitmap(for: badge.request.key) == nil)
    #expect(await snapshot.prepareReaderImage(badge))
    #expect(snapshot.readerImageRegions(in: CGRect(origin: .zero, size: snapshot.size)) == regions)
}

@Test func svgDecodeRejectsOversizeAndMalformedImages() {
    for (width, height) in [(1_000_000_000, 1_000_000_000), (2731, 20), (2200, 2200), (0, 10)] {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(width)" height="\#(height)"/>"#
        #expect(DocumentImageStore.decode(Data(svg.utf8)) == nil)
    }
    let broken = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><g></svg>"#
    #expect(DocumentImageStore.decode(Data(broken.utf8)) == nil)
}
