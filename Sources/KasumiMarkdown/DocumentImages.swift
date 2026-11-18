import CoreText
import Foundation
import ImageIO

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Immutable decoded pixels shared by layout passes and asynchronous loading.
package final class DocumentImage: NSObject, @unchecked Sendable {
    package let bitmap: CGImage
    /// Oriented source dimensions in document points. Small images are not enlarged.
    let size: CGSize
    let isSVG: Bool
    init(bitmap: CGImage, size: CGSize, isSVG: Bool = false) {
        self.bitmap = bitmap
        self.size = size
        self.isSVG = isSVG
    }

    func fitted(to maximumWidth: CGFloat, width: CGFloat? = nil, height: CGFloat? = nil) -> CGSize {
        Self.fittedSize(size, to: maximumWidth, width: width, height: height)
    }

    static func fittedSize(_ size: CGSize, to maximumWidth: CGFloat, width: CGFloat?, height: CGFloat?) -> CGSize {
        guard maximumWidth.isFinite, maximumWidth > 0, size.width > 0, size.height > 0 else { return .zero }
        if let width, let height {
            let fittedWidth = min(width, maximumWidth)
            let fittedHeight = height * (fittedWidth / width)
            return fittedHeight.isFinite && fittedHeight > 0
                ? CGSize(width: fittedWidth, height: fittedHeight) : .zero
        }
        let requestedScale = width.map { $0 / size.width } ?? height.map { $0 / size.height } ?? 1
        let scale = min(requestedScale, maximumWidth / size.width)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return fitted.width.isFinite && fitted.height.isFinite ? fitted : .zero
    }
}

/// Layout reads local/data resources and cached remote resources only.
/// HTTP loading is explicitly asynchronous, bounded, and never starts in draw().
package final class DocumentImageStore: @unchecked Sendable {
    struct Metadata: Sendable {
        let size: CGSize
        let isSVG: Bool
    }

    private final class MetadataEntry {
        let value: Metadata?
        init(_ value: Metadata?) { self.value = value }
    }

    static let shared = DocumentImageStore()
    static let maximumBytes = 20 * 1024 * 1024
    private static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }
    private let cache = NSCache<NSString, DocumentImage>()
    private let metadata = NSCache<NSString, MetadataEntry>()
    private let remoteData = NSCache<NSString, NSData>()
    private let session: URLSession

    convenience init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        self.init(session: URLSession(configuration: configuration))
    }
    init(session: URLSession) {
        cache.totalCostLimit = 80 * 1024 * 1024
        metadata.countLimit = 2048
        remoteData.totalCostLimit = 2 * Self.maximumBytes
        self.session = session
    }
    deinit { session.invalidateAndCancel() }

    static func resourceURL(_ source: String, baseURL: URL?) -> URL? {
        guard !source.isEmpty else { return nil }
        if baseURL == nil, source.hasPrefix("/") {
            return URL(fileURLWithPath: source.removingPercentEncoding ?? source)
        }
        let directory = baseURL?.appendingPathComponent("", isDirectory: true)
        guard let url = URL(string: source, relativeTo: directory)?.absoluteURL,
            let scheme = url.scheme?.lowercased(), ["file", "data", "http", "https"].contains(scheme)
        else { return nil }
        if scheme == "file", let host = url.host, !host.isEmpty, host != "localhost" { return nil }
        return url
    }

    func image(for source: String, baseURL: URL?) -> DocumentImage? {
        guard let url = Self.resourceURL(source, baseURL: baseURL) else { return nil }
        let key = cacheKey(url)
        if let image = cache.object(forKey: key) { return image }
        guard let data = resourceData(url, key: key), let image = Self.decode(data) else { return nil }
        store(image, key: key)
        return image
    }

    func readerSource(for source: String, baseURL: URL?) -> ReaderImageSource? {
        guard let url = Self.resourceURL(source, baseURL: baseURL) else { return nil }
        let key = cacheKey(url)
        let info: Metadata?
        if let entry = metadata.object(forKey: key) {
            info = entry.value
        } else if let image = cache.object(forKey: key) {
            info = Metadata(size: image.size, isSVG: image.isSVG)
        } else {
            // ImageIO can inspect a local raster directly, without loading the
            // file into a Data buffer or asking for a pixel representation.
            if url.isFileURL, Self.validFileSize(url),
                let source = CGImageSourceCreateWithURL(url as CFURL, Self.sourceOptions),
                let size = Self.rasterSize(source)
            {
                info = Metadata(size: size, isSVG: false)
            } else {
                info = resourceData(url, key: key).flatMap(Self.inspect)
            }
            // Missing remote data can arrive after this layout.
            if info != nil || url.isFileURL || url.scheme == "data" {
                metadata.setObject(MetadataEntry(info), forKey: key)
            }
        }
        return info.map { ReaderImageSource(url: url, revision: key as String, info: $0) }
    }

    func readerBitmap(_ request: ReaderImageRequest) async -> CGImage? {
        let url = request.source.url
        let key = request.source.revision as NSString
        let data: Data?
        if let existing = resourceData(url, key: key) {
            data = existing
        } else if Self.isRemote(url) {
            data = await download(url)
            if let data { remoteData.setObject(data as NSData, forKey: key, cost: data.count) }
        } else {
            data = nil
        }
        guard !Task.isCancelled, let data, Self.validByteCount(data.count) else { return nil }
        return autoreleasepool {
            switch request.rasterization {
            case .raster(let maxDimension):
                return Self.decodeRaster(data, maxDimension: maxDimension)?.bitmap
            case .svg(let pixels):
                return SVGImageDecoder.source(data)
                    .flatMap { SVGImageDecoder.rasterize($0, readerPixels: pixels)?.bitmap }
            }
        }
    }

    private static func isRemote(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    private static func validByteCount(_ count: Int) -> Bool { count > 0 && count <= maximumBytes }

    private static func validFileSize(_ url: URL) -> Bool {
        guard let count = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return validByteCount(count)
    }

    private func resourceData(_ url: URL, key: NSString) -> Data? {
        if url.isFileURL {
            guard Self.validFileSize(url) else { return nil }
            return try? Data(contentsOf: url, options: .mappedIfSafe)
        }
        if url.scheme?.lowercased() == "data" { return Self.dataURL(url.absoluteString) }
        return remoteData.object(forKey: key).map { $0 as Data }
    }

    /// The reader warms remote headers and encoded data. Export preloads full
    /// rasters. Both use the same download limits and four-request window.
    @discardableResult func preload(_ document: ParsedDocument, forReader: Bool = false) async -> Bool {
        var sources = Set<URL>()
        for block in document.blocks {
            let runs = block.runs + block.rows.flatMap { $0.flatMap { $0 } }
            for run in runs {
                guard let source = run.imageSource,
                    let url = Self.resourceURL(source, baseURL: document.baseURL),
                    Self.isRemote(url), !hasRemoteResource(cacheKey(url), forReader: forReader)
                else { continue }
                sources.insert(url)
            }
        }
        let urls = Array(sources)
        return await withTaskGroup(of: Bool.self) { group in
            var next = 0
            var changed = false
            func enqueue() {
                guard !Task.isCancelled, next < urls.count else { return }
                let url = urls[next]
                next += 1
                group.addTask { await self.fetch(url, forReader: forReader) }
            }
            for _ in 0..<min(4, urls.count) { enqueue() }
            while let loaded = await group.next() {
                changed = loaded || changed
                enqueue()
            }
            return changed
        }
    }

    private func hasRemoteResource(_ key: NSString, forReader: Bool) -> Bool {
        if forReader { return metadata.object(forKey: key)?.value != nil || cache.object(forKey: key) != nil }
        return cache.object(forKey: key) != nil
    }

    private func fetch(_ url: URL, forReader: Bool) async -> Bool {
        let key = cacheKey(url)
        if hasRemoteResource(key, forReader: forReader) { return false }
        let data: Data?
        if let existing = remoteData.object(forKey: key) {
            data = existing as Data
        } else {
            data = await download(url)
        }
        guard !Task.isCancelled, let data else { return false }
        return autoreleasepool {
            if forReader {
                guard let info = Self.inspect(data) else { return false }
                metadata.setObject(MetadataEntry(info), forKey: key)
                remoteData.setObject(data as NSData, forKey: key, cost: data.count)
            } else {
                guard let image = Self.decode(data) else { return false }
                store(image, key: key)
                // Retain the SVG source for fitted reader requests after export.
                if image.isSVG { remoteData.setObject(data as NSData, forKey: key, cost: data.count) }
            }
            return true
        }
    }

    private func download(_ url: URL) async -> Data? {
        do {
            let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                response.expectedContentLength <= Int64(Self.maximumBytes)
            else { return nil }
            var data = Data()
            if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
            for try await byte in bytes {
                guard !Task.isCancelled, data.count < Self.maximumBytes else { return nil }
                data.append(byte)
            }
            return data
        } catch { return nil }
    }

    private func store(_ image: DocumentImage, key: NSString) {
        cache.setObject(image, forKey: key, cost: image.bitmap.bytesPerRow * image.bitmap.height)
        metadata.setObject(MetadataEntry(Metadata(size: image.size, isSVG: image.isSVG)), forKey: key)
    }

    private func cacheKey(_ url: URL) -> NSString {
        guard url.isFileURL, let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        else { return url.absoluteString as NSString }
        return
            "\(url.absoluteString)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            as NSString
    }

    package static func decode(_ data: Data) -> DocumentImage? {
        guard validByteCount(data.count) else { return nil }
        return decodeRaster(data) ?? SVGImageDecoder.decode(data)
    }

    private static func inspect(_ data: Data) -> Metadata? {
        guard validByteCount(data.count) else { return nil }
        if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            let size = rasterSize(source)
        {
            return Metadata(size: size, isSVG: false)
        }
        return SVGImageDecoder.sourceSize(data).map { Metadata(size: $0, isSVG: true) }
    }

    private static func rasterSize(_ source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            width.isFinite, height.isFinite, width > 0, height > 0, width * height <= 40_000_000
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation)
            ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    private static func decodeRaster(_ data: Data, maxDimension: Int = 8192) -> DocumentImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions), let size = rasterSize(source)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(CGFloat(maxDimension), max(size.width, size.height)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DocumentImage(bitmap: bitmap, size: size)
    }

    private static func dataURL(_ source: String) -> Data? {
        guard source.utf8.count <= maximumBytes * 3 + 1024, let comma = source.firstIndex(of: ",") else { return nil }
        let header = source[..<comma].lowercased()
        let base64 = header.hasSuffix(";base64")
        let maximumPayload = base64 ? (maximumBytes + 2) / 3 * 4 : maximumBytes
        let payload = Array(source[source.index(after: comma)...].utf8)
        var decoded = Data()
        var cursor = 0
        func hex(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: return byte - 48
            case 65...70: return byte - 55
            case 97...102: return byte - 87
            default: return nil
            }
        }
        while cursor < payload.count {
            guard decoded.count < maximumPayload else { return nil }
            if payload[cursor] == 37 {
                guard cursor + 2 < payload.count, let high = hex(payload[cursor + 1]),
                    let low = hex(payload[cursor + 2])
                else { return nil }
                decoded.append(high * 16 + low)
                cursor += 3
            } else {
                decoded.append(payload[cursor])
                cursor += 1
            }
        }
        let data = base64 ? Data(base64Encoded: decoded) : decoded
        guard let data, data.count <= maximumBytes else { return nil }
        return data
    }
}

extension NSAttributedString.Key {
    static let kasumiImage = NSAttributedString.Key("KasumiImageAttachment")
}

final class ImageAttachment: NSObject {
    private let image: DocumentImage?
    let readerRequest: ReaderImageRequest?
    private let readerCache: ReaderImageCache?
    private let placeholder: CGColor?
    let size: CGSize
    let altText: String
    init(image: DocumentImage, maximumWidth: CGFloat, altText: String, width: CGFloat? = nil, height: CGFloat? = nil) {
        self.image = image
        readerRequest = nil
        readerCache = nil
        placeholder = nil
        size = image.fitted(to: maximumWidth, width: width, height: height)
        self.altText = altText
    }
    init(request: ReaderImageRequest, cache: ReaderImageCache, altText: String, placeholder: CGColor?) {
        image = nil
        readerRequest = request
        readerCache = cache
        self.placeholder = placeholder
        size = request.size
        self.altText = altText
    }
    func attributed(link: String? = nil) -> NSAttributedString {
        let pointer = Unmanaged.passRetained(self).toOpaque()
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: {
                Unmanaged<ImageAttachment>.fromOpaque($0).release()
            }, getAscent: { Unmanaged<ImageAttachment>.fromOpaque($0).takeUnretainedValue().size.height },
            getDescent: { _ in 0 },
            getWidth: { Unmanaged<ImageAttachment>.fromOpaque($0).takeUnretainedValue().size.width })
        guard let delegate = CTRunDelegateCreate(&callbacks, pointer) else {
            Unmanaged<ImageAttachment>.fromOpaque(pointer).release()
            return NSAttributedString(string: altText)
        }
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTRunDelegateAttributeName as String): delegate,
            .kasumiImage: self, .kasumiSemanticText: altText, .foregroundColor: PlatformColor.clear
        ]
        if let link { attributes[.link] = link }
        return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
    }
    /// Draw in the local upward-positive baseline coordinates used by CTLine.
    func draw(in context: CGContext) {
        let rect = CGRect(origin: .zero, size: size)
        let bitmap = image?.bitmap ?? readerRequest.flatMap { readerCache?.bitmap(for: $0.key) }
        if let bitmap {
            context.interpolationQuality = .high
            context.draw(bitmap, in: rect)
        } else if let placeholder {
            context.setFillColor(placeholder)
            context.fill(rect)
        }
    }
}
