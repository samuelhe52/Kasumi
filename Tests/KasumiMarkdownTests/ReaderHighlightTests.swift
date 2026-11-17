import Foundation
import Testing

@testable import KasumiMarkdown

@Suite struct ReaderHighlightTests {
    @Test func windowCandidatesMatchExhaustiveHighlightsAcrossTablesReplacementsAndEstimates() throws {
        let body = (0..<30).map { index in
            "Paragraph \(index). " + String(repeating: "中文 needle and 👩‍👩‍👧‍👦 text. ", count: 6)
        }
        let cell = String(repeating: "needle 中文 wrap words ", count: 8)
        let alt = String(repeating: "long fallback description words ", count: 12) + "needleEND"
        let middle = """
            | Left | Middle | Right |
            | --- | --- | --- |
            | \(cell) | $x_i+1$ needle | \(cell) |
            | next needle | more needle | final needle |

            ![\(alt)](not-a-real-image.png)

            العربية עברית needle.
            """
        let document = MarkdownDocument(
            markdown:
                body.prefix(15).joined(separator: "\n\n") + "\n\n" + middle + "\n\n"
                + body.suffix(15).joined(separator: "\n\n"))
        let style = RenderStyle(fontSize: 16, widthLimit: nil)
        for width: CGFloat in [260, 520] {
            let full = RenderedDocument(document, width: width, style: style, scrollableTables: true)
            let anchor = full.readingAnchor(atY: full.tables[0].frame.minY)
            for viewport in [false, true] {
                let snapshot = RenderedDocument(
                    document, width: width, style: style, scrollableTables: true,
                    preparation: ReflowPreparation(),
                    viewport: viewport ? ViewportLayoutRequest(height: 400, anchor: anchor) : nil)
                var windows = stride(from: CGFloat(0), to: snapshot.size.height, by: 411).map {
                    CGRect(x: 0, y: $0, width: width, height: 180)
                }
                let fallback = try #require(snapshot.ranges(matching: "needleEND").first)
                windows += snapshot.selectionRects(for: fallback).map {
                    CGRect(x: 0, y: $0.midY, width: width, height: 0.5)
                }
                let table = snapshot.tables[0]
                windows += [table.frame.minY + 20, table.frame.midY, table.frame.maxY - 30].map {
                    CGRect(x: 0, y: $0, width: width, height: 40)
                }
                for query in ["needle", "needleEND", "文", "x_i+1", "👩‍👩‍👧‍👦"] {
                    let matches = snapshot.ranges(matching: query)
                    let index = try #require(ReaderHighlightIndex(matches, in: snapshot))
                    for window in windows {
                        let candidates = index.candidates(in: snapshot, verticalRange: window.minY..<window.maxY)
                        for right in [false, true] {
                            let actual = visible(
                                snapshot, matches: matches, indices: candidates, window: window, right: right)
                            let expected = visible(
                                snapshot, matches: matches, indices: matches.indices, window: window, right: right)
                            #expect(
                                actual == expected, "\(query), width \(width), viewport \(viewport), window \(window)")
                        }
                    }
                }
            }
        }
    }

    @Test func candidatesStaySmallPreserveOriginalIndicesAndRejectForeignSnapshots() throws {
        let document = MarkdownDocument(
            markdown: (0..<100).map {
                "Paragraph \($0). " + String(repeating: "中文 needle words. ", count: 20)
            }.joined(separator: "\n\n"))
        let style = RenderStyle(fontSize: 16, widthLimit: nil)
        let snapshot = RenderedDocument(
            document, width: 400, style: style,
            scrollableTables: false, preparation: ReflowPreparation())
        let matches = snapshot.ranges(matching: "needle")
        let index = try #require(ReaderHighlightIndex(matches, in: snapshot))
        let before = snapshot.fragmentStatistics.materialized
        let top = snapshot.size.height * 0.5
        let candidates = index.candidates(in: snapshot, verticalRange: top..<(top + 400))
        #expect(candidates.count > 0 && candidates.count < matches.count / 10)
        #expect(candidates.lowerBound > matches.count / 4)
        #expect(snapshot.fragmentStatistics.materialized == before)
        let foreign = RenderedDocument(document, width: 500, style: style)
        #expect(index.candidates(in: foreign, verticalRange: top..<(top + 400)).isEmpty)
        #expect(ReaderHighlightIndex(matches, in: foreign) == nil)
        #expect(ReaderHighlightIndex(Array(matches.reversed()), in: snapshot) == nil)
        #expect(snapshot.textRange(intersectingVerticalRange: 0..<0) == nil)
        #expect(snapshot.textRange(intersectingVerticalRange: (-CGFloat.infinity)..<0) == nil)
        #expect(snapshot.textRange(intersectingVerticalRange: 0..<CGFloat.infinity) == nil)
        #expect(
            snapshot.textRange(intersectingVerticalRange: (snapshot.size.height + 10)..<(snapshot.size.height + 20))
                == nil)
        let empty = RenderedDocument(MarkdownDocument(markdown: ""), width: 400, style: style)
        #expect(empty.textRange(intersectingVerticalRange: 0..<100) == nil)
    }

    #if os(macOS)
        @Test(.enabled(if: ProcessInfo.processInfo.environment["KASUMI_HIGHLIGHT_TIMING"] == "1"))
        func macHighlightTimings() async throws {
            func ms(_ start: ContinuousClock.Instant) -> Double {
                let d = start.duration(to: .now).components
                return Double(d.seconds) * 1000 + Double(d.attoseconds) / 1e15
            }
            func stats(_ values: [Double]) -> String {
                let sorted = values.sorted()
                return
                    "p50=\(sorted[sorted.count / 2]) p95=\(sorted[Int(Double(sorted.count - 1) * 0.95)]) max=\(sorted.last!)"
            }
            let paragraph = String(String(repeating: "中文重排需要流畅，阅读位置保持稳定。", count: 4).prefix(50))
            let document = MarkdownDocument(
                markdown: Array(repeating: paragraph, count: 1000).joined(separator: "\n\n"))
            let session = DocumentReflowSession(document, style: RenderStyle(fontSize: 16, widthLimit: nil))
            for width: CGFloat in [400, 500] {
                let full = await session.render(width: width)
                let anchor = full.readingAnchor(atY: full.size.height * 0.5)
                let partial = await session.render(width: width, viewportHeight: 800, anchor: anchor)
                for (mode, snapshot) in [("full", full), ("viewport", partial)] {
                    let top = snapshot.y(for: anchor) ?? 0
                    let window = CGRect(x: 0, y: max(0, top - 400), width: width, height: 1600)
                    let matches = snapshot.ranges(matching: "文")
                    let index = try #require(ReaderHighlightIndex(matches, in: snapshot))
                    let reference = visible(
                        snapshot, matches: matches, indices: matches.indices, window: window, right: false)
                    var build: [Double] = []
                    var all: [Double] = []
                    var bounded: [Double] = []
                    var candidateCount = 0
                    for _ in 0..<30 {
                        var start = ContinuousClock.now
                        let current = try #require(ReaderHighlightIndex(matches, in: snapshot))
                        build.append(ms(start))
                        start = .now
                        let expected = visible(
                            snapshot, matches: matches, indices: matches.indices, window: window, right: false)
                        all.append(ms(start))
                        start = .now
                        let candidates = current.candidates(in: snapshot, verticalRange: window.minY..<window.maxY)
                        let actual = visible(
                            snapshot, matches: matches, indices: candidates, window: window, right: false)
                        bounded.append(ms(start))
                        candidateCount = index.candidates(in: snapshot, verticalRange: window.minY..<window.maxY).count
                        #expect(actual == reference && expected == reference)
                    }
                    print(
                        "HIGHLIGHT_TIMING \(mode) width=\(width) matches=\(matches.count) candidates=\(candidateCount) build=\(stats(build)) all=\(stats(all)) bounded=\(stats(bounded))"
                    )
                }
            }
        }
    #endif

    private struct Highlight: Equatable {
        let index: Int
        let rect: CGRect
    }

    private func visible(
        _ snapshot: RenderedDocument, matches: [KasumiMarkdown.TextRange], indices: Range<Int>,
        window: CGRect, right: Bool
    ) -> [Highlight] {
        indices.flatMap { index in
            snapshot.selectionRects(for: matches[index]).compactMap { rect in
                var visible = rect
                if let table = snapshot.tables.first(where: {
                    $0.isScrollable && rect.midY >= $0.frame.minY && rect.midY <= $0.frame.maxY
                }) {
                    visible = rect.offsetBy(dx: right ? -(table.contentWidth - table.frame.width) : 0, dy: 0)
                        .intersection(table.frame)
                }
                guard !visible.isNull, !visible.isEmpty, visible.intersects(window) else { return nil }
                return Highlight(index: index, rect: visible)
            }
        }
    }
}
