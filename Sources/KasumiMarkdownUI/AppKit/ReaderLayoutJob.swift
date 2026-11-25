#if os(macOS)
import AppKit
import KasumiMarkdown
import os

/// One background layout and viewport paint that a resize can wait for on the
/// main thread. The work never needs the main actor, so the wait can't deadlock.
final class ReaderLayoutJob: Sendable {
    struct Output: Sendable {
        let document: RenderedDocument
        let preview: ReaderViewportBitmap?
        let cost: Duration
    }

    let request: ReaderReflowState.Request
    let start = ContinuousClock.now
    let task: Task<Output, Never>
    private let output: OSAllocatedUnfairLock<Output?>
    private let finished: DispatchSemaphore
    private let painter: Painter

    init(
        _ request: ReaderReflowState.Request, session: DocumentReflowSession, scale: CGFloat,
        colorSpace: CGColorSpace, signposter: OSSignposter
    ) {
        let output = OSAllocatedUnfairLock<Output?>(initialState: nil)
        let finished = DispatchSemaphore(value: 0)
        let painter = Painter(scale: scale, colorSpace: colorSpace, signposter: signposter)
        self.request = request
        self.output = output
        self.finished = finished
        self.painter = painter
        task = Task.detached(priority: .high) {
            let start = ContinuousClock.now
            let interval = signposter.beginInterval("Layout", id: signposter.makeSignpostID())
            let document = await session.render(
                width: request.width, viewportHeight: request.height, anchor: request.anchor)
            signposter.endInterval("Layout", interval)
            let rect = Self.visibleRect(
                of: document, top: request.anchor.flatMap { document.y(for: $0) } ?? 0,
                width: request.width, height: request.height)
            let preview = painter.paint(document, rect: rect)
            let value = Output(document: document, preview: preview, cost: start.duration(to: .now))
            output.withLock { $0 = value }
            finished.signal()
            return value
        }
    }

    var result: Output? { output.withLock { $0 } }

    /// Call at most once per job.
    func wait(for budget: Duration) -> Output? {
        let (seconds, attoseconds) = budget.components
        let nanoseconds = Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
        guard finished.wait(timeout: .now() + .nanoseconds(nanoseconds)) == .success else { return nil }
        return result
    }

    func paint(_ document: RenderedDocument, rect: CGRect) async -> ReaderViewportBitmap? {
        let painter = painter
        return await Task.detached(priority: .userInitiated) { painter.paint(document, rect: rect) }.value
    }

    static func visibleRect(of document: RenderedDocument, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: 0, y: max(0, min(max(0, document.size.height - height), top)), width: width, height: height)
            .intersection(CGRect(origin: .zero, size: document.size))
    }

    private struct Painter: Sendable {
        let scale: CGFloat
        let colorSpace: CGColorSpace
        let signposter: OSSignposter

        func paint(_ document: RenderedDocument, rect: CGRect) -> ReaderViewportBitmap? {
            let interval = signposter.beginInterval("ViewportPaint", id: signposter.makeSignpostID())
            defer { signposter.endInterval("ViewportPaint", interval) }
            return ReaderViewportBitmap.paint(
                document, rect: rect, scale: scale, colorSpace: colorSpace, excludingScrollableTables: true)
        }
    }
}
#endif
