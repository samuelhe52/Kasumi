import Foundation
import KasumiMarkdown

/// Main-actor-owned scheduling state. A width change replaces only the pending
/// request; synchronous typesetting already in flight is allowed to finish.
struct ReaderReflowState {
    struct Request: Equatable, Sendable {
        let generation: UUID
        let width: CGFloat
        var anchor: ReadingAnchor? = nil
        var height: CGFloat = 0
    }

    private(set) var desired: Request?
    private(set) var running: Request?
    private(set) var installed: Request?

    var needsLayout: Bool { desired != nil && desired != installed }

    mutating func request(width: CGFloat, generation: UUID, anchor: ReadingAnchor? = nil, height: CGFloat = 0) {
        guard width.isFinite, width > 0 else { return }
        desired = Request(generation: generation, width: width, anchor: anchor, height: height)
    }

    mutating func begin() -> Request? {
        guard running == nil, let desired, desired != installed else { return nil }
        running = desired
        return desired
    }

    func accepts(_ request: Request, coversDesiredViewport: Bool = false) -> Bool {
        guard running == request, let desired, desired.generation == request.generation else { return false }
        return desired.anchor == request.anchor
            || (coversDesiredViewport && desired.width == request.width && desired.height == request.height)
    }

    /// Finish only after viewport painting, so it shares the same concurrency
    /// bound as typesetting. Intermediate widths may publish; stale styles may not.
    mutating func complete(_ request: Request, coversDesiredViewport: Bool = false) -> Bool {
        guard running == request else { return false }
        let publish = accepts(request, coversDesiredViewport: coversDesiredViewport) && desired != installed
        running = nil
        if publish {
            // Coverage was checked against the latest target after prepainting.
            installed =
                coversDesiredViewport && desired?.width == request.width && desired?.height == request.height
                ? desired : request
        }
        return publish
    }

    mutating func stop() {
        desired = nil
    }
}

/// Main-actor-owned anchor policy. Width/style generations freeze a semantic
/// location; a newly installed content revision adopts its current paragraph keys.
struct ReaderReflowAnchorState {
    private(set) var value: ReadingAnchor?
    private var installedRevision: UUID?

    mutating func captureIfNeeded(
        in rendered: RenderedDocument?, atY top: CGFloat, restoring fallback: ReadingAnchor?
    ) {
        guard value == nil else { return }
        value = rendered?.readingAnchor(atY: top) ?? fallback
    }

    mutating func didInstall(_ rendered: RenderedDocument, revision: UUID, atY top: CGFloat) {
        guard installedRevision != revision else { return }
        installedRevision = revision
        value = rendered.readingAnchor(atY: top)
    }

    /// Explicit navigation must use this even when incidental scroll delegate
    /// callbacks are suppressed. Pass the actual top after nonanimated clamping.
    mutating func moved(in rendered: RenderedDocument?, atY top: CGFloat) {
        value = rendered?.readingAnchor(atY: top)
    }

    mutating func navigate(to anchor: ReadingAnchor) { value = anchor }
}
