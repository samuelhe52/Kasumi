import Foundation
import Testing

// ReaderReflowState.swift in this test target links to the app's actual source,
// keeping this UI-independent scheduler testable without a simulator or public API.
@Suite struct ReaderReflowTests {
    @Test func continuousResizePublishesAndCoalescesWithOneWorker() throws {
        var state = ReaderReflowState()
        let generation = UUID()
        state.request(width: 800, generation: generation)
        let first = try #require({ state.begin() }())
        for width in stride(from: 790, through: 400, by: -10) {
            state.request(width: CGFloat(width), generation: generation)
            #expect({ state.begin() }() == nil)
        }
        // Progress does not depend on the user releasing the resize handle.
        #expect({ state.complete(first) }())
        #expect(state.installed == first)
        let latest = try #require({ state.begin() }())
        #expect(latest.width == 400)
        #expect({ state.complete(latest) }())
        #expect(!state.needsLayout)
        #expect({ state.begin() }() == nil)
    }

    @Test func styleInvalidationWaitsForWorkerAndRejectsItsResult() throws {
        var state = ReaderReflowState()
        state.request(width: 800, generation: UUID())
        let old = try #require({ state.begin() }())
        let generation = UUID()
        state.request(width: 500, generation: generation)
        #expect(!state.accepts(old))
        #expect({ state.begin() }() == nil)
        #expect(!{ state.complete(old) }())
        let next = try #require({ state.begin() }())
        #expect(next.generation == generation && next.width == 500)
        #expect({ state.complete(next) }())
        // Also covers invalidation while the viewport preview is being painted.
        state.request(width: 510, generation: generation)
        let painting = try #require({ state.begin() }())
        state.request(width: 510, generation: UUID())
        #expect(!{ state.complete(painting) }())
        #expect(state.installed == next)
    }

    @Test func returnToInstalledWidthAndShutdownDiscardObsoleteWork() throws {
        var state = ReaderReflowState()
        let generation = UUID()
        state.request(width: 600, generation: generation)
        let initial = try #require({ state.begin() }())
        #expect({ state.complete(initial) }())
        state.request(width: 400, generation: generation)
        let obsolete = try #require({ state.begin() }())
        state.request(width: 600, generation: generation)
        #expect(!{ state.complete(obsolete) }())
        #expect({ state.begin() }() == nil)
        state.request(width: 800, generation: generation)
        let finishing = try #require({ state.begin() }())
        state.stop()
        #expect(!state.accepts(finishing))
        #expect(!{ state.complete(finishing) }())
        #expect({ state.begin() }() == nil)
        for width in [CGFloat.zero, -.infinity, .nan] {
            state.request(width: width, generation: generation)
            #expect({ state.begin() }() == nil)
        }
    }
}
