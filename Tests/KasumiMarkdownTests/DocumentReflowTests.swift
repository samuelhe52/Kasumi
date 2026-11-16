import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import KasumiMarkdown

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
            #expect(cached.height == fresh.height)
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

    @Test(.enabled(if: ProcessInfo.processInfo.environment["KASUMI_REFLOW_TIMING"] == "1"))
    func macReflowTimings() async {
        let samples = [
            (
                "English",
                "The reader should reflow text smoothly while the window changes size. Words and punctuation remain clear, and the reading position stays stable. "
            ),
            ("Chinese", "窗口大小改变时，阅读器应当流畅地重新排列文字。中文标点、字体和段落之间的距离都应保持准确；拖动窗口边缘，不应出现明显延迟。阅读位置需要保持稳定，不能随着每次换行不断向前移动。")
        ]
        let style = RenderStyle(fontSize: 16, widthLimit: nil)
        for count in [2000, 10000, 50000] {
            for (language, sentence) in samples {
                let paragraph = String(String(repeating: sentence, count: 500 / sentence.count + 1).prefix(500))
                let doc = MarkdownDocument(
                    markdown: Array(repeating: paragraph, count: count / 500).joined(separator: "\n\n"))
                let session = DocumentReflowSession(doc, style: style)
                _ = await session.render(width: 600)
                var timings: [Double] = []
                for width: CGFloat in [800, 500, 400, 700, 440] {
                    let start = ContinuousClock.now
                    let snapshot = await session.render(width: width)
                    let elapsed = start.duration(to: .now).components
                    timings.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
                    #expect(snapshot.size.height > 0)
                }
                print("REFLOW \(language) chars=\(count) median-ms=\(timings.sorted()[2]) max-ms=\(timings.max()!)")
            }
        }
    }
}
