#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import CoreText
import Foundation
import ImageIO

/// Immutable decoded pixels shared by layout passes and asynchronous loading.
public final class DocumentImage: NSObject, @unchecked Sendable {
    public let bitmap: CGImage
    /// Oriented source dimensions in document points. Small images are not enlarged.
    public let size: CGSize
    init(bitmap: CGImage, size: CGSize) { self.bitmap = bitmap; self.size = size }

    public func fitted(to maximumWidth: CGFloat) -> CGSize {
        guard maximumWidth.isFinite, maximumWidth > 0, size.width > 0, size.height > 0 else { return .zero }
        let scale = min(1, maximumWidth / size.width)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// Layout reads local/data resources and already decoded cache entries only.
/// HTTP loading is explicitly asynchronous, bounded, and never starts in draw().
public final class DocumentImageStore: @unchecked Sendable {
    public static let shared = DocumentImageStore()
    public static let maximumBytes = 20 * 1024 * 1024
    private let cache = NSCache<NSString, DocumentImage>()
    private let session: URLSession

    public convenience init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        self.init(session: URLSession(configuration: configuration))
    }
    init(session: URLSession) {
        cache.totalCostLimit = 80 * 1024 * 1024
        self.session = session
    }
    deinit { session.invalidateAndCancel() }

    public static func resourceURL(_ source: String, baseURL: URL?) -> URL? {
        guard !source.isEmpty else { return nil }
        if baseURL == nil, source.hasPrefix("/") { return URL(fileURLWithPath: source.removingPercentEncoding ?? source) }
        let directory = baseURL?.appendingPathComponent("", isDirectory: true)
        guard let url = URL(string: source, relativeTo: directory)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["file", "data", "http", "https"].contains(scheme) else { return nil }
        if scheme == "file", let host = url.host, !host.isEmpty, host != "localhost" { return nil }
        return url
    }

    public func image(for source: String, baseURL: URL?) -> DocumentImage? {
        guard let url = Self.resourceURL(source, baseURL: baseURL) else { return nil }
        let key = cacheKey(url)
        if let image = cache.object(forKey: key) { return image }
        let data: Data?
        if url.isFileURL {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let count = values.fileSize,
                  count > 0, count <= Self.maximumBytes else { return nil }
            data = try? Data(contentsOf: url, options: .mappedIfSafe)
        } else if url.scheme?.lowercased() == "data" { data = Self.dataURL(url.absoluteString) }
        else { return nil }
        guard let data, let image = Self.decode(data) else { return nil }
        store(image, key: key)
        return image
    }

    /// Preload remote resources before export, or redraw a reader when this
    /// returns true. Up to four requests run concurrently. Relative local files
    /// need no preload; they are decoded lazily on the first layout pass.
    @discardableResult public func preload(_ document: ParsedDocument) async -> Bool {
        var sources = Set<URL>()
        for block in document.blocks {
            let runs = block.runs + block.rows.flatMap { $0.flatMap { $0 } }
            for run in runs {
                guard let source = run.imageSource,
                      let url = Self.resourceURL(source, baseURL: document.baseURL),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      cache.object(forKey: cacheKey(url)) == nil else { continue }
                sources.insert(url)
            }
        }
        let urls = Array(sources)
        return await withTaskGroup(of: Bool.self) { group in
            var next = 0, changed = false
            func enqueue() {
                guard next < urls.count else { return }
                let url = urls[next]; next += 1
                group.addTask { await self.fetch(url) }
            }
            for _ in 0..<min(4, urls.count) { enqueue() }
            while let loaded = await group.next() { changed = loaded || changed; enqueue() }
            return changed
        }
    }

    private func fetch(_ url: URL) async -> Bool {
        let key = cacheKey(url)
        if cache.object(forKey: key) != nil { return false }
        do {
            let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  response.expectedContentLength <= Int64(Self.maximumBytes) else { return false }
            var data = Data()
            if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
            for try await byte in bytes {
                guard !Task.isCancelled, data.count < Self.maximumBytes else { return false }
                data.append(byte)
            }
            guard let image = Self.decode(data) else { return false }
            store(image, key: key)
            return true
        } catch { return false }
    }

    private func store(_ image: DocumentImage, key: NSString) {
        cache.setObject(image, forKey: key, cost: image.bitmap.bytesPerRow * image.bitmap.height)
    }
    private func cacheKey(_ url: URL) -> NSString {
        guard url.isFileURL, let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return url.absoluteString as NSString }
        return "\(url.absoluteString)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)" as NSString
    }

    static func decode(_ data: Data) -> DocumentImage? {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0, width * height <= 40_000_000 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(8192, max(width, height)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let size = (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        return DocumentImage(bitmap: bitmap, size: size)
    }

    private static func dataURL(_ source: String) -> Data? {
        guard source.utf8.count <= maximumBytes * 3 + 1024, let comma = source.firstIndex(of: ",") else { return nil }
        let header = source[..<comma].lowercased()
        let base64 = header.hasSuffix(";base64")
        let maximumPayload = base64 ? (maximumBytes + 2) / 3 * 4 : maximumBytes
        let payload = Array(source[source.index(after: comma)...].utf8)
        var decoded = Data(), cursor = 0
        func hex(_ byte: UInt8) -> UInt8? {
            switch byte { case 48...57: return byte - 48; case 65...70: return byte - 55; case 97...102: return byte - 87; default: return nil }
        }
        while cursor < payload.count {
            guard decoded.count < maximumPayload else { return nil }
            if payload[cursor] == 37 {
                guard cursor + 2 < payload.count, let high = hex(payload[cursor + 1]), let low = hex(payload[cursor + 2]) else { return nil }
                decoded.append(high * 16 + low); cursor += 3
            } else { decoded.append(payload[cursor]); cursor += 1 }
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
    let image: DocumentImage
    let size: CGSize
    let altText: String
    init(image: DocumentImage, maximumWidth: CGFloat, altText: String) {
        self.image = image; size = image.fitted(to: maximumWidth); self.altText = altText
    }
    func attributed(link: String? = nil) -> NSAttributedString {
        let pointer = Unmanaged.passRetained(self).toOpaque()
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: {
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
        context.interpolationQuality = .high
        context.draw(image.bitmap, in: CGRect(origin: .zero, size: size))
    }
}
