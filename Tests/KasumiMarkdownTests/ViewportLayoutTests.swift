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
        for (width, target) in [(CGFloat(320), 0), (800, 40), (400, 79)] {
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

    @Test func textBlocksFallbackAndSnapshotExportsPreserveExactOutput() async throws {
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
            #expect(!result.hasEstimatedGeometry)
            let exact = RenderedDocument(doc, width: 400, style: style)
            #expect(result.size == exact.size)
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
}
