import Foundation
import Testing

@testable import KasumiMarkdown

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

    @Test func deepScrollInvalidatesViewportWorkButResizeAtSameAnchorStillPublishes() throws {
        var state = ReaderReflowState()
        let generation = UUID()
        let firstAnchor = ReadingAnchor(blockKey: "a", blockIndex: 0, offset: 0, blockCount: 100, verticalFraction: 0)
        let farAnchor = ReadingAnchor(blockKey: "b", blockIndex: 70, offset: 100, blockCount: 100, verticalFraction: 0)
        state.request(width: 400, generation: generation, anchor: firstAnchor, height: 700)
        let old = try #require({ state.begin() }())
        state.request(width: 400, generation: generation, anchor: farAnchor, height: 700)
        #expect(!state.accepts(old))
        #expect(!{ state.complete(old) }())
        let far = try #require({ state.begin() }())
        state.request(width: 500, generation: generation, anchor: farAnchor, height: 700)
        #expect({ state.complete(far) }())
        let resized = try #require({ state.begin() }())
        #expect(resized.width == 500 && resized.anchor == farAnchor)
        #expect({ state.complete(resized) }())
        #expect(!state.needsLayout)
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

    @Test func hiddenPreviewDrainsItsWorkerBeforeResumingAtTheLatestRequest() throws {
        var state = ReaderReflowState()
        let generation = UUID()
        state.request(width: 400, generation: generation)
        let hidden = try #require({ state.begin() }())
        state.stop()
        #expect(!state.accepts(hidden))
        #expect({ state.begin() }() == nil)
        // Reopen before the hidden worker returns, after changing the content.
        let edited = UUID()
        state.request(width: 600, generation: edited)
        #expect({ state.begin() }() == nil)
        #expect(!{ state.complete(hidden) }())
        let resumed = try #require({ state.begin() }())
        #expect(resumed.width == 600 && resumed.generation == edited)
        #expect({ state.complete(resumed) }())
        #expect(!state.needsLayout)
    }

    @Test func contentRevisionsRefreshFrozenReadingKeysWithoutWidthDrift() throws {
        let tail =
            String(repeating: "Leading words place the reading marker inside the paragraph. ", count: 4)
            + "Reading marker. " + String(repeating: "More words keep the target long enough to reflow. ", count: 12)
        let original = [
            "Original previous two.", "Original previous one.",
            "Original target paragraph. " + tail, "Original next one.", "Original next two."
        ]
        func render(_ paragraphs: [String], width: CGFloat = 400, fontSize: CGFloat = 16) -> RenderedDocument {
            RenderedDocument(
                MarkdownDocument(markdown: paragraphs.joined(separator: "\n\n")), width: width,
                style: RenderStyle(fontSize: fontSize, widthLimit: nil))
        }
        let first = render(original)
        let target = try #require(first.ranges(matching: "Reading marker.").first)
        let rect = try #require(first.selectionRects(for: target).first)
        let initialY = rect.minY + rect.height * 0.25
        let originalAnchor = first.readingAnchor(atY: initialY)
        #expect(originalAnchor.blockIndex == 2 && originalAnchor.offset > 0)
        var state = ReaderReflowAnchorState()
        let revisionA = UUID()
        state.didInstall(first, revision: revisionA, atY: initialY)
        for width: CGFloat in [800, 300, 500, 400] {
            let next = render(original, width: width, fontSize: width == 500 ? 22 : 16)
            let y = try #require(next.y(for: originalAnchor))
            state.captureIfNeeded(in: next, atY: y, restoring: nil)
            state.didInstall(next, revision: revisionA, atY: y)
            #expect(state.value == originalAnchor)
        }

        var edited = original
        edited[2] = "Edited target paragraph. " + tail
        let second = render(edited)
        let currentAnchor = try #require(state.value)
        let secondY = try #require(second.y(for: currentAnchor))
        state.didInstall(second, revision: UUID(), atY: secondY)
        let secondAnchor = try #require(state.value)
        #expect(secondAnchor.blockIndex == 2 && secondAnchor.blockKey != originalAnchor.blockKey)
        let updated =
            (0..<5).map { "Inserted prefix paragraph \($0)." }
            + [
                "Replaced previous two.", "Replaced previous one.", edited[2], "Replaced next one.",
                "Replaced next two."
            ]
        let third = render(updated)
        let thirdY = try #require(third.y(for: secondAnchor))
        #expect(third.readingAnchor(atY: thirdY).blockIndex == 7)
        let staleY = try #require(third.y(for: originalAnchor))
        #expect(third.readingAnchor(atY: staleY).blockIndex == 4)
        state.didInstall(third, revision: UUID(), atY: thirdY)
        let thirdAnchor = try #require(state.value)
        #expect(thirdAnchor.blockIndex == 7)
    }

    @Test func explicitProgrammaticScrollTracksActualClampedTopWithoutDelegate() throws {
        let source = (0..<20).map { "Paragraph \($0). " + String(repeating: "Reading position text. ", count: 12) }
            .joined(separator: "\n\n")
        let parsed = MarkdownDocument(markdown: source)
        let style = RenderStyle(fontSize: 16, widthLimit: nil)
        let document = RenderedDocument(parsed, width: 400, style: style)
        func top(_ query: String) throws -> CGFloat {
            let match = try #require(document.ranges(matching: query).first)
            return try #require(document.selectionRects(for: match).first).minY
        }
        let revision = UUID()
        var state = ReaderReflowAnchorState()
        // A Find result at paragraph 2, followed by manual scrolling to 15.
        let resultTop = max(0, try top("Paragraph 2.") - 24)
        let awayTop = try top("Paragraph 15.")
        state.didInstall(document, revision: revision, atY: resultTop)
        state.moved(in: document, atY: awayTop)
        let away = try #require(state.value)
        // The keyboard handler deliberately scrolls while its delegate is guarded.
        // It must record the actual clamped top explicitly, as the app now does.
        let maximum = max(0, document.size.height - 500)
        let actualTop = min(maximum, resultTop)
        state.moved(in: document, atY: actualTop)
        let revealed = try #require(state.value)
        #expect(revealed == document.readingAnchor(atY: actualTop) && revealed != away)
        let resized = RenderedDocument(parsed, width: 600, style: style)
        let restored = try #require(resized.y(for: revealed))
        state.didInstall(resized, revision: revision, atY: restored)
        #expect(state.value == revealed)
        let saved = try JSONEncoder().encode(revealed)
        #expect(try JSONDecoder().decode(ReadingAnchor.self, from: saved) == revealed)
        // Requested navigation can exceed the scroll range; track the displayed top.
        let pastEnd = document.size.height + 1000
        state.moved(in: document, atY: min(maximum, pastEnd))
        #expect(state.value == document.readingAnchor(atY: maximum))
        #expect(state.value != document.readingAnchor(atY: pastEnd))
    }

}
