import CoreGraphics
import Foundation
import KasumiMarkdown

@main struct ReaderBench {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.count == 4, args[0] == "--svg-decode", let repeats = Int(args[2]), repeats > 0 {
            let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            var samples: [Double] = []
            var pixels = 0
            for _ in 0..<repeats {
                let start = ContinuousClock.now
                samples.append(try autoreleasepool {
                    guard let bitmap = DocumentImageStore.decode(data)?.bitmap else {
                        throw BenchError.invalid("SVG decoding failed")
                    }
                    pixels = bitmap.width * bitmap.height
                    return milliseconds(start)
                })
            }
            try writeJSON(["decodeMs": samples, "pixels": pixels], to: args[3])
            return
        }
        if args.count == 3, args[0] == "--reader-images" {
            try await measureReaderImages(source: URL(fileURLWithPath: args[1]), output: args[2])
            return
        }
        // Repeated parsing provides enough samples for Instruments without
        // mixing font initialization, layout, or bitmap work into the profile.
        if args.count == 4, args[0] == "--profile-parse", let repeats = Int(args[2]), repeats > 0 {
            let source = try String(contentsOfFile: args[1], encoding: .utf8)
            var samples: [Double] = []
            var checksum = 0
            for _ in 0..<repeats {
                try Task.checkCancellation()
                let start = ContinuousClock.now
                checksum += autoreleasepool { MarkdownDocument(markdown: source).outline.count }
                samples.append(milliseconds(start))
            }
            try writeJSON(["parseAndOutlineMs": samples, "checksum": checksum], to: args[3])
            return
        }
        if args.count == 2, args[0] == "--corpus" {
            let root = URL(fileURLWithPath: args[1])
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for item in BenchmarkCase.all {
                try Data(item.source.utf8).write(to: root.appendingPathComponent(item.id + ".md"))
            }
            try writeJSON(["schema": 1, "generator": "LabSample-v1-en_US", "cases": BenchmarkCase.all.map(\.manifest)],
                          to: root.appendingPathComponent("manifest.json").path)
            return
        }
        if args.count == 6, args[0] == "--worker", let item = BenchmarkCase.all.first(where: { $0.id == args[2] }) {
            let phase = args[1], startState = hostState()
            let readStart = ContinuousClock.now
            let data = try Data(contentsOf: URL(fileURLWithPath: args[3]))
            guard let source = String(data: data, encoding: .utf8) else { throw BenchError.invalid("source decoding") }
            let readMs = milliseconds(readStart)
            let worker = Worker(item: item, source: source, full: args[5] == "full")
            let result: [String: Any]
            switch phase {
            case "cold": result = try await worker.open(warm: false, fileStart: readStart)
            case "warm": result = try await worker.open(warm: true)
            case "resize": result = try await worker.resize()
            case "afterPrepare": result = try await worker.afterPrepare()
            case "paint": result = try await worker.painting()
            case "find": result = try await worker.find()
            case "memory": result = try await worker.memory()
            default: throw BenchError.invalid("unknown worker phase")
            }
            // Validate after measurements so generator/locale setup cannot warm cold initialization.
            guard Data(source.utf8) == Data(item.source.utf8) else { throw BenchError.invalid("worker source differs from generator") }
            try writeJSON(["schema": 1, "phase": phase, "case": item.id, "corpus": item.manifest,
                           "valid": true,
                           "geometry": phase == "memory" ? ["width": 900, "height": 714, "fontSize": 18, "scale": 1] : ["width": 1179, "height": 701, "fontSize": 18, "scale": 2],
                           "readDecodeMs": readMs, "hostStart": startState, "hostEnd": hostState(), "result": result], to: args[4])
            return
        }
        throw BenchError.invalid(
            "Usage: --corpus DIR | --worker PHASE CASE SOURCE OUTPUT quick|full | "
                + "--profile-parse SOURCE REPEATS OUTPUT | --svg-decode SOURCE REPEATS OUTPUT | "
                + "--reader-images SOURCE OUTPUT")
    }

    static func measureReaderImages(source: URL, output: String) async throws {
        let start = ContinuousClock.now
        let width: CGFloat = 402
        let height: CGFloat = 874
        let scale: CGFloat = 3
        let data = try Data(contentsOf: source)
        let read = milliseconds(start)
        let document = try MarkdownDocument(
            data: data, fileExtension: source.pathExtension, baseURL: source.deletingLastPathComponent())
        let parsed = milliseconds(start)
        let session = DocumentReflowSession(
            document, style: RenderStyle(fontSize: 18, widthLimit: nil),
            scrollableTables: true, readerDisplayScale: scale)
        let snapshot = await session.render(width: width, viewportHeight: height)
        let layout = milliseconds(start)
        let rect = CGRect(x: 0, y: 0, width: width, height: min(height, snapshot.size.height))
        guard !snapshot.needsLayout(in: rect), let first = LabPreview.paint(snapshot, rect: rect, scale: scale) else {
            throw BenchError.invalid("missing first viewport")
        }
        let firstBitmap = milliseconds(start)
        let initialMemory = try BenchmarkMemory.read()
        let regions = snapshot.readerImageRegions(in: rect)
        var loaded = 0
        for region in regions where await snapshot.prepareReaderImage(region) { loaded += 1 }
        let painted: LabPreview?
        let imageBitmap: Double
        if regions.isEmpty {
            painted = nil
            imageBitmap = firstBitmap
        } else {
            guard let image = LabPreview.paint(snapshot, rect: rect, scale: scale) else {
                throw BenchError.invalid("missing image viewport")
            }
            painted = image
            imageBitmap = milliseconds(start)
        }
        try writeJSON([
            "fileToFirstBitmapMs": firstBitmap, "fileToImageBitmapMs": imageBitmap,
            "readMs": read, "parseMs": parsed - read, "layoutMs": layout - parsed,
            "firstPaintMs": firstBitmap - layout,
            "initialMemory": initialMemory, "finalMemory": try BenchmarkMemory.read(),
            "visibleImageOccurrences": regions.count, "loadedRasters": loaded,
            "documentHeight": snapshot.size.height
        ], to: output)
        withExtendedLifetime((first, painted)) {}
    }

}
