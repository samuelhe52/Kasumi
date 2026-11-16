import Foundation

/// Main-actor-owned scheduling state. A width change replaces only the pending
/// request; synchronous typesetting already in flight is allowed to finish.
struct ReaderReflowState {
    struct Request: Equatable, Sendable {
        let generation: UUID
        let width: CGFloat
    }

    private(set) var desired: Request?
    private(set) var running: Request?
    private(set) var installed: Request?

    var needsLayout: Bool { desired != nil && desired != installed }

    mutating func request(width: CGFloat, generation: UUID) {
        guard width.isFinite, width > 0 else { return }
        desired = Request(generation: generation, width: width)
    }

    mutating func begin() -> Request? {
        guard running == nil, let desired, desired != installed else { return nil }
        running = desired
        return desired
    }

    func accepts(_ request: Request) -> Bool {
        running == request && desired?.generation == request.generation
    }

    /// Finish only after viewport painting, so it shares the same concurrency
    /// bound as typesetting. Intermediate widths may publish; stale styles may not.
    mutating func complete(_ request: Request) -> Bool {
        guard running == request else { return false }
        let publish = accepts(request) && desired != installed
        running = nil
        if publish { installed = request }
        return publish
    }

    mutating func stop() {
        desired = nil
    }
}
