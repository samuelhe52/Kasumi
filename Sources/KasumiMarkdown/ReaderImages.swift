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
        case provider(SVGImageDecoder.Pixels)
    }

    struct Key: Hashable, Sendable {
        let revision: String
        let rasterization: Rasterization
        let scope: UUID?
    }

    static let maximumPixels: CGFloat = 4_000_000

    let source: ReaderImageSource
    let size: CGSize
    let rasterization: Rasterization
    let scope: UUID?
    var key: Key { Key(revision: source.revision, rasterization: rasterization, scope: scope) }

    init?(source: ReaderImageSource, maximumWidth: CGFloat, width: CGFloat?, height: CGFloat?, scale: CGFloat) {
        let size = DocumentImage.fittedSize(source.info.size, to: maximumWidth, width: width, height: height)
        guard size.width > 0, size.height > 0 else { return nil }
        self.source = source
        self.size = size
        scope = nil
        // The reader needs screen pixels. Bound even extreme authored sizes
        // and keep an individual RGBA raster well inside the working cache.
        let maxPixels = Self.maximumPixels
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

    init?(url: URL, scope: UUID, intrinsicSize: CGSize, size: CGSize, scale: CGFloat) {
        let longest = max(size.width, size.height)
        let shortest = min(size.width, size.height)
        guard longest.isFinite, shortest.isFinite, shortest > 0 else { return nil }
        let limit = min(8192, sqrt(Self.maximumPixels / (shortest / longest)))
        let fittedScale = min(scale, limit / longest)
        // Round to device pixels without crossing either cap.
        let width = max(1, min(8192, ceil(size.width * fittedScale)))
        let height = max(1, min(8192, ceil(size.height * fittedScale), floor(Self.maximumPixels / width)))
        guard let pixels = SVGImageDecoder.Pixels(size: CGSize(width: width, height: height), scale: 1) else {
            return nil
        }
        source = ReaderImageSource(
            url: url, revision: url.absoluteString, info: DocumentImageStore.Metadata(size: intrinsicSize, isSVG: false))
        self.scope = scope
        self.size = size
        rasterization = .provider(pixels)
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
    package var isRemote: Bool { DocumentImageStore.isRemote(request.source.url) }

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

    private static let placeholderSize = CGSize(width: 96, height: 54)
    let displayScale: CGFloat
    private let store: DocumentImageStore
    private let scope: ReaderImageResources?
    private let rasters: ReaderImageRasterCache
    // Freeze remote dimensions for the reflow generation, including widths not
    // yet laid out. Text preparation must not mix pre/post-resolution geometry.
    private let metadata: [URL: ReaderImageResources.Metadata]
    private let geometryLock = NSLock()
    // URLs whose layout depends on the resolved image, so a resolution can tell
    // whether it changes geometry. A URL is present when some occurrence takes its
    // aspect ratio from the image. The value is the widest space given to an
    // occurrence with neither width nor height authored (0 if none), because only
    // those also take their width from the image. The pass that sizes table
    // columns counts too.
    private var intrinsicWidthLimits: [URL: CGFloat] = [:]

    init(
        displayScale: CGFloat, store: DocumentImageStore = .shared, byteLimit: Int = 64 * 1024 * 1024,
        resources: ReaderImageResources? = nil
    ) {
        self.displayScale = displayScale
        self.store = store
        scope = resources
        rasters = resources?.rasters ?? ReaderImageRasterCache(byteLimit: byteLimit)
        metadata = resources?.snapshot() ?? [:]
    }

    func request(
        for source: String, baseURL: URL?, maximumWidth: CGFloat, width: CGFloat?, height: CGFloat?
    ) -> ReaderImageRequest? {
        guard let url = DocumentImageStore.resourceURL(source, baseURL: baseURL) else { return nil }
        if let scope, DocumentImageStore.isRemote(url) {
            if scope.hasProvider, width == nil || height == nil {
                let limit = width == nil && height == nil ? maximumWidth : 0
                geometryLock.withLock {
                    intrinsicWidthLimits[url] = max(intrinsicWidthLimits[url] ?? 0, limit)
                }
            }
            let intrinsic = intrinsicSize(for: url)
            let size = DocumentImage.fittedSize(intrinsic, to: maximumWidth, width: width, height: height)
            return ReaderImageRequest(url: url, scope: scope.id, intrinsicSize: intrinsic, size: size, scale: displayScale)
        }
        guard let source = store.readerSource(for: url) else { return nil }
        return ReaderImageRequest(
            source: source, maximumWidth: maximumWidth, width: width, height: height, scale: displayScale)
    }

    func bitmap(for key: ReaderImageRequest.Key) -> CGImage? { rasters.bitmap(for: key) }

    func hasResult(for key: ReaderImageRequest.Key) -> Bool { rasters.hasResult(for: key) }

    func hasResult(for request: ReaderImageRequest) -> Bool {
        if case .provider = request.rasterization {
            guard let scope, request.scope == scope.id, scope.hasProvider else { return true }
            let url = request.source.url
            guard let metadata = scope.status(for: url) else { return false }
            if let size = metadata.size, needsGeometry(for: url, size: size) { return false }
            if metadata.unavailable { return true }
        }
        return hasResult(for: request.key)
    }

    func load(_ request: ReaderImageRequest) async -> Bool { await prepare(request) == .pixels }

    func prepare(_ request: ReaderImageRequest) async -> ReaderResourceUpdate {
        guard !Task.isCancelled, !hasResult(for: request) else { return .none }
        if case .provider(let pixels) = request.rasterization {
            guard let scope, request.scope == scope.id else { return .none }
            let url = request.source.url
            if let size = scope.status(for: url)?.size, needsGeometry(for: url, size: size) {
                return .geometry
            }
            guard let resource = await scope.resolve(url), !Task.isCancelled else { return .none }
            if needsGeometry(for: url, size: resource.intrinsicSize) { return .geometry }
            let size = CGSize(width: pixels.width, height: pixels.height)
            return await rasters.load(request.key) {
                try? await resource.rasterize(size)
            } ? .pixels : .none
        }
        return await rasters.load(request.key) { await self.store.readerBitmap(request) } ? .pixels : .none
    }

    private func intrinsicSize(for url: URL) -> CGSize { metadata[url]?.size ?? Self.placeholderSize }

    private func needsGeometry(for url: URL, size: CGSize) -> Bool {
        let original = intrinsicSize(for: url)
        guard size != original, let limit = geometryLock.withLock({ intrinsicWidthLimits[url] }) else { return false }
        return size.height / size.width != original.height / original.width
            || min(size.width, limit) != min(original.width, limit)
    }
}

package enum ReaderResourceUpdate: Sendable, Equatable {
    case none, pixels, geometry
}

/// Owned by one reader file/provider/revision. Same-file edits and reflows
/// reuse remote metadata and pixels, but each layout captures fresh geometry.
package final class ReaderImageResources: Sendable {
    struct Metadata: Sendable {
        let size: CGSize?
        let unavailable: Bool
    }

    private enum Resolution: Sendable {
        case available(MarkdownImageResource)
        case unavailable
    }

    let id = UUID()
    let rasters = ReaderImageRasterCache(byteLimit: 64 * 1024 * 1024, separatesLocalWork: true)
    private let configuration: MarkdownRemoteImages?
    private let metadata = ReaderImageLRU<URL, Metadata>(countLimit: 2048)
    private let resources = ReaderImageLRU<URL, MarkdownImageResource>(
        countLimit: 256, byteLimit: 2 * DocumentImageStore.maximumBytes)
    private let work = ReaderImageWork<URL, Resolution>()

    package init(_ configuration: MarkdownRemoteImages?) { self.configuration = configuration }

    var hasProvider: Bool { configuration != nil }
    func snapshot() -> [URL: Metadata] { metadata.snapshot() }
    func status(for url: URL) -> Metadata? { metadata.value(for: url) }

    func resolve(_ url: URL) async -> MarkdownImageResource? {
        guard let provider = configuration?.provider else { return nil }
        let result = await work.run(url) {
            let status = self.metadata.touch(url)
            if status?.unavailable == true { return .unavailable }
            if status != nil, let resource = self.resources.touch(url) { return .available(resource) }
            return nil
        } operation: {
            guard !Task.isCancelled, let resource = try? await provider(url) else { return .unavailable }
            let size = resource.intrinsicSize
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
                max(size.width, size.height) <= 40_000_000,
                (size.height / size.width).isFinite, (size.width / size.height).isFinite
            else { return .unavailable }
            return .available(resource)
        } publish: { resolution in
            switch resolution {
            case .available(let resource):
                self.resources.insert(resource, for: url, cost: resource.retainedBytes)
                self.metadata.insert(Metadata(size: resource.intrinsicSize, unavailable: false), for: url)
            case .unavailable:
                let size = self.metadata.value(for: url)?.size
                self.metadata.insert(Metadata(size: size, unavailable: true), for: url)
            }
        }
        switch result {
        case .cached(.available(let resource)), .loaded(.available(let resource)): return resource
        default: return nil
        }
    }
}

final class ReaderImageRasterCache: Sendable {
    private struct Entry: Sendable {
        let bitmap: CGImage?
    }
    private let entries: ReaderImageLRU<ReaderImageRequest.Key, Entry>
    private let work = ReaderImageWork<ReaderImageRequest.Key, Entry>()
    private let localWork: ReaderImageWork<ReaderImageRequest.Key, Entry>?
    private let byteLimit: Int

    init(byteLimit: Int, separatesLocalWork: Bool = false) {
        self.byteLimit = byteLimit
        entries = ReaderImageLRU(countLimit: 256, byteLimit: byteLimit)
        localWork = separatesLocalWork ? ReaderImageWork(limit: 1) : nil
    }

    func bitmap(for key: ReaderImageRequest.Key) -> CGImage? { entries.value(for: key)?.bitmap }
    func hasResult(for key: ReaderImageRequest.Key) -> Bool { entries.touch(key) != nil }

    func load(
        _ key: ReaderImageRequest.Key, operation: @escaping @Sendable () async -> CGImage?
    ) async -> Bool {
        let work = key.scope == nil ? localWork ?? self.work : self.work
        let result = await work.run(key) {
            self.entries.touch(key)
        } operation: {
            guard !Task.isCancelled, let bitmap = await operation(),
                bitmap.width > 0, bitmap.height > 0, bitmap.width <= 8192, bitmap.height <= 8192
            else { return Entry(bitmap: nil) }
            if case .provider = key.rasterization,
                bitmap.width * bitmap.height > Int(ReaderImageRequest.maximumPixels)
            { return Entry(bitmap: nil) }
            let (bytes, overflow) = bitmap.bytesPerRow.multipliedReportingOverflow(by: bitmap.height)
            return Entry(bitmap: !overflow && bytes <= self.byteLimit ? bitmap : nil)
        } publish: { entry in
            let cost = entry.bitmap.map { $0.bytesPerRow * $0.height } ?? 0
            self.entries.insert(entry, for: key, cost: cost)
        }
        if case .loaded(let entry) = result { return !Task.isCancelled && entry.bitmap != nil }
        return false
    }
}
