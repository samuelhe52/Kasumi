import Foundation
import Testing

@testable import KasumiMarkdown

@Suite struct SelectionLookupTests {
    @Test func semanticLookupPreservesObjectsEmptyPaddingAndUTF16Boundaries() {
        let parts: [(String, String?)] = [
            ("\u{FFFC}", ""), ("A👩‍👩‍👧‍👦e\u{301} ", nil),
            ("\u{FFFC}", "x_i"), ("\u{FFFC}", "x_i"),
            ("\u{FFFC}", ""), ("code", nil), ("\u{FFFC}", ""),
            ("漢\u{FFFC}", "replacement"), (" 中文", nil), ("\u{FFFC}", "")
        ]
        let source = NSMutableAttributedString(string: "")
        var spans: [(rendered: NSRange, semantic: NSRange, replacement: Bool)] = []
        var semantic = ""
        for (text, replacement) in parts {
            let part = NSAttributedString(
                string: text, attributes: replacement.map { [.kasumiSemanticText: $0] } ?? [:])
            spans.append(
                (
                    NSRange(location: source.length, length: part.length),
                    NSRange(location: semantic.utf16.count, length: (replacement ?? text).utf16.count),
                    replacement != nil
                ))
            semantic += replacement ?? text
            source.append(part)
        }
        let map = DocumentTextMap(source)
        #expect(map.string == semantic)
        for offset in 0...semantic.utf16.count {
            let expected =
                spans.first { NSLocationInRange(offset, $0.semantic) }.map {
                    $0.rendered.location + ($0.replacement ? 0 : offset - $0.semantic.location)
                } ?? source.length
            #expect(map.renderedOffset(forSemanticOffset: offset) == expected)
            for length in 0...(semantic.utf16.count - offset) {
                let selected = NSRange(location: offset, length: length)
                let overlaps = spans.compactMap { span -> NSRange? in
                    let overlap = NSIntersectionRange(selected, span.semantic)
                    guard overlap.length > 0 else { return nil }
                    return span.replacement
                        ? span.rendered
                        : NSRange(
                            location: span.rendered.location + overlap.location - span.semantic.location,
                            length: overlap.length)
                }
                let expected = overlaps.first.map { first in
                    NSRange(location: first.location, length: NSMaxRange(overlaps.last!) - first.location)
                }
                #expect(map.renderedRange(for: selected) == expected)
            }
        }
        for offset in 0...source.length {
            for length in 0...(source.length - offset) {
                let selected = NSRange(location: offset, length: length)
                let overlaps = spans.compactMap { span -> NSRange? in
                    let overlap = NSIntersectionRange(selected, span.rendered)
                    guard overlap.length > 0 else { return nil }
                    let semantic =
                        span.replacement
                        ? span.semantic
                        : NSRange(
                            location: span.semantic.location + overlap.location - span.rendered.location,
                            length: overlap.length)
                    return semantic.length > 0 ? semantic : nil
                }
                let expected = overlaps.first.map { first in
                    NSRange(location: first.location, length: NSMaxRange(overlaps.last!) - first.location)
                }
                #expect(map.semanticRange(forRenderedRange: selected) == expected)
            }
        }
        let empty = DocumentTextMap(NSAttributedString(string: ""))
        #expect(empty.renderedRange(for: NSRange(location: 0, length: 0)) == nil)
        #expect(empty.renderedOffset(forSemanticOffset: 0) == 0)
    }

    @Test func indexedSelectionsMatchExhaustiveGeometryAcrossFullAndViewportLayouts() throws {
        let body = (0..<24).map {
            "Paragraph \($0). 中文𠀀汉\u{301} with office words and 👩‍👩‍👧‍👦. "
                + String(repeating: "[link](https://example.com) and `code` continue. ", count: 2)
        }
        let middle = """
            | A long table heading | Another heading |
            | --- | --- |
            | $x_i+1$ and text | 中文 table cell that wraps |
            | More words in the next row | Final cell |

            Text with $\\frac{1}{2}$ and ![missing image](missing.png).

            ```swift

            let value = 1

            print(value)
            ```

            العربية עברית mixed RTL text.

            Hard break here.\u{20}\u{20}
            And another line.
            """
        let document = MarkdownDocument(
            markdown:
                body.prefix(12).joined(separator: "\n\n") + "\n\n" + middle + "\n\n"
                + body.suffix(12).joined(separator: "\n\n"))
        let style = RenderStyle(fontSize: 16, widthLimit: nil)
        for width: CGFloat in [260, 520] {
            let full = RenderedDocument(document, width: width, style: style, scrollableTables: true)
            let anchor = full.readingAnchor(atY: full.size.height * 0.5)
            for viewport in [false, true] {
                let request = viewport ? ViewportLayoutRequest(height: 300, anchor: anchor) : nil
                let snapshot = RenderedDocument(
                    document, width: width, style: style, scrollableTables: true,
                    preparation: ReflowPreparation(), viewport: request)
                let reference: DocumentLayout
                if let request {
                    reference = DocumentTypesetter.viewportLayout(
                        document.parsed, width: width,
                        style: style.typography, insets: style.insets, scrollableTables: true,
                        preparation: ReflowPreparation(), request: request)
                    #expect(snapshot.hasEstimatedGeometry)
                } else {
                    reference = DocumentTypesetter.layout(
                        document.parsed, width: width,
                        style: style.typography, insets: style.insets, scrollableTables: true)
                }
                #expect(snapshot.size.height == reference.height)
                // Logical line intervals are source-ordered, including code's
                // empty rows and table cells placed at the same document Y.
                let ranges = reference.paragraphs.flatMap { item in
                    item.paragraph.lines.map {
                        NSRange(location: item.textOffset + $0.range.location, length: $0.range.length)
                    }
                }
                #expect(
                    zip(ranges, ranges.dropFirst()).allSatisfy {
                        $0.location <= $1.location && NSMaxRange($0) <= NSMaxRange($1)
                    })
                let count = try #require(
                    snapshot.offset(from: snapshot.documentRange.lowerBound, to: snapshot.documentRange.upperBound))
                var offsets = Set(stride(from: 0, through: count, by: 37))
                let paragraphRanges = reference.paragraphs.map {
                    NSRange(location: $0.textOffset, length: $0.paragraph.attributed.length)
                }
                for range in ranges + paragraphRanges {
                    for rendered in [range.location, NSMaxRange(range)] {
                        let semantic = reference.textMap.semanticOffset(forRenderedOffset: rendered)
                        offsets.insert(min(count, semantic))
                    }
                }
                for offset in offsets.sorted() {
                    for length in [0, 1, 12, 55, count - offset] {
                        let selected = NSRange(location: offset, length: min(length, count - offset))
                        let start = try #require(
                            snapshot.position(from: snapshot.documentRange.lowerBound, offset: selected.location))
                        let end = try #require(snapshot.position(from: start, offset: selected.length))
                        #expect(
                            snapshot.selectionRects(for: TextRange(start, end))
                                == exhaustiveRects(reference, semantic: selected))
                    }
                }
            }
        }
    }

    private func exhaustiveRects(_ layout: DocumentLayout, semantic: NSRange) -> [CGRect] {
        guard semantic.length > 0, let selected = layout.textMap.renderedRange(for: semantic) else { return [] }
        var measured: [CGRect] = []
        var estimated: [CGRect] = []
        for item in layout.paragraphs {
            for line in item.paragraph.lines {
                let range = NSRange(location: item.textOffset + line.range.location, length: line.range.length)
                let overlap = NSIntersectionRange(selected, range)
                guard overlap.length > 0 else { continue }
                let start = line.offset(forStringIndex: overlap.location - item.textOffset)
                let end = line.offset(
                    forStringIndex: NSMaxRange(overlap) - item.textOffset, affinity: .precedingFragment)
                measured.append(
                    CGRect(
                        x: item.origin.x + line.origin.x + min(start, end),
                        y: item.origin.y + line.origin.y - line.ascent, width: abs(end - start),
                        height: max(1, line.ascent + line.descent)))
            }
            if let estimate = item.paragraph.estimate {
                let range = NSRange(location: item.textOffset, length: item.paragraph.attributed.length)
                let overlap = NSIntersectionRange(selected, range)
                guard overlap.length > 0 else { continue }
                let unit = item.paragraph.height / CGFloat(max(1, range.length))
                estimated.append(
                    CGRect(
                        x: item.origin.x, y: item.origin.y + CGFloat(overlap.location - range.location) * unit,
                        width: estimate.width, height: max(1, CGFloat(overlap.length) * unit)))
            }
        }
        return estimated.isEmpty ? measured : (measured + estimated).sorted { $0.minY < $1.minY }
    }
}

#if os(macOS)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KASUMI_FIND_TIMING"] == "1"))
    func macFindTimings() async {
        func ms(_ start: ContinuousClock.Instant) -> Double {
            let d = start.duration(to: .now).components
            return Double(d.seconds) * 1000 + Double(d.attoseconds) / 1e15
        }
        func stats(_ values: [Double]) -> String {
            let a = values.sorted()
            return "p50=\(a[a.count / 2]) p95=\(a[Int(Double(a.count - 1) * 0.95)]) max=\(a.last!)"
        }
        let samples = [
            (
                "English",
                "The reader should reflow text smoothly while the window changes size. Words and punctuation remain clear, and the reading position stays stable. ",
                "text"
            ),
            ("Chinese", "窗口大小改变时，阅读器应当流畅地重新排列文字。中文标点、字体和段落之间的距离都应保持准确；拖动窗口边缘，不应出现明显延迟。阅读位置需要保持稳定，不能随着每次换行不断向前移动。", "文")
        ]
        for (language, sentence, query) in samples {
            for length in [500, 50] {
                let paragraph = String(String(repeating: sentence, count: length / sentence.count + 1).prefix(length))
                let document = MarkdownDocument(
                    markdown: Array(repeating: paragraph, count: 50000 / length).joined(separator: "\n\n"))
                let session = DocumentReflowSession(document, style: RenderStyle(fontSize: 16, widthLimit: nil))
                let full = await session.render(width: 500)
                let anchor = full.readingAnchor(atY: full.size.height * 0.5)
                let partial = await session.render(width: 500, viewportHeight: 800, anchor: anchor)
                for (mode, snapshot) in [("full", full), ("viewport", partial)] {
                    let ranges = snapshot.ranges(matching: query)
                    for range in ranges { _ = snapshot.selectionRects(for: range) }
                    var search: [Double] = []
                    var geometry: [Double] = []
                    var checksum: CGFloat = 0
                    for _ in 0..<30 {
                        let start = ContinuousClock.now
                        let found = snapshot.ranges(matching: query)
                        search.append(ms(start))
                        let next = ContinuousClock.now
                        for range in found {
                            for rect in snapshot.selectionRects(for: range) { checksum += rect.minY }
                        }
                        geometry.append(ms(next))
                    }
                    print(
                        "FIND_TIMING \(language) paragraphs=\(50000 / length) mode=\(mode) matches=\(ranges.count) search=\(stats(search)) geometry=\(stats(geometry)) checksum=\(checksum)"
                    )
                }
            }
        }
    }
#endif
