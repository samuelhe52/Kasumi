import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import KasumiMarkdown

@Suite struct ViewportLayoutTests {
    private let style = RenderStyle(fontSize: 16, widthLimit: nil)
    private var source: String {
        (0..<80).map { i in
            "Paragraph \(i). "
                + String(
                    repeating: "中文𠀀汉\u{0301}、主线“感知—传输” *office* **affinity** and reading words. ", count: 6)
        }.joined(separator: "\n\n")
    }

    @Test func viewportMeasuresNearbyParagraphsAndKeepsLocalGeometryExact() async throws {
        let document = MarkdownDocument(markdown: source)
        let session = DocumentReflowSession(document, style: style)
        let original = await session.render(width: 600)
        let text = original.text(in: original.documentRange)
        for (width, target) in [(CGFloat(320), 0), (336, 0), (800, 40), (400, 79)] {
            let match = try #require(original.ranges(matching: "Paragraph \(target).").first)
            let reading = try #require(original.position(from: match.lowerBound, offset: 180))
            let anchor = original.readingAnchor(atY: original.caretRect(for: reading).minY + 2)
            #expect(anchor.offset > 0)
            let viewport = await session.render(width: width, viewportHeight: 500, anchor: anchor)
            let full = await session.render(width: width)
            #expect(viewport.hasEstimatedGeometry)
            #expect(viewport.paragraphStatistics.measured < 20)
            #expect(viewport.text(in: viewport.documentRange) == text)
            let y = try #require(viewport.y(for: anchor))
            let referenceY = try #require(full.y(for: anchor))
            let top = min(max(0, y), max(0, viewport.size.height - 500))
            let referenceTop = min(max(0, referenceY), max(0, full.size.height - 500))
            let region = CGRect(x: 0, y: top, width: width, height: min(500, viewport.size.height - top))
            #expect(!viewport.needsLayout(in: region))
            let actualPixels = try pixels(viewport, top: top)
            let expectedPixels = try pixels(full, top: referenceTop)
            #expect(actualPixels == expectedPixels)
            let current = try #require(viewport.ranges(matching: "Paragraph \(target).").first)
            let reference = try #require(full.ranges(matching: "Paragraph \(target).").first)
            let actual = viewport.caretRect(for: current.lowerBound).offsetBy(dx: 0, dy: -y)
            let expected = full.caretRect(for: reference.lowerBound).offsetBy(dx: 0, dy: -referenceY)
            #expect(abs(actual.minY - expected.minY) < 0.000_001)
            #expect(actual.minX == expected.minX && actual.size == expected.size)
            #expect(viewport.readingAnchor(atY: y).blockKey == anchor.blockKey)
        }
        // Later layouts must not mutate previously published snapshots.
        #expect(original.text(in: original.documentRange) == text)
        #expect(!original.hasEstimatedGeometry)
    }

    @Test func coldViewportPreparesOnlyVisibleDrawingTextAndKeepsSearchComplete() throws {
        let document = MarkdownDocument(markdown: source)
        let preparation = ReflowPreparation()
        let partial = RenderedDocument(
            document, width: 600, style: style, scrollableTables: false, preparation: preparation,
            viewport: ViewportLayoutRequest(height: 500, anchor: nil))
        #expect(preparation.attributedBuilds < 15)
        #expect(preparation.shapedParagraphCount < 15)
        #expect(partial.ranges(matching: "Paragraph 79.").count == 1)
        let full = RenderedDocument(document, width: 600, style: style)
        #expect(partial.text(in: partial.documentRange) == full.text(in: full.documentRange))
        #expect(try pixels(partial, top: 0) == pixels(full, top: 0))
    }

    @Test func deepNavigationAndPoorEstimatesRefineTheSemanticTarget() async throws {
        let document = MarkdownDocument(markdown: source)
        let session = DocumentReflowSession(document, style: style)
        let initial = await session.render(width: 400, viewportHeight: 500)
        let far = try #require(initial.ranges(matching: "Paragraph 65.").first)
        let target = try #require(initial.readingAnchor(at: far.lowerBound))
        let approximate = initial.selectionRects(for: far)
        #expect(approximate.count == 1)
        #expect(initial.needsLayout(in: approximate[0]))
        let refined = await session.render(width: 400, viewportHeight: 500, anchor: target)
        let y = try #require(refined.y(for: target))
        #expect(!refined.needsLayout(in: CGRect(x: 0, y: y, width: 400, height: 500)))
        #expect(refined.readingAnchor(atY: y).blockKey == target.blockKey)
        #expect(refined.paragraphStatistics.measured < 20)
        #expect(initial.needsLayout(in: approximate[0]))
        #expect(initial.readingAnchor(at: far.lowerBound) == target)
        let offset = try #require(initial.offset(from: initial.documentRange.lowerBound, to: far.lowerBound))
        let lower = try #require(refined.position(from: refined.documentRange.lowerBound, offset: offset))
        let upper = try #require(refined.position(from: lower, offset: "Paragraph 65.".utf16.count))
        #expect(refined.text(in: TextRange(lower, upper)) == initial.text(in: far))
        #expect(initial.offset(from: initial.documentRange.lowerBound, to: lower) == nil)

        let preparation = ReflowPreparation()
        for index in 0..<80 { preparation.measuredHeight(10_000, at: index, width: 320) }
        let poor = RenderedDocument(
            document, width: 320, style: style, scrollableTables: false, preparation: preparation,
            viewport: ViewportLayoutRequest(height: 700, anchor: target))
        let correctedY = try #require(poor.y(for: target))
        #expect(!poor.needsLayout(in: CGRect(x: 0, y: correctedY, width: 320, height: 700)))
        #expect(poor.readingAnchor(atY: correctedY).blockKey == target.blockKey)
    }

    @Test func visibleMarginHitTestsCannotSelectWideOffscreenEstimates() async throws {
        let document = MarkdownDocument(markdown: (0..<100).map { "Short paragraph \($0)." }.joined(separator: "\n\n"))
        let session = DocumentReflowSession(document, style: style)
        let viewport = await session.render(width: 1000, viewportHeight: 500)
        let full = await session.render(width: 1000)
        #expect(viewport.hasEstimatedGeometry)
        #expect(!viewport.needsLayout(in: CGRect(x: 0, y: 0, width: 1000, height: 500)))
        for point in [CGPoint(x: 950, y: 250), CGPoint(x: 0, y: 250), CGPoint(x: 100, y: 250), CGPoint(x: 950, y: 490)]
        {
            let actual = viewport.position(closestTo: point)
            let expected = full.position(closestTo: point)
            #expect(
                viewport.offset(from: viewport.documentRange.lowerBound, to: actual)
                    == full.offset(from: full.documentRange.lowerBound, to: expected))
            #expect(viewport.caretRect(for: actual) == full.caretRect(for: expected))
        }
        // Offscreen hit testing remains approximate until that region is refined.
        let offscreen = viewport.position(closestTo: CGPoint(x: 100, y: 3000))
        #expect(viewport.needsLayout(in: viewport.caretRect(for: offscreen)))
        // Gaps and EOF outside the prepared window must also stay local rather
        // than jumping back to the viewport's final measured line.
        for point in [CGPoint(x: 40, y: 2804.7656), CGPoint(x: 40, y: viewport.size.height + 5)] {
            let actual = viewport.position(closestTo: point)
            let expected = full.position(closestTo: point)
            let actualOffset = try #require(viewport.offset(from: viewport.documentRange.lowerBound, to: actual))
            let expectedOffset = try #require(full.offset(from: full.documentRange.lowerBound, to: expected))
            #expect(abs(actualOffset - expectedOffset) <= 32)
            #expect(abs(viewport.caretRect(for: actual).minY - full.caretRect(for: expected).minY) < 40)
        }
    }

    @Test func quoteOverhangRequiresRefinementBeforeRegionExport() async throws {
        let document = MarkdownDocument(
            markdown: (0..<100).map { "> Quoted paragraph \($0)." }.joined(separator: "\n\n"))
        let preparation = ReflowPreparation()
        let request = ViewportLayoutRequest(height: 500, anchor: nil)
        let layout = DocumentTypesetter.viewportLayout(
            document.parsed, width: 400, style: style.typography, insets: style.insets,
            scrollableTables: false, preparation: preparation, request: request)
        let first = try #require(layout.paragraphs.first { $0.paragraph.estimate != nil })
        let partial = RenderedDocument(
            document, width: 400, style: style, scrollableTables: false, preparation: preparation, viewport: request)
        let region = CGRect(x: 0, y: first.origin.y - 2, width: 400, height: 1)
        #expect(partial.needsLayout(in: region))
        #expect(throws: DocumentExportError.self) { try DocumentExport.png(partial, scale: 2, region: region) }
        let anchor = partial.readingAnchor(atY: first.origin.y)
        let refined = await DocumentReflowSession(document, style: style).render(
            width: 400, viewportHeight: 500, anchor: anchor)
        #expect(!refined.needsLayout(in: region))
        let full = RenderedDocument(document, width: 400, style: style)
        let actual = try decodedPixels(DocumentExport.png(refined, scale: 2, region: region))
        let expected = try decodedPixels(DocumentExport.png(full, scale: 2, region: region))
        #expect(actual == expected)
    }

    @Test func emptyHeadingAnchorsKeepTheirOriginAfterMeasurement() async throws {
        let huge = String(repeating: "中文 text before the empty heading. ", count: 120)
        let trailing = (0..<50).map { "Following paragraph \($0)." }.joined(separator: "\n\n")
        let document = MarkdownDocument(markdown: huge + "\n\n# \n\n" + trailing + "\n\n# \n\nEnd.")
        let session = DocumentReflowSession(document, style: style)
        let initial = await session.render(width: 400, viewportHeight: 500)
        for id in ["", "-1"] {
            let anchor = try #require(initial.readingAnchor(forAnchor: id))
            for width: CGFloat in [400, 800] {
                let measured = await session.render(width: width, viewportHeight: 500, anchor: anchor)
                let rect = try #require(measured.rect(forAnchor: id))
                let y = try #require(measured.y(for: anchor))
                #expect(abs(y - rect.minY) < 0.000_001)
                #expect(!measured.needsLayout(in: rect.insetBy(dx: 0, dy: -1)))
                #expect(measured.paragraphStatistics.measured < measured.paragraphStatistics.total)
            }
            let full = await session.render(width: 400)
            let fullRect = try #require(full.rect(forAnchor: id))
            let fullY = try #require(full.y(for: anchor))
            #expect(abs(fullY - fullRect.minY) < 0.000_001)
        }
    }

    @Test func mixedViewportFreezesInputsAndKeepsTablesAndAttachmentsExact() async throws {
        let body = source.components(separatedBy: "\n\n")
        let mixed = #"""
            ## Mixed content

            | Long header first | Long header second | Formula/picture |
            | --- | --- | --- |
            | A long cell with words and 中文 text wrapping inside the column. | Another long cell with words and 中文 text. | $x+1$ |
            | More wrapping text in the first column. | More wrapping text in the second column. | ![tiny](images/tiny.png) |

            Inline formula $\frac{1}{3}$ in a paragraph.

            ![wide](images/wide%20sample.png)

            $$
            x^2+1
            $$

            ```mermaid
            graph LR
            A[Start] --> B[End]
            ```
            """#
        let document = MarkdownDocument(
            markdown: (Array(body.prefix(40)) + [mixed] + Array(body.suffix(40))).joined(separator: "\n\n"),
            baseURL: testRepositoryURL.appendingPathComponent("fixtures"))
        let preparation = ReflowPreparation()
        var retained: [DocumentLayout] = []
        var previousObjects = Set<ObjectIdentifier>()
        var imageWidths: [CGFloat] = []
        for width: CGFloat in [400, 800, 320] {
            let full = RenderedDocument(document, width: width, style: style, scrollableTables: true)
            let anchor = try #require(full.readingAnchor(forAnchor: "mixed-content"))
            let request = ViewportLayoutRequest(height: 800, anchor: anchor)
            let layout = DocumentTypesetter.viewportLayout(
                document.parsed, width: width, style: style.typography, insets: style.insets,
                scrollableTables: true, preparation: preparation, request: request)
            let storageObjects = attachmentIdentities(layout.text)
            let paragraphObjects = layout.paragraphs.reduce(into: Set<ObjectIdentifier>()) {
                $0.formUnion(attachmentIdentities($1.paragraph.attributed))
            }
            #expect(storageObjects.count >= 6 && storageObjects == paragraphObjects)
            #expect(storageObjects.isDisjoint(with: previousObjects))
            previousObjects.formUnion(storageObjects)
            #expect(layout.textMap == DocumentTextMap(layout.text))
            for item in layout.paragraphs
            where item.tableIndex != nil || !attachmentIdentities(item.paragraph.attributed).isEmpty {
                #expect(item.paragraph.estimate == nil)
            }
            imageWidths.append(try #require(layout.imageBounds.map(\.width).max()))
            retained.append(layout)
            let partial = RenderedDocument(
                document, width: width, style: style, scrollableTables: true, preparation: preparation,
                viewport: request)
            #expect(partial.hasEstimatedGeometry)
            #expect(partial.paragraphStatistics.measured < partial.paragraphStatistics.total / 2)
            #expect(partial.text(in: partial.documentRange) == full.text(in: full.documentRange))
            let y = try #require(partial.y(for: anchor))
            let referenceY = try #require(full.y(for: anchor))
            #expect(!partial.needsLayout(in: CGRect(x: 0, y: y, width: width, height: 500)))
            let actual = try pixels(partial, top: y)
            let expected = try pixels(full, top: referenceY)
            #expect(actual == expected)
            let table = try #require(partial.tables.first)
            let reference = try #require(full.tables.first)
            #expect(table.contentWidth == reference.contentWidth && table.frame.width == reference.frame.width)
            #expect(abs(table.frame.height - reference.frame.height) < 0.000_001)
            for x in [CGFloat(0), max(0, table.contentWidth - 200)] {
                let region = CGRect(x: x, y: 0, width: 200, height: min(200, table.frame.height.rounded(.down)))
                let a = try tablePixels(partial, rect: region)
                let b = try tablePixels(full, rect: region)
                #expect(a == b)
            }
            for query in ["wide", "x^2+1", "Start"] {
                let match = try #require(full.ranges(matching: query).first)
                let target = try #require(full.readingAnchor(at: match.lowerBound))
                let revealed = RenderedDocument(
                    document, width: width, style: style, scrollableTables: true, preparation: preparation,
                    viewport: ViewportLayoutRequest(height: 500, anchor: target))
                let actualY = try #require(revealed.y(for: target))
                let expectedY = try #require(full.y(for: target))
                #expect(!revealed.needsLayout(in: CGRect(x: 0, y: actualY, width: width, height: 500)))
                let actual = try pixels(revealed, top: actualY)
                let expected = try pixels(full, top: expectedY)
                #expect(actual == expected)
            }
        }
        #expect(imageWidths[1] > imageWidths[0] && imageWidths[0] > imageWidths[2])
        #expect(retained.count == 3)
    }

    @Test func offscreenTablesAndMathDeferThenRefineWithExactPixelsAndSemanticOffsets() async throws {
        let body = (0..<50).map { "Paragraph \($0). " + String(repeating: "中文 text words. ", count: 10) }
        let mixed = """
            | Feature | Formula | Text |
            | --- | --- | --- |
            | Measurement | $x_i + 1$ | 中文 and `inline code` |

            $$
            \\frac{1}{3} + x^2
            $$
            """
        let document = MarkdownDocument(markdown: (body + [mixed] + body).joined(separator: "\n\n"))
        let preparation = ReflowPreparation()
        let request = ViewportLayoutRequest(height: 500, anchor: nil)
        let layout = DocumentTypesetter.viewportLayout(
            document.parsed, width: 500, style: style.typography, insets: style.insets,
            scrollableTables: true, preparation: preparation, request: request)
        #expect(layout.paragraphs.filter { $0.tableIndex != nil }.allSatisfy { $0.paragraph.estimate != nil })
        #expect(attachmentIdentities(layout.text).isEmpty)
        let session = DocumentReflowSession(document, style: style, scrollableTables: true)
        let initial = await session.render(width: 500, viewportHeight: 500)
        let full = RenderedDocument(document, width: 500, style: style, scrollableTables: true)
        let originalPixels = try pixels(initial, top: 0)
        #expect(initial.text(in: initial.documentRange) == full.text(in: full.documentRange))
        var measuredTable: RenderedTable?
        for query in ["Measurement", "x_i + 1", "inline code", "frac"] {
            let match = try #require(initial.ranges(matching: query).first)
            let anchor = try #require(initial.readingAnchor(at: match.lowerBound))
            let exact = await session.render(width: 500, viewportHeight: 500, anchor: anchor)
            let top = try #require(exact.y(for: anchor))
            let referenceTop = try #require(full.y(for: anchor))
            #expect(!exact.needsLayout(in: CGRect(x: 0, y: top, width: 500, height: 500)))
            #expect(exact.text(in: exact.documentRange) == full.text(in: full.documentRange))
            #expect(try pixels(exact, top: top) == pixels(full, top: referenceTop))
            if query == "Measurement" { measuredTable = exact.tables.first }
        }
        let returned = await session.render(width: 500, viewportHeight: 500)
        #expect(returned.tables.first?.frame.size == measuredTable?.frame.size)
        #expect(returned.tables.first?.contentWidth == measuredTable?.contentWidth)
        #expect(try pixels(initial, top: 0) == originalPixels)
    }

    @Test func idlePreparationProducesCompleteIndependentSnapshotsAndResetsForWidth() async throws {
        let source =
            (0..<35).map { "Paragraph \($0). " + String(repeating: "中文 text. ", count: 12) }
            .joined(separator: "\n\n") + "\n\n| A | B |\n| --- | --- |\n| $x+1$ | Text |"
        let document = MarkdownDocument(markdown: source)
        let session = DocumentReflowSession(document, style: style)
        let initial = await session.render(width: 400, viewportHeight: 300)
        #expect(initial.hasEstimatedGeometry)
        let before = try pixels(initial, top: 0)
        let warm = try #require(try await session.prepareForScrolling(width: 400))
        let full = RenderedDocument(document, width: 400, style: style)
        #expect(!warm.hasEstimatedGeometry && warm.size == full.size)
        let revisited = await session.render(
            width: 400, viewportHeight: 300,
            anchor: warm.readingAnchor(atY: warm.size.height * 0.8))
        #expect(revisited === warm && !revisited.hasEstimatedGeometry)
        #expect(warm.text(in: warm.documentRange) == full.text(in: full.documentRange))
        for fraction: CGFloat in [0, 0.3, 0.8] {
            let top = fraction * max(0, full.size.height - 500)
            #expect(try pixels(warm, top: top) == pixels(full, top: top))
        }
        _ = await session.render(width: 600, viewportHeight: 300)
        let resized = try #require(try await session.prepareForScrolling(width: 600))
        #expect(resized.size.width == 600 && !resized.hasEstimatedGeometry)
        #expect(warm.size == full.size)
        #expect(try pixels(initial, top: 0) == before)
    }

    @Test func foregroundWidthChangeInvalidatesInFlightIdlePreparation() async throws {
        let session = DocumentReflowSession(MarkdownDocument(markdown: source), style: style)
        let task = Task { try await session.prepareForScrolling(width: 400) }
        while await session.warmCursor == 0 { await Task.yield() }
        let foreground = await session.render(width: 600, viewportHeight: 500)
        do {
            if let completed = try await task.value { #expect(completed.size.width == 400) }
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(foreground.size.width == 600)
        let ready = try #require(try await session.prepareForScrolling(width: 600))
        #expect(ready.size.width == 600 && !ready.hasEstimatedGeometry)
        let full = RenderedDocument(MarkdownDocument(markdown: source), width: 600, style: style)
        #expect(try pixels(ready, top: 0) == pixels(full, top: 0))
    }

    @Test func idlePreparationHonorsCancellationAndResourceEnvelope() async throws {
        let document = MarkdownDocument(markdown: source)
        let session = DocumentReflowSession(document, style: style)
        let task = Task { try await session.prepareForScrolling(width: 400) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled idle preparation completed")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        let next = await session.render(width: 600, viewportHeight: 500)
        #expect(!next.needsLayout(in: CGRect(x: 0, y: 0, width: 600, height: 500)))
        let warm = try #require(try await session.prepareForScrolling(width: 600))
        #expect(!warm.hasEstimatedGeometry && warm.size.width == 600)
        for source in [
            String(repeating: "x", count: 4001), "![image](missing.png)",
            "| A | B |\n| --- | --- |\n" + String(repeating: "| a | b |\n", count: 33)
        ] {
            let excluded = DocumentReflowSession(MarkdownDocument(markdown: source), style: style)
            #expect(try await excluded.prepareForScrolling(width: 400) == nil)
        }
        for source in [
            "![remote](https://example.invalid/image.png)", "![missing](missing.png)",
            "```mermaid\ngraph TD; A-->B\n```"
        ] {
            let excluded = DocumentReflowSession(
                MarkdownDocument(markdown: source, baseURL: testRepositoryURL), style: style,
                readerDisplayScale: 2, preparesLocalImageLayout: true)
            #expect(try await excluded.prepareForScrolling(width: 400) == nil)
        }
    }

    @Test func idlePreparationKeepsLocalAndEmbeddedImagePixelsDeferred() async throws {
        let base = testRepositoryURL.appendingPathComponent("fixtures")
        let data = try Data(contentsOf: base.appendingPathComponent("images/tiny.png")).base64EncodedString()
        let prose = (0..<30).map { "Paragraph \($0) with enough text to wrap on a narrow screen." }
            .joined(separator: "\n\n")
        let wideTable =
            "| A | B | C | D | E | F | G | H |\n"
            + "| --- | --- | --- | --- | --- | --- | --- | --- |\n"
            + String(repeating: "| 0 | 1 | 0 | 1 | 0 | 1 | 0 | 1 |\n", count: 11)
        let document = MarkdownDocument(
            markdown: """
                ![Local SVG](HTMLAndSVG/logo.svg)

                \(prose)

                \(wideTable)

                | Local PNG | Embedded PNG |
                | --- | --- |
                | ![Local](images/wide%20sample.png) | ![Embedded](data:image/png;base64,\(data)) |
                """, baseURL: base)
        let eager = DocumentReflowSession(
            document, style: style, readerDisplayScale: nil, preparesLocalImageLayout: true)
        #expect(try await eager.prepareForScrolling(width: 400) == nil)
        let defaultReader = DocumentReflowSession(document, style: style, readerDisplayScale: 2)
        #expect(try await defaultReader.prepareForScrolling(width: 400) == nil)

        let reader = DocumentReflowSession(
            document, style: style, readerDisplayScale: 2, preparesLocalImageLayout: true)
        let first = await reader.render(width: 400, viewportHeight: 200)
        #expect(first.hasEstimatedGeometry)
        let warm = try #require(try await reader.prepareForScrolling(width: 400))
        let reference = await defaultReader.render(width: 400)
        let regions = warm.readerImageRegions(in: CGRect(origin: .zero, size: warm.size))
        #expect(!warm.hasEstimatedGeometry && warm.size == reference.size)
        #expect(warm.text(in: warm.documentRange) == reference.text(in: reference.documentRange))
        #expect(regions.count == 3)
        #expect(regions == reference.readerImageRegions(in: CGRect(origin: .zero, size: reference.size)))
        #expect(regions.allSatisfy { !warm.hasReaderImageResult(for: $0) })
        let revisited = await reader.render(
            width: 400, viewportHeight: 200, anchor: warm.readingAnchor(atY: warm.size.height * 0.8))
        #expect(revisited === warm)
        let visible = try #require(regions.first)
        #expect(await warm.prepareReaderImage(visible))
        #expect(revisited.hasReaderImageResult(for: visible))
        #expect(!warm.hasReaderImageResult(for: try #require(regions.last)))

        let resized = await reader.render(width: 550, viewportHeight: 200)
        #expect(resized.size.width == 550 && resized.hasEstimatedGeometry)
        let readyAtNewWidth = try #require(try await reader.prepareForScrolling(width: 550))
        #expect(readyAtNewWidth !== warm && readyAtNewWidth.size.width == 550)
    }

    @Test func linkedParagraphDefersItsUnadornedLines() async throws {
        let words = String(repeating: "普通中文 text before and after the link. ", count: 30)
        let document = MarkdownDocument(markdown: words + "[agp linked](https://example.com) " + words)
        let session = DocumentReflowSession(document, style: style)
        for width: CGFloat in [400, 600] {
            let lazy = await session.render(width: width)
            let eager = RenderedDocument(document, width: width, style: style)
            let initial = lazy.fragmentStatistics
            #expect(initial.materialized > 0 && initial.materialized < initial.total / 4)
            let actual = try pixels(lazy, top: 0)
            let expected = try pixels(eager, top: 0)
            #expect(actual == expected)
            #expect(lazy.fragmentStatistics.materialized < initial.total)
            let match = try #require(lazy.ranges(matching: "agp linked").first)
            let reference = try #require(eager.ranges(matching: "agp linked").first)
            let rect = try #require(lazy.selectionRects(for: match).first)
            let linkedPixels = try pixels(lazy, top: max(0, rect.minY - 100))
            let referencePixels = try pixels(eager, top: max(0, rect.minY - 100))
            #expect(linkedPixels == referencePixels)
            #expect(lazy.selectionRects(for: match) == eager.selectionRects(for: reference))
        }
    }

    @Test func textBlocksAndMixedAttachmentsPreserveExactVisibleOutput() async throws {
        let blocks = """
            # Heading

            > Quoted 中文 text.

            1. First list item.
            2. Second list item.

            ```swift
            let value = 42
            ```

            ---

            """ + source + "\n\n# Deep heading\n\nReference [^note].\n\n[^note]: Footnote target."
        let document = MarkdownDocument(markdown: blocks)
        let session = DocumentReflowSession(document, style: style)
        let partial = await session.render(width: 400, viewportHeight: 500)
        let full = await session.render(width: 400)
        #expect(partial.hasEstimatedGeometry)
        #expect(!partial.needsLayout(in: CGRect(x: 0, y: 0, width: 400, height: 500)))
        let a = try pixels(partial, top: 0)
        let b = try pixels(full, top: 0)
        #expect(a == b)
        let region = CGRect(x: 0, y: 0, width: 400, height: 300)
        let actual = try partial.imageData(scale: 1, region: region)
        let expected = try full.imageData(scale: 1, region: region)
        #expect(actual == expected)
        #expect(throws: DocumentExportError.self) { try DocumentExport.png(partial, scale: 1) }
        let far = try #require(partial.ranges(matching: "Paragraph 65.").first)
        let unmeasuredRegion = try #require(partial.selectionRects(for: far).first)
        #expect(throws: DocumentExportError.self) {
            try DocumentExport.jpeg(partial, scale: 1, region: unmeasuredRegion)
        }
        for id in ["deep-heading", "fn-note"] {
            let rect = try #require(partial.rect(forAnchor: id))
            #expect(partial.needsLayout(in: rect.insetBy(dx: 0, dy: -1)))
            let anchor = try #require(partial.readingAnchor(forAnchor: id))
            let navigated = await session.render(width: 400, viewportHeight: 500, anchor: anchor)
            let exactRect = try #require(navigated.rect(forAnchor: id))
            #expect(!navigated.needsLayout(in: exactRect.insetBy(dx: 0, dy: -1)))
            let targetY = try #require(navigated.y(for: anchor))
            let referenceY = try #require(full.y(for: anchor))
            // A footnote marker shares the body baseline and can be the capture
            // index's canonical first line. Match the exact layout's choice.
            #expect(navigated.readingAnchor(atY: targetY).blockKey == full.readingAnchor(atY: referenceY).blockKey)
        }
        for attachment in [
            "| A | B |\n| --- | --- |\n| one | two |", "![image](missing.png)", "$x+1$",
            "$$\nx+1\n$$", "```mermaid\ngraph LR\nA-->B\n```"
        ] {
            let doc = MarkdownDocument(markdown: source + "\n\n" + attachment)
            let result = await DocumentReflowSession(doc, style: style).render(width: 400, viewportHeight: 500)
            #expect(result.hasEstimatedGeometry)
            #expect(result.paragraphStatistics.measured < result.paragraphStatistics.total / 2)
            #expect(!result.needsLayout(in: CGRect(x: 0, y: 0, width: 400, height: 500)))
            let exact = RenderedDocument(doc, width: 400, style: style)
            #expect(result.text(in: result.documentRange) == exact.text(in: exact.documentRange))
            let visible = try pixels(result, top: 0)
            let reference = try pixels(exact, top: 0)
            #expect(visible == reference)
        }
        let giant = MarkdownDocument(markdown: String(repeating: "中文 English text ", count: 200))
        let single = await DocumentReflowSession(giant, style: style).render(width: 400, viewportHeight: 500)
        #expect(single.paragraphStatistics.total == 1 && single.paragraphStatistics.measured == 1)
    }

    private func pixels(_ document: RenderedDocument, top: CGFloat) throws -> Data {
        let width = Int(document.size.width * 2)
        let context = try #require(
            CGContext(
                data: nil, width: width, height: 1000, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        context.translateBy(x: 0, y: 500)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -top)
        document.draw(in: context, rect: CGRect(x: 0, y: top, width: document.size.width, height: 500))
        return Data(bytes: try #require(context.data), count: context.bytesPerRow * context.height)
    }

    private func decodedPixels(_ data: Data) throws -> Data {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try #require(image.dataProvider?.data) as Data
    }

    private func attachmentIdentities(_ attributed: NSAttributedString) -> Set<ObjectIdentifier> {
        var objects = Set<ObjectIdentifier>()
        for key in [NSAttributedString.Key.kasumiMath, .kasumiImage, .kasumiDiagram] {
            attributed.enumerateAttribute(key, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                if let value { objects.insert(ObjectIdentifier(value as AnyObject)) }
            }
        }
        return objects
    }

    private func tablePixels(_ document: RenderedDocument, rect: CGRect) throws -> Data {
        let width = Int(rect.width * 2)
        let height = Int(rect.height * 2)
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        document.drawTable(at: 0, in: context, rect: rect)
        return Data(bytes: try #require(context.data), count: context.bytesPerRow * context.height)
    }
}
