import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import KasumiMarkdown

#if os(macOS)
    import Darwin
#endif


@Suite struct DocumentReflowTests {
    private var source: String {
        """
        # 中文标题 English

        中文连续文字𠀀汉\u{0301}字与 English office [链接](https://example.com)，**强调文字**，`code` $\\frac{1}{3}$。

        > 引用与 Arabic مرحبا بالعالم。

        1. A numbered list with 中文。
        2. Another item.

        ```swift
        let value = "中文"
        ```

        | 标题 | English |
        | --- | ---: |
        | 长单元格中文内容和 office | [link](https://example.org) |

        ![small image](images/tiny.png)
        """
    }

    @Test func preparationReusesTextAndShapesWithoutChangingGeometry() {
        let parsed = DocumentParser.parse(source, baseURL: testRepositoryURL.appendingPathComponent("fixtures"))
        let cache = ReflowPreparation()
        let style = RenderStyle(fontSize: 16, widthLimit: nil).typography
        let warm = DocumentTypesetter.layout(
            parsed, width: 600, style: style, scrollableTables: true, preparation: cache)
        var mathObjects: [MathAttachment] = []
        warm.text.enumerateAttribute(.kasumiMath, in: NSRange(location: 0, length: warm.text.length)) { value, _, _ in
            if let value = value as? MathAttachment { mathObjects.append(value) }
        }
        #expect(!mathObjects.isEmpty)
        #expect(warm.semanticContent != nil && cache.semanticBuilds == 1)
        let builds = (cache.attributedBuilds, cache.shapedBuilds)
        #expect(builds.0 > 0 && builds.1 > 0)
        for width: CGFloat in [100, 320, 800, 440, 600] {
            let cached = DocumentTypesetter.layout(
                parsed, width: width, style: style, scrollableTables: true, preparation: cache)
            let fresh = DocumentTypesetter.layout(parsed, width: width, style: style, scrollableTables: true)
            cached.text.enumerateAttribute(.kasumiMath, in: NSRange(location: 0, length: cached.text.length)) {
                value, _, _ in
                if let value = value as? MathAttachment { #expect(!mathObjects.contains { $0 === value }) }
            }
            #expect(cached.semanticContent === warm.semanticContent)
            #expect(cached.textMap == DocumentTextMap(cached.text))
            #expect(cached.height == fresh.height)
            let cachedIndex = ReadingPositionIndex(layout: cached)
            let freshIndex = ReadingPositionIndex(layout: fresh)
            for y in stride(from: CGFloat(0), to: cached.height, by: 37) {
                #expect(cachedIndex.capture(y: y) == freshIndex.capture(y: y))
            }
            #expect(cached.textMap.string == fresh.textMap.string)
            #expect(cached.headingPositions == fresh.headingPositions)
            #expect(cached.anchorPositions == fresh.anchorPositions)
            #expect(cached.imageBounds == fresh.imageBounds)
            #expect(cached.paragraphs.count == fresh.paragraphs.count)
            for (a, b) in zip(cached.paragraphs, fresh.paragraphs) {
                #expect(a.origin == b.origin && a.textOffset == b.textOffset)
                #expect(a.paragraph.height == b.paragraph.height)
                #expect(a.paragraph.diagnostics == b.paragraph.diagnostics)
                #expect(a.paragraph.lines.count == b.paragraph.lines.count)
                for (x, y) in zip(a.paragraph.lines, b.paragraph.lines) {
                    #expect(x.range == y.range && x.origin == y.origin && x.width == y.width)
                    #expect(x.ascent == y.ascent && x.descent == y.descent)
                    #expect(x.adjustmentRatio == y.adjustmentRatio)
                    #expect(x.fragments.count == y.fragments.count)
                    for (f, g) in zip(x.fragments, y.fragments) {
                        #expect(f.range == g.range && f.x == g.x && f.width == g.width)
                        #expect(f.drawOffset == g.drawOffset && f.glyphInset == g.glyphInset)
                    }
                }
            }
        }
        #expect(cache.attributedBuilds == builds.0)
        #expect(cache.shapedBuilds == builds.1)
        #expect(cache.semanticBuilds == 1)
    }

    @Test func sessionSnapshotsKeepIndependentPixelsAndInteractions() async throws {
        let doc = MarkdownDocument(markdown: source, baseURL: testRepositoryURL.appendingPathComponent("fixtures"))
        let style = RenderStyle(fontSize: 16, widthLimit: nil)
        let session = DocumentReflowSession(doc, style: style, scrollableTables: true)
        let original = await session.render(width: 360)
        let originalPixels = try pixels(original)
        for width: CGFloat in [700, 320, 360] {
            let cached = await session.render(width: width)
            let fresh = RenderedDocument(doc, width: width, style: style, scrollableTables: true)
            #expect(cached.size == fresh.size)
            #expect(cached.text(in: cached.documentRange) == fresh.text(in: fresh.documentRange))
            #expect(try pixels(cached) == pixels(fresh))
            let range = try #require(cached.ranges(matching: "English").first)
            let expected = try #require(fresh.ranges(matching: "English").first)
            #expect(cached.selectionRects(for: range) == fresh.selectionRects(for: expected))
            #expect(cached.caretRect(for: range.lowerBound) == fresh.caretRect(for: expected.lowerBound))
        }
        #expect(try pixels(original) == originalPixels)
        let larger = DocumentReflowSession(doc, style: RenderStyle(fontSize: 24, widthLimit: nil))
        let changed = await larger.render(width: 360)
        #expect(changed.size.height != original.size.height)
    }

    @Test func semanticCacheInvalidatesForChangedRenderedOffsetsWithIdenticalText() {
        let cache = ReflowPreparation()
        func mappedContent(_ attributed: NSAttributedString) -> DocumentSemanticContent {
            let paragraph = ParagraphLayout(
                attributed: attributed, lines: [], height: 0, semanticContent: ParagraphSemanticContent(attributed))
            let storage = NSMutableAttributedString(attributedString: attributed)
            storage.append(NSAttributedString(string: "\n"))
            return cache.semanticContent(
                paragraphs: [PlacedText(paragraph: paragraph, origin: .zero, textOffset: 0)], storage: storage)
        }
        func content(_ source: String) -> DocumentSemanticContent {
            mappedContent(NSAttributedString(string: source, attributes: [.kasumiSemanticText: "alt"]))
        }
        let fallback = content("Image unavailable: alt")
        let loaded = content("\u{FFFC}")
        #expect(fallback.text == loaded.text && loaded.text == "alt")
        #expect(fallback !== loaded)
        #expect(fallback.textMap.renderedOffset(forSemanticOffset: 3) == "Image unavailable: alt".utf16.count)
        #expect(loaded.textMap.renderedOffset(forSemanticOffset: 3) == 1)
        #expect(content("\u{FFFC}") === loaded)
        #expect(cache.semanticBuilds == 2)
        // Same semantic text AND rendered length can still hide different maps.
        let leadingObject = NSMutableAttributedString(string: "\u{FFFC}c")
        leadingObject.addAttribute(.kasumiSemanticText, value: "ab", range: NSRange(location: 0, length: 1))
        let trailingObject = NSMutableAttributedString(string: "a\u{FFFC}")
        trailingObject.addAttribute(.kasumiSemanticText, value: "bc", range: NSRange(location: 1, length: 1))
        let leading = mappedContent(leadingObject)
        let trailing = mappedContent(trailingObject)
        #expect(leading.text == "abc" && leading.text == trailing.text)
        #expect(leading !== trailing)
        #expect(leading.textMap.semanticOffset(forRenderedOffset: 1) == 2)
        #expect(trailing.textMap.semanticOffset(forRenderedOffset: 1) == 1)
        #expect(cache.semanticBuilds == 4)
    }

    @Test func preparedItemsRespectWidthsOptionsAndIndentWithoutStickyDiagnostics() throws {
        let style = RenderStyle(fontSize: 16).typography
        let source = style.attributed([InlineRun("中文 English office、段落文字 and more words. ")])
        let prepared = ParagraphPreparation(source, fontSize: 16, verbatim: false)
        let input = try #require(prepared.input)
        var changed = ParagraphProfileOptions(values: style.profileValues)
        changed.cjkLatinGap = 0
        let settings: [(Float, ParagraphProfileOptions)] = [(0, .init()), (16, .init()), (16, changed)]
        for (index, setting) in settings.enumerated() {
            for width: Float in [800, 90, 300, 12, 440, 800] {
                let items = try #require(prepared.items(indent: setting.0, options: setting.1))
                let cached = ParagraphEngine.layout(items, width: width, outerWidth: width, baseEm: 16)
                let fresh = ParagraphEngine.layout(
                    clusters: input.clusters, runs: input.metrics, width: width, outerWidth: width, baseEm: 16,
                    indent: setting.0, options: setting.1)
                #expect(cached == fresh)
                #expect(prepared.itemBuilds == index + 1)
            }
        }
        let invalid = ParagraphEngine.prepare(clusters: input.clusters, runs: input.metrics, indent: .nan)
        #expect(ParagraphEngine.layout(invalid, width: 300, outerWidth: 300, baseEm: 16).diagnostics == [.invalidInput])
        let valid = try #require(prepared.items(indent: 0, options: .init()))
        #expect(ParagraphEngine.layout(valid, width: .nan, outerWidth: 300, baseEm: 16).diagnostics == [.invalidInput])
    }

    @Test func decorationCandidatesMatchForcedDecorationGeometry() {
        let style = Typography()
        let source = "ag 中文𠀀汉\u{0301} office and more words to wrap"
        let cases: [([NSAttributedString.Key: Any], Bool)] = [
            ([:], false), ([.underlineStyle: 0], false),
            ([.underlineStyle: 1], true),
            ([NSAttributedString.Key(kCTUnderlineStyleAttributeName as String): 1], true),
            ([.kasumiUnderline: true], true), ([.link: "https://example.com"], true), ([.link: "#target"], true)
        ]
        for (attributes, expectedCandidate) in cases {
            let destination = attributes[.link] as? String
            let attributed = NSMutableAttributedString(
                attributedString: style.attributed([
                    InlineRun(source, traits: destination == nil ? [] : [.link], destination: destination)
                ]))
            attributed.addAttributes(attributes, range: NSRange(location: 0, length: attributed.length))
            let prepared = ParagraphPreparation(attributed, fontSize: 16, verbatim: false)
            #expect(prepared.hasDecorationCandidates == expectedCandidate)
            for width: CGFloat in [150, 400] {
                let actual = ParagraphTypesetter.layout(attributed, width: width, fontSize: 16, preparation: prepared)
                let forced = TextUnderline.applying(to: actual, fontSize: 16, hasCandidates: true)
                #expect(actual.underlines.count == forced.underlines.count)
                for (a, b) in zip(actual.underlines, forced.underlines) {
                    #expect(a.rect == b.rect && a.color.cgColor == b.color.cgColor && a.radius == b.radius)
                }
                if expectedCandidate { #expect(!actual.underlines.isEmpty) }
            }
        }
    }

    private func pixels(_ snapshot: RenderedDocument) throws -> [UInt8] {
        let width = Int(snapshot.size.width)
        let height = min(800, Int(ceil(snapshot.size.height)))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        snapshot.draw(in: context, rect: CGRect(x: 0, y: 0, width: width, height: height))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }

    #if os(macOS)
        /// Measures the complete handoff sequence without UIKit. The old snapshot
        /// survives construction and viewport painting, then is explicitly released.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["KASUMI_REFLOW_TIMING"] == "1"))
        func macReflowTimings() async throws {
            let environment = ProcessInfo.processInfo.environment
            let repetitions = max(20, Int(environment["KASUMI_REFLOW_SAMPLES"] ?? "20") ?? 20)
            let samples = [
                (
                    "English",
                    "The reader should reflow text smoothly while the window changes size. Words and punctuation remain clear, and the reading position stays stable. "
                ),
                ("Chinese", "窗口大小改变时，阅读器应当流畅地重新排列文字。中文标点、字体和段落之间的距离都应保持准确；拖动窗口边缘，不应出现明显延迟。阅读位置需要保持稳定，不能随着每次换行不断向前移动。")
            ]
            let style = RenderStyle(fontSize: 16, widthLimit: nil)
            for count in [10000, 50000] {
                if let selected = environment["KASUMI_REFLOW_CHARACTERS"], selected != String(count) { continue }
                for (language, sentence) in samples {
                    if let selected = environment["KASUMI_REFLOW_LANGUAGE"], selected != language { continue }
                    let paragraph = String(String(repeating: sentence, count: 500 / sentence.count + 1).prefix(500))
                    let doc = MarkdownDocument(
                        markdown: Array(repeating: paragraph, count: count / 500).joined(separator: "\n\n"))
                    let session = DocumentReflowSession(doc, style: style)
                    var previous: RenderedDocument? = await session.render(width: 600)
                    var construction = [[Double]](repeating: [], count: 5)
                    var disposal = construction
                    var painting = construction
                    let widths: [CGFloat] = [800, 500, 400, 700, 440]
                    let contexts = try widths.map { width in
                        try #require(
                            CGContext(
                                data: nil, width: Int(width * 2), height: 1600, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    }
                    // Warm viewport glyph rasterization independently of the timed samples.
                    paint(try #require(previous), context: contexts[0], width: 600)
                    for _ in 0..<repetitions {
                        for (index, width) in widths.enumerated() {
                            let start = ContinuousClock.now
                            var next: RenderedDocument? = await session.render(width: width)
                            construction[index].append(milliseconds(since: start))
                            let paintStart = ContinuousClock.now
                            paint(try #require(next), context: contexts[index], width: width)
                            painting[index].append(milliseconds(since: paintStart))
                            let releaseStart = ContinuousClock.now
                            releaseSnapshot(&previous)
                            disposal[index].append(milliseconds(since: releaseStart))
                            previous = next
                            releaseSnapshot(&next)
                        }
                    }
                    releaseSnapshot(&previous)
                    var usage = rusage()
                    let status = getrusage(RUSAGE_SELF, &usage)
                    let rss = status == 0 ? Double(usage.ru_maxrss) / (1024 * 1024) : -1
                    for (index, width) in widths.enumerated() {
                        print(
                            "REFLOW_PHASE \(language) chars=\(count) width=\(width) n=\(repetitions) construct=\(stats(construction[index])) dispose=\(stats(disposal[index])) draw=\(stats(painting[index]))"
                        )
                    }
                    print(
                        "REFLOW_SUMMARY \(language) chars=\(count) n=\(repetitions * widths.count) construct=\(stats(construction.flatMap { $0 })) dispose=\(stats(disposal.flatMap { $0 })) draw=\(stats(painting.flatMap { $0 })) process-peak-rss-mib=\(rss)"
                    )
                }
            }
        }

        private func milliseconds(since start: ContinuousClock.Instant) -> Double {
            let elapsed = start.duration(to: .now).components
            return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        }

        private func stats(_ values: [Double]) -> String {
            let sorted = values.sorted()
            return
                "p50:\(sorted[sorted.count / 2]),p95:\(sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]),max:\(sorted.last!)"
        }

        @inline(never) private func releaseSnapshot(_ snapshot: inout RenderedDocument?) {
            snapshot = nil
        }

        private func paint(_ snapshot: RenderedDocument, context: CGContext, width: CGFloat) {
            let top = max(0, (snapshot.size.height - 800) / 2)
            let rect = CGRect(x: 0, y: top, width: width, height: 800)
            context.saveGState()
            context.scaleBy(x: 2, y: 2)
            context.translateBy(x: 0, y: 800)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0, y: -top)
            snapshot.draw(in: context, rect: rect)
            context.restoreGState()
        }
    #endif
}
