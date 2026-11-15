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
        "![Sample](images/wide%20sample.png)\n\n![Missing](images/no.png)", baseURL: imageFixtureDirectory)
    let style = Typography()
    let layout = DocumentTypesetter.layout(document, width: 400, style: style)
    let imageRect = try #require(layout.imageBounds.first)
    #expect(imageRect == CGRect(x: 40, y: 28, width: 320, height: 160))
    #expect(layout.text.string.contains("Image unavailable: Missing"))
    #expect(layout.textMap.string == "Sample\nMissing\n")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = folder.appendingPathComponent("images.png")
    try DocumentExporter.writeImage(document, style: style, width: 400, scale: 1, to: output)
    let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
    let bitmap = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    func pixel(_ x: Int, _ y: Int) throws -> [UInt8] {
        let crop = try #require(bitmap.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(
            CGContext(
                data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes
    }
    let top = try pixel(200, 48)
    let bottom = try pixel(200, 168)
    let corner = try pixel(48, 36)
    #expect(top[0] > 180 && top[1] < 80)
    #expect(bottom[0] < 80 && bottom[1] > 120)
    #expect(corner[0] > 240 && corner[1] > 240 && corner[2] > 240)
}

fileprivate final class ImageFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "image-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let large = url.lastPathComponent == "oversized.png"
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": large ? "30000000" : "128", "Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !large, let data = try? Data(contentsOf: imageFixtureDirectory.appendingPathComponent("images/tiny.png")) {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func remoteImagesRequireBoundedAsynchronousPreload() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageFixtureProtocol.self]
    let store = DocumentImageStore(session: URLSession(configuration: configuration))
    let url = "https://image-fixture.invalid/tiny.png"
    let document = DocumentParser.parse("![Remote](\(url))")
    #expect(store.image(for: url, baseURL: nil) == nil)
    #expect(await store.preload(document))
    #expect(store.image(for: url, baseURL: nil)?.size == CGSize(width: 32, height: 24))
    #expect(await store.preload(document) == false)
    let oversized = "https://image-fixture.invalid/oversized.png"
    #expect(await store.preload(DocumentParser.parse("![Too big](\(oversized))")) == false)
    #expect(store.image(for: oversized, baseURL: nil) == nil)
}
