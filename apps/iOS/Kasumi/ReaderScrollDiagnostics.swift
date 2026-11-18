import UIKit

/// Opt-in measurement only. No display link, samples or files exist unless the
/// test launcher supplies KASUMI_SCROLL_DIAGNOSTICS. Callback timing is a main-
/// thread scheduling proxy; it is not proof of GPU presentation or dropped frames.
@MainActor final class ReaderScrollDiagnostics: NSObject {
    struct Viewport {
        let top: CGFloat
        let width: CGFloat
        let height: CGFloat
        let active: Bool
        let measured: Bool
        let fullyMeasured: Bool
    }
    private struct Sample: Codable {
        let time: Double
        let callbackGapMS: Double?
        let expectedIntervalMS: Double
        let active: Bool
        let measured: Bool
        let fullyMeasured: Bool
        let top: Double
        let width: Double
        let height: Double
    }
    private let run: String
    private let viewport: () -> Viewport?
    private var link: CADisplayLink?
    private var samples: [Sample] = []
    private var previousTime: Double?
    private let start = CACurrentMediaTime()
    private var finished = false

    static func make(viewport: @escaping () -> Viewport?) -> ReaderScrollDiagnostics? {
        guard let run = ProcessInfo.processInfo.environment["KASUMI_SCROLL_DIAGNOSTICS"],
            !run.isEmpty, run.count <= 100,
            run.unicodeScalars.allSatisfy({
                CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0)
            })
        else { return nil }
        return ReaderScrollDiagnostics(run: run, viewport: viewport)
    }

    private init(run: String, viewport: @escaping () -> Viewport?) {
        self.run = run
        self.viewport = viewport
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard !finished, samples.count < 20000 else {
            finish()
            return
        }
        let now = CACurrentMediaTime()
        defer { previousTime = now }
        guard let value = viewport() else { return }
        samples.append(
            Sample(
                time: now - start, callbackGapMS: previousTime.map { (now - $0) * 1000 },
                expectedIntervalMS: max(0, link.targetTimestamp - link.timestamp) * 1000,
                active: value.active, measured: value.measured, fullyMeasured: value.fullyMeasured,
                top: Double(value.top),
                width: Double(value.width), height: Double(value.height)))
    }

    func finish() {
        guard !finished else { return }
        finished = true
        link?.invalidate()
        link = nil
        guard !samples.isEmpty else { return }
        do {
            let root = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            .appendingPathComponent(".kasumi-scroll-diagnostics", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("\(run)-\(UUID().uuidString).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(samples).write(to: url, options: .atomic)
        } catch {
            print("Scroll diagnostics could not be written: \(error.localizedDescription)")
        }
    }
}
