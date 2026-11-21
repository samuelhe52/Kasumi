import CoreGraphics
import Foundation
import ImageIO

/// Resolve an HTTP(S) image URL. Return `nil` to decline it; the reader will not
/// fall back to another provider or to the export cache.
public typealias MarkdownRemoteImageProvider = @Sendable (URL) async throws -> MarkdownImageResource?

/// How a native Markdown reader loads HTTP(S) images. Without one, the reader makes no network requests.
public struct MarkdownRemoteImages: Sendable {
    /// Shared by copies of this value. Passing a configuration with a different ID clears
    /// the reader's remote image cache, so create one configuration and keep it.
    public let id: UUID
    let provider: MarkdownRemoteImageProvider

    public init(provider: @escaping MarkdownRemoteImageProvider) {
        id = UUID()
        self.provider = provider
    }

    /// Downloads HTTP(S) images with the library's size-limited downloader and decoder.
    public static let http = MarkdownRemoteImages { url in
        guard DocumentImageStore.isRemote(url),
            let data = await DocumentImageStore.shared.download(url, cachePolicy: .reloadIgnoringLocalCacheData)
        else { return nil }
        try Task.checkCancellation()
        return try MarkdownImageResource(encodedData: data)
    }
}

/// Dimensions used for layout and a separate, size-aware source of pixels.
public struct MarkdownImageResource: Sendable {
    public let intrinsicSize: CGSize
    let rasterize: @Sendable (CGSize) async throws -> CGImage?
    let retainedBytes: Int

    /// The reader runs `rasterize` off the main actor with a bounded pixel size
    /// (not points). It can call it again for another size or after eviction.
    /// Supply positive, finite intrinsic dimensions in document points.
    public init(intrinsicSize: CGSize, rasterize: @escaping @Sendable (CGSize) async throws -> CGImage?) {
        self.intrinsicSize = intrinsicSize
        self.rasterize = rasterize
        retainedBytes = 0
    }

    /// Reads the dimensions of a raster or SVG image without decoding it. The data is kept
    /// and decoded at the requested size when the image becomes visible. Throws if the
    /// data is too large or isn't a supported image.
    public init(encodedData data: Data) throws {
        guard DocumentImageStore.validByteCount(data.count) else { throw DecodingError.invalidImageData }
        if let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let size = DocumentImageStore.rasterSize(source)
        {
            intrinsicSize = size
            let aspect = min(size.width, size.height) / max(size.width, size.height)
            let maxDimension = floor(sqrt(ReaderImageRequest.maximumPixels / aspect))
            rasterize = { pixels in
                let longest = min(max(pixels.width, pixels.height), maxDimension)
                return autoreleasepool { DocumentImageStore.decodeRaster(data, maxDimension: Int(longest))?.bitmap }
            }
        } else if let svg = SVGImageDecoder.source(data) {
            intrinsicSize = svg.size
            rasterize = { pixels in
                guard let pixels = SVGImageDecoder.Pixels(size: pixels, scale: 1) else { return nil }
                return autoreleasepool { SVGImageDecoder.rasterize(svg, readerPixels: pixels)?.bitmap }
            }
        } else {
            throw DecodingError.invalidImageData
        }
        retainedBytes = data.count
    }

    private enum DecodingError: Error { case invalidImageData }
}
