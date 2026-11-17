#if os(macOS)
import Foundation
import KasumiMarkdown

/// Offscreen native measurements; no event simulation or frame-rate claim.
enum LabBenchmark {
    static func run(to output: URL) async throws {
        func milliseconds(since start: ContinuousClock.Instant) -> Double {
            let elapsed = start.duration(to: .now).components
            return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        var rows: [[String: Any]] = []
        for count in [50_000, 200_000] {
            for sample in [LabSample.chinese, .mixed] {
                let source = sample.markdown(characters: count)
                let parseStart = ContinuousClock.now
                let document = MarkdownDocument(markdown: source)
                let parse = milliseconds(since: parseStart)
                let session = DocumentReflowSession(document, style: RenderStyle(fontSize: 18, widthLimit: nil))
                let firstStart = ContinuousClock.now
                let initial = await session.render(width: 1179, viewportHeight: 701)
                let first = milliseconds(since: firstStart)
                var fixed: [Double] = []
                var changing: [Double] = []
                var scroll: [Double] = []
                var paint: [Double] = []
                var uncovered = 0
                for index in 0..<12 {
                    var start = ContinuousClock.now
                    let resized = await session.render(width: CGFloat([1179, 900, 1000][index % 3]), viewportHeight: 701)
                    changing.append(milliseconds(since: start))
                    start = ContinuousClock.now
                    let same = await session.render(width: 1179, viewportHeight: 701)
                    fixed.append(milliseconds(since: start))
                    let target = initial.readingAnchor(atY: CGFloat(index + 1) * 900)
                    start = ContinuousClock.now
                    let next = await session.render(width: 1179, viewportHeight: 701, anchor: target)
                    scroll.append(milliseconds(since: start))
                    let top = min(max(0, next.size.height - 701), max(0, next.y(for: target) ?? 0))
                    let rect = CGRect(x: 0, y: top, width: 1179, height: 701)
                        .intersection(CGRect(origin: .zero, size: next.size))
                    if next.needsLayout(in: rect) { uncovered += 1 }
                    start = ContinuousClock.now
                    guard LabPreview.paint(next, rect: rect, scale: 2) != nil else {
                        throw CocoaError(.coderReadCorrupt)
                    }
                    paint.append(milliseconds(since: start))
                    withExtendedLifetime((resized, same)) {}
                }
                rows.append([
                    "sample": sample.rawValue, "nominalCharacters": count, "utf16Units": source.utf16.count,
                    "parseMs": parse, "firstSnapshotMs": first,
                    "warmWidthMedianMs": median(changing), "fixedWidthMedianMs": median(fixed),
                    "scrollMedianMs": median(scroll), "scrollMaxMs": scroll.max()!,
                    "viewportPaintMedianMs": median(paint), "uncoveredViewports": uncovered,
                    "samples": scroll.count
                ])
            }
        }
        let result: [String: Any] = [
            "schema": 1, "width": 1179, "viewportHeight": 701, "fontSize": 18, "paintScale": 2,
            "notes": "Headless session construction and SDR Mac viewport painting. Parsing is separate; no GUI load-to-display or FPS measurement. OS caches are not reset.",
            "results": rows
        ]
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        guard uncoveredCount(rows) == 0 else { throw CocoaError(.coderReadCorrupt) }
    }

    private static func uncoveredCount(_ rows: [[String: Any]]) -> Int {
        rows.reduce(0) { $0 + ($1["uncoveredViewports"] as? Int ?? 0) }
    }
}
#endif
