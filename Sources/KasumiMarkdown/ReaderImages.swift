import CoreGraphics
import Foundation

struct ReaderImageSource: Sendable {
    let url: URL
    let revision: String
    let info: DocumentImageStore.Metadata
}

struct ReaderImageRequest: Sendable {
    enum Rasterization: Hashable, Sendable {
        case raster(Int)
        case svg(SVGImageDecoder.Pixels)
    }

    struct Key: Hashable, Sendable {
        let revision: String
        let rasterization: Rasterization
    }

    let source: ReaderImageSource
    let size: CGSize
    let rasterization: Rasterization
    var key: Key { Key(revision: source.revision, rasterization: rasterization) }

    init?(source: ReaderImageSource, maximumWidth: CGFloat, width: CGFloat?, height: CGFloat?, scale: CGFloat) {
        let size = DocumentImage.fittedSize(source.info.size, to: maximumWidth, width: width, height: height)
        guard size.width > 0, size.height > 0 else { return nil }
        self.source = source
        self.size = size
        // The reader needs screen pixels. Bound even extreme authored sizes
        // and keep an individual RGBA raster well inside the working cache.
        let maxPixels: CGFloat = 4_000_000
        let longest = max(size.width, size.height)
        let longestLimit = min(8192, sqrt(maxPixels / (min(size.width, size.height) / longest)))
        let fittedScale = min(scale, longestLimit / longest)
        if source.info.isSVG {
            guard let pixels = SVGImageDecoder.Pixels(size: size, scale: fittedScale) else { return nil }
            rasterization = .svg(pixels)
        } else {
            let intrinsic = source.info.size
            let aspect = min(intrinsic.width, intrinsic.height) / max(intrinsic.width, intrinsic.height)
            // ImageIO preserves the source aspect even when HTML stretches the
            // logical rectangle. Bound the thumbnail using its own aspect.
            let maxDimension = min(longest * fittedScale, sqrt(maxPixels / aspect))
            let intrinsicLongest = max(intrinsic.width, intrinsic.height)
            rasterization = .raster(max(1, Int(ceil(min(maxDimension, intrinsicLongest)))))
        }
    }
}

struct PlacedReaderImage: Sendable {
    let rect: CGRect
    let request: ReaderImageRequest
    var tableIndex: Int?
}

/// An image occurrence in a viewport. Table rectangles use table-content
/// coordinates to address the table's own tiled layer.
public struct ReaderImageRegion: Sendable, Equatable {
    public let rect: CGRect
    public let tableID: Int?
    let request: ReaderImageRequest

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rect == rhs.rect && lhs.tableID == rhs.tableID && lhs.request.key == rhs.request.key
    }

    /// Multiple placements can share one decoded raster.
    public func sharesRaster(with other: ReaderImageRegion) -> Bool { request.key == other.request.key }
}

/// Snapshot attachments keep only a request and a reference to this bounded
/// cache. Drawing reads already available pixels without I/O or decoding.
final class ReaderImageCache: Equatable, @unchecked Sendable {
    static func == (lhs: ReaderImageCache, rhs: ReaderImageCache) -> Bool { lhs === rhs }

    private struct Entry {
        let bitmap: CGImage?
        var cost: Int { bitmap.map { $0.bytesPerRow * $0.height } ?? 0 }
    }

    let displayScale: CGFloat
    private let store: DocumentImageStore
    private let byteLimit: Int
    private let lock = NSLock()
    private var entries: [ReaderImageRequest.Key: Entry] = [:]
    private var recency: [ReaderImageRequest.Key] = []
    private var totalCost = 0

    init(displayScale: CGFloat, store: DocumentImageStore = .shared, byteLimit: Int = 64 * 1024 * 1024) {
        self.displayScale = displayScale
        self.store = store
        self.byteLimit = byteLimit
    }

    func request(
        for source: String, baseURL: URL?, maximumWidth: CGFloat, width: CGFloat?, height: CGFloat?
    ) -> ReaderImageRequest? {
        guard let source = store.readerSource(for: source, baseURL: baseURL) else { return nil }
        return ReaderImageRequest(
            source: source, maximumWidth: maximumWidth, width: width, height: height, scale: displayScale)
    }

    func bitmap(for key: ReaderImageRequest.Key) -> CGImage? {
        lock.withLock { entries[key]?.bitmap }
    }

    /// Checks residency and marks requested images as recently used.
    func hasResult(for key: ReaderImageRequest.Key) -> Bool {
        lock.withLock {
            guard entries[key] != nil, let index = recency.firstIndex(of: key) else { return false }
            recency.append(recency.remove(at: index))
            return true
        }
    }

    /// The host serializes and cancels work as its viewport changes.
    func load(_ request: ReaderImageRequest) async -> Bool {
        guard !Task.isCancelled, !hasResult(for: request.key) else { return false }
        let bitmap = await store.readerBitmap(request)
        guard !Task.isCancelled else { return false }
        return lock.withLock {
            guard entries[request.key] == nil else { return false }
            let decoded = Entry(bitmap: bitmap)
            let entry = decoded.cost <= byteLimit ? decoded : Entry(bitmap: nil)
            while totalCost + entry.cost > byteLimit || recency.count >= 256 {
                totalCost -= entries.removeValue(forKey: recency.removeFirst())!.cost
            }
            entries[request.key] = entry
            recency.append(request.key)
            totalCost += entry.cost
            return entry.bitmap != nil
        }
    }
}
