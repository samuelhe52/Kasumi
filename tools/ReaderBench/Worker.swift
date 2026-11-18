import CoreGraphics
import CryptoKit
import Foundation
import KasumiMarkdown

struct BenchmarkCase {
    let sample: LabSample
    let count: Int
    var id: String { "\(sample == .single ? "single" : sample.rawValue.lowercased())-\(count)" }
    var source: String { sample.markdown(characters: count) }
    static var all: [BenchmarkCase] {
        [LabSample.english, .chinese, .mixed].flatMap { sample in
            [20_000, 50_000, 200_000].map { BenchmarkCase(sample: sample, count: $0) }
        } + [BenchmarkCase(sample: .single, count: 50_000)]
    }
    var manifest: [String: Any] {
        let data = Data(source.utf8)
        return [
            "id": id, "sample": sample.rawValue, "nominalBodyCharacters": count,
            "utf16Units": source.utf16.count, "utf8Bytes": data.count,
            "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "completePreparationEligible": sample != .single
        ]
    }
}

enum BenchError: Error { case invalid(String) }

func milliseconds(_ start: ContinuousClock.Instant) -> Double {
    let elapsed = start.duration(to: .now).components
    return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
}

func hostState() -> [String: Any] {
    let process = ProcessInfo.processInfo
    return ["thermalState": process.thermalState.rawValue, "lowPowerMode": process.isLowPowerModeEnabled]
}

func writeJSON(_ value: Any, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(
        to: url, options: .atomic)
}

struct Worker {
    static let width: CGFloat = 1179, height: CGFloat = 701
    static let widths: [CGFloat] = [1179, 1000, 900, 440]
    let item: BenchmarkCase
    let source: String
    let full: Bool
    var iterations: Int { full ? 50 : 5 }
    var style: RenderStyle { RenderStyle(fontSize: 18, widthLimit: nil) }

    func rect(_ snapshot: RenderedDocument, top: CGFloat = 0, width: CGFloat = width, height: CGFloat = height)
        -> CGRect
    {
        CGRect(x: 0, y: min(max(0, snapshot.size.height - height), max(0, top)), width: width, height: height)
            .intersection(CGRect(origin: .zero, size: snapshot.size))
    }

    func paint(_ snapshot: RenderedDocument, rect: CGRect, scale: CGFloat = 2) throws -> Double {
        guard !rect.isEmpty, !snapshot.needsLayout(in: rect) else { throw BenchError.invalid("uncovered engine paint") }
        return try autoreleasepool {
            let start = ContinuousClock.now
            guard let bitmap = LabPreview.paint(snapshot, rect: rect, scale: scale) else {
                throw BenchError.invalid("bitmap creation failed")
            }
            let elapsed = milliseconds(start)
            withExtendedLifetime(bitmap) {}
            return elapsed
        }
    }

    func prepared(_ session: DocumentReflowSession, width: CGFloat = width) async throws -> (RenderedDocument?, Double)
    {
        let start = ContinuousClock.now
        let snapshot = try await session.prepareForScrolling(width: width)
        let elapsed = milliseconds(start)
        guard (snapshot != nil) == (item.sample != .single), snapshot?.hasEstimatedGeometry != true else {
            throw BenchError.invalid("unexpected preparation eligibility or incomplete result")
        }
        return (snapshot, elapsed)
    }

    func open(warm: Bool, fileStart: ContinuousClock.Instant? = nil) async throws -> [String: Any] {
        // A discarded in-process parse/layout/paint warms library/font/raster initialization.
        // Only this worker's warm mode uses it; cold workers never do.
        if warm { try await warmOpen() }
        let total = ContinuousClock.now
        let parseStart = ContinuousClock.now
        let document = autoreleasepool { MarkdownDocument(markdown: source) }
        let parseMs = milliseconds(parseStart)
        let setupStart = ContinuousClock.now
        let session = DocumentReflowSession(document, style: style)
        let setupMs = milliseconds(setupStart)
        let firstStart = ContinuousClock.now
        let initial = await session.render(width: Self.width, viewportHeight: Self.height)
        let firstMs = milliseconds(firstStart)
        let paintMs = try paint(initial, rect: rect(initial))
        let totalMs = milliseconds(total)
        let fileTotalMs = fileStart.map { milliseconds($0) }
        var timings = [
            "parseMs": parseMs, "sessionSetupMs": setupMs, "firstSnapshotMs": firstMs,
            "firstPaintMs": paintMs, "sourceToFirstBitmapMs": totalMs
        ]
        if let fileTotalMs { timings["fileToFirstBitmapMs"] = fileTotalMs }
        let memory = try BenchmarkMemory.read()
        withExtendedLifetime((document, session, initial)) {}
        return [
            "timings": timings, "memory": memory,
            "semanticUTF16Units": initial.offset(
                from: initial.documentRange.lowerBound, to: initial.documentRange.upperBound)!
        ]
    }

    @inline(never) func warmOpen() async throws {
        let doc = MarkdownDocument(markdown: source)
        let session = DocumentReflowSession(doc, style: style)
        let snapshot = await session.render(width: Self.width, viewportHeight: Self.height)
        _ = try paint(snapshot, rect: rect(snapshot))
        withExtendedLifetime((doc, session, snapshot)) {}
    }

    func resize() async throws -> [String: Any] {
        let document = MarkdownDocument(markdown: source)
        let session = DocumentReflowSession(document, style: style)
        var previous: RenderedDocument? = await session.render(width: 900, viewportHeight: Self.height)
        let origin = previous!.documentRange.lowerBound
        let length = previous!.offset(from: origin, to: previous!.documentRange.upperBound)!
        let anchor = previous!.readingAnchor(at: previous!.position(from: origin, offset: length / 2)!)!
        var samples: [[String: Any]] = []
        // The first complete cycle is explicit warmup, never silently filtered later.
        for cycle in 0..<(full ? 26 : 4) {
            for width in Self.widths {
                let start = ContinuousClock.now
                var next: RenderedDocument? = await session.render(
                    width: width, viewportHeight: Self.height, anchor: anchor)
                let construct = milliseconds(start)
                let visible = rect(next!, top: next!.y(for: anchor) ?? 0, width: width)
                let painting = try paint(next!, rect: visible)
                let releaseStart = ContinuousClock.now
                releaseSnapshot(&previous)
                let dispose = milliseconds(releaseStart)
                previous = next
                releaseSnapshot(&next)
                if cycle > 0 {
                    samples.append([
                        "cycle": cycle, "width": width, "layoutMs": construct,
                        "paintMs": painting, "oldSnapshotReleaseMs": dispose
                    ])
                }
            }
        }
        releaseSnapshot(&previous)
        // Fixed-width refinement has its own session, before complete preparation.
        let movingSession = DocumentReflowSession(document, style: style)
        var current = await movingSession.render(width: Self.width, viewportHeight: Self.height)
        var refinements: [[String: Any]] = []
        for index in 0..<(full ? 100 : 12) {
            let fraction = CGFloat((index * 37) % 101) / 100
            let target = current.readingAnchor(atY: max(0, current.size.height - Self.height) * fraction)
            var start = ContinuousClock.now
            current = await movingSession.render(width: Self.width, viewportHeight: Self.height, anchor: target)
            let moving = milliseconds(start)
            guard !current.needsLayout(in: rect(current, top: current.y(for: target) ?? 0)) else {
                throw BenchError.invalid("uncovered moving-anchor refinement")
            }
            start = ContinuousClock.now
            let same = await movingSession.render(width: Self.width, viewportHeight: Self.height, anchor: target)
            let fixed = milliseconds(start)
            refinements.append([
                "index": index, "anchorFraction": fraction, "movingAnchorMs": moving, "sameWidthMs": fixed
            ])
            withExtendedLifetime(same) {}
        }
        return [
            "widthSamples": samples, "refinementSamples": refinements,
            "warmupCycles": 1, "anchorSemanticOffset": length / 2
        ]
    }

    func afterPrepare() async throws -> [String: Any] {
        let document = MarkdownDocument(markdown: source)
        let session = DocumentReflowSession(document, style: style)
        let initial = await session.render(width: Self.width, viewportHeight: Self.height)
        let (snapshot, prepareMs) = try await prepared(session)
        let start = ContinuousClock.now
        let changed = await session.render(width: 900, viewportHeight: Self.height)
        let elapsed = milliseconds(start)
        _ = try paint(changed, rect: rect(changed, width: 900))
        withExtendedLifetime((initial, snapshot, session)) {}
        return ["prepareMs": prepareMs, "eligible": snapshot != nil, "widthChangeAfterPrepareMs": elapsed]
    }

    // One complete pair per call ensures snapshots/session are released before the next pair.
    @inline(never) func traversal(document: MarkdownDocument, sessionNumber: Int) async throws -> [String: Any] {
        let session = DocumentReflowSession(document, style: style)
        let initial = await session.render(width: Self.width, viewportHeight: Self.height)
        let (prepared, prepareMs) = try await prepared(session)
        let snapshot: RenderedDocument
        if let prepared { snapshot = prepared } else { snapshot = await session.render(width: Self.width) }
        let limit = max(0, snapshot.size.height - Self.height)
        var tops = Array(stride(from: CGFloat(0), through: limit, by: Self.height))
        if tops.last != limit { tops.append(limit) }
        var first: [Double] = []
        var returning: [Double] = []
        for top in tops { first.append(try paint(snapshot, rect: rect(snapshot, top: top))) }
        for top in tops.reversed() { returning.append(try paint(snapshot, rect: rect(snapshot, top: top))) }
        withExtendedLifetime((initial, snapshot, session)) {}
        return [
            "session": sessionNumber, "tops": tops, "firstMs": first, "returnMs": returning,
            "prepareMs": prepareMs, "documentHeight": snapshot.size.height, "eligible": prepared != nil
        ]
    }

    func painting() async throws -> [String: Any] {
        let document = MarkdownDocument(markdown: source)
        var sessions: [[String: Any]] = []
        var count = 0
        let target = full && item.sample != .single ? 1000 : 1
        repeat {
            let pair = try await traversal(document: document, sessionNumber: sessions.count + 1)
            count += (pair["firstMs"] as! [Double]).count
            sessions.append(pair)
        } while count < target
        return ["sessions": sessions, "minimumSamplesPerDirection": target]
    }

    func find() async throws -> [String: Any] {
        let document = MarkdownDocument(markdown: source)
        let session = DocumentReflowSession(document, style: style)
        let initial = await session.render(width: Self.width, viewportHeight: Self.height)
        let (fullSnapshot, _) = try await prepared(session)
        let snapshot: RenderedDocument
        if let fullSnapshot { snapshot = fullSnapshot } else { snapshot = await session.render(width: Self.width) }
        let text = snapshot.text(in: snapshot.documentRange)
        let query = item.sample == .english ? "reader" : "阅读"
        var search = ReaderSearchState()
        var rows: [[String: Any]] = []
        for index in 0..<iterations {
            // Different query forces a miss while retaining the immutable semantic text.
            _ = search.ranges(in: text, matching: "__no_benchmark_match__")
            var start = ContinuousClock.now
            let numeric = search.ranges(in: text, matching: query)
            let searchMs = milliseconds(start)
            start = ContinuousClock.now
            let retained = search.ranges(in: text, matching: query)
            let hitMs = milliseconds(start)
            guard retained == numeric, !numeric.isEmpty else { throw BenchError.invalid("Find lost matches") }
            start = ContinuousClock.now
            let origin = snapshot.documentRange.lowerBound
            let matches = numeric.map { range in
                KasumiMarkdown.TextRange(
                    snapshot.position(from: origin, offset: range.location)!,
                    snapshot.position(from: origin, offset: NSMaxRange(range))!)
            }
            guard let indexer = ReaderHighlightIndex(matches, in: snapshot) else {
                throw BenchError.invalid("Find index")
            }
            let remapMs = milliseconds(start)
            let top = max(0, snapshot.size.height - Self.height) * CGFloat((index * 37) % 101) / 100
            start = ContinuousClock.now
            let candidates = indexer.candidates(in: snapshot, verticalRange: top..<(top + Self.height))
            var rectangles = 0
            for i in candidates { rectangles += snapshot.selectionRects(for: matches[i]).count }
            let geometryMs = milliseconds(start)
            rows.append([
                "index": index, "searchMissMs": searchMs, "searchHitMs": hitMs, "remapIndexMs": remapMs,
                "viewportGeometryMs": geometryMs, "matches": matches.count,
                "candidates": candidates.count, "rectangles": rectangles
            ])
        }
        let start = ContinuousClock.now
        let giant = snapshot.selectionRects(for: snapshot.documentRange)
        let giantMs = milliseconds(start)
        withExtendedLifetime((initial, snapshot, session, giant)) {}
        return [
            "query": query, "samples": rows, "wholeDocumentSelectionMs": giantMs,
            "wholeDocumentRectangles": giant.count
        ]
    }

    func memory() async throws -> [String: Any] {
        var samples: [[String: Any]] = []
        func sample(_ stage: String, _ idle: Int = 0) throws {
            samples.append(["stage": stage, "idleSeconds": idle, "memory": try BenchmarkMemory.read()])
        }
        let document = MarkdownDocument(markdown: source)
        try sample("afterParse")
        let session = DocumentReflowSession(document, style: style)
        let initial = await session.render(width: 900, viewportHeight: 714)
        try sample("afterFirstViewport")
        let (ready, prepareMs) = try await prepared(session, width: 900)
        guard let snapshot = ready else { throw BenchError.invalid("memory case requires complete prep") }
        _ = try paint(
            snapshot, rect: rect(snapshot, top: snapshot.size.height * 0.55, width: 900, height: 714), scale: 1)
        for stage in ["preparedAndOneViewport", "afterFullTraversal"] {
            if stage == "afterFullTraversal" {
                // Match the earlier retained-memory probe: one reusable 1x context, no retained images.
                try autoreleasepool {
                    guard
                        let context = CGContext(
                            data: nil, width: 900, height: 714, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                    else {
                        throw BenchError.invalid("memory bitmap")
                    }
                    context.translateBy(x: 0, y: 714)
                    context.scaleBy(x: 1, y: -1)
                    for top in stride(from: CGFloat(0), to: snapshot.size.height, by: CGFloat(714)) {
                        let area = CGRect(x: 0, y: top, width: 900, height: 714)
                        guard !snapshot.needsLayout(in: area) else {
                            throw BenchError.invalid("memory traversal uncovered")
                        }
                        autoreleasepool {
                            context.saveGState()
                            context.translateBy(x: 0, y: -top)
                            snapshot.draw(in: context, rect: area)
                            context.restoreGState()
                        }
                    }
                }
            }
            var previous = 0
            for idle in full ? [0, 5, 15] : [0, 1] {
                if idle > previous { try await Task.sleep(for: .seconds(idle - previous)) }
                try sample(stage, idle)
                previous = idle
            }
        }
        withExtendedLifetime((document, session, initial, snapshot)) {}
        return ["samples": samples, "prepareMs": prepareMs, "width": 900, "height": 714, "scale": 1, "repetitions": 1]
    }
}

@inline(never) func releaseSnapshot(_ snapshot: inout RenderedDocument?) { snapshot = nil }
