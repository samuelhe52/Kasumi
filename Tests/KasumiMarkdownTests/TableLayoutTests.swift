import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing

@testable import KasumiMarkdown

fileprivate func tableFixture() throws -> MarkdownDocument {
    let url = testRepositoryURL.appendingPathComponent("fixtures/Tables.md")
    return MarkdownDocument(markdown: try String(contentsOf: url, encoding: .utf8))
}

@Suite struct TableLayoutTests {
    @Test func verboseCellsDoNotStarveShortColumnsAndHeadersUseTheirPaintedFont() throws {
        let style = Typography()
        let source = """
            | Description | MMMM | Count |
            | --- | --- | ---: |
            | \(String(repeating: "A long description with several words. ", count: 5)) | a | 12 |
            """
        let layout = DocumentTypesetter.layout(DocumentParser.parse(source), width: 520, style: style, insets: .zero)
        let header = try #require(layout.paragraphs.first { $0.paragraph.attributed.string == "MMMM" })
        let count = try #require(layout.paragraphs.first { $0.paragraph.attributed.string == "Count" })
        let secondWidth = count.origin.x - header.origin.x
        let paintedWidth = CGFloat(
            CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(header.paragraph.attributed), nil, nil, nil))
        #expect(secondWidth >= paintedWidth + style.size * 1.2 - 0.01)
        #expect(secondWidth < style.size * 6)
        #expect(header.paragraph.lines.count == 1)
        #expect(layout.tables[0].contentWidth <= 520)
        let description = try #require(layout.paragraphs.first { $0.paragraph.attributed.string.hasPrefix("A long") })
        #expect(description.paragraph.lines.allSatisfy { $0.width <= header.origin.x - description.origin.x })
    }

    @Test func narrowReaderOverflowsButRoomyPagesAndFileExportsFit() throws {
        let document = try tableFixture()
        let style = RenderStyle(fontSize: 16, widthLimit: nil, insets: .init(top: 20, left: 20, bottom: 20, right: 20))
        let narrow = RenderedDocument(document, width: 360, style: style, scrollableTables: true)
        let wide = RenderedDocument(document, width: 1000, style: style, scrollableTables: true)
        let fitted = RenderedDocument(document, width: 360, style: style)
        #expect(narrow.tables.count == 4)
        #expect(narrow.tables[0].isScrollable)
        #expect(narrow.tables[1].isScrollable)
        #expect(!narrow.tables[2].isScrollable)
        #expect(wide.tables.allSatisfy { !$0.isScrollable })
        #expect(fitted.tables.allSatisfy { !$0.isScrollable })
        #expect(fitted.tables.allSatisfy { $0.frame.maxX <= 340.01 })
        #expect(narrow.size.width == 360)
        #expect(narrow.text(in: narrow.documentRange) == fitted.text(in: fitted.documentRange))
        #expect(narrow.size.height < fitted.size.height)
        // Fitted PDF layout must retain offscreen reader columns.
        let pdf = try #require(PDFDocument(data: DocumentExport.pdf(document, style: style)))
        let extracted = (pdf.string ?? "").replacingOccurrences(of: "-\n", with: "")
        #expect(extracted.contains("Final result"))
        #expect(pdf.string?.contains("Final column") == true)
    }

    @Test func tableContentBeyondPageCanPaintAndKeepsSemanticLinksAndCarets() throws {
        let document = try tableFixture()
        let style = RenderStyle(fontSize: 16, insets: .init(top: 20, left: 20, bottom: 20, right: 20))
        let rendered = RenderedDocument(document, width: 360, style: style, scrollableTables: true)
        let table = rendered.tables[1]
        let match = try #require(rendered.ranges(matching: "Final result").first)
        let rect = try #require(rendered.selectionRects(for: match).first)
        #expect(rect.maxX > table.frame.maxX)
        #expect(rendered.link(at: CGPoint(x: rect.midX, y: rect.midY))?.absoluteString == "https://example.com/final")
        let caret = rendered.caretRect(for: match.lowerBound)
        #expect(rendered.position(closestTo: CGPoint(x: caret.minX, y: caret.midY)) == match.lowerBound)

        let contentSize = CGSize(width: ceil(table.contentWidth), height: ceil(table.frame.height))
        let full = try tablePixels(size: contentSize) { context in
            rendered.drawTable(at: table.id, in: context, rect: CGRect(origin: .zero, size: contentSize))
        }
        let tiled = try tablePixels(size: contentSize) { context in
            for x in stride(from: CGFloat(0), to: contentSize.width, by: 160) {
                rendered.drawTable(
                    at: table.id, in: context,
                    rect: CGRect(x: x, y: 0, width: min(160, contentSize.width - x), height: contentSize.height))
            }
        }
        #expect(full == tiled)
        // Removing table paint from the page must also remove header backgrounds
        // and rules, while the independent table still paints the final column.
        let page = try tablePixels(size: rendered.size) {
            rendered.draw(in: $0, rect: CGRect(origin: .zero, size: rendered.size), excludingScrollableTables: true)
        }
        let sampleX = Int(rect.midX - table.frame.minX)
        let sampleY = Int(rect.midY - table.frame.minY)
        let ink = (max(0, sampleY - 8)...min(Int(contentSize.height) - 1, sampleY + 8)).contains { y in
            (max(0, sampleX - 20)...min(Int(contentSize.width) - 1, sampleX + 20)).contains { x in
                full[(y * Int(contentSize.width) + x) * 4] < 200
            }
        }
        #expect(ink)
        let blank = (Int(table.frame.minY + 2)..<Int(table.frame.maxY - 2)).allSatisfy { y in
            (Int(table.frame.minX + 2)..<Int(table.frame.maxX - 2)).allSatisfy { x in
                let offset = (y * Int(ceil(rendered.size.width)) + x) * 4
                return page[offset..<(offset + 4)].elementsEqual(page[0..<4])
            }
        }
        #expect(blank)
        let visiblePage = try tablePixels(size: rendered.size) {
            rendered.draw(in: $0, rect: CGRect(origin: .zero, size: rendered.size))
        }
        #expect(
            (Int(table.frame.minY)..<Int(table.frame.maxY)).allSatisfy { y in
                (342..<358).allSatisfy { x in
                    let offset = (y * Int(ceil(rendered.size.width)) + x) * 4
                    return visiblePage[offset..<(offset + 4)].elementsEqual(visiblePage[0..<4])
                }
            })
    }
}

fileprivate func tablePixels(size: CGSize, draw: (CGContext) -> Void) throws -> [UInt8] {
    let width = Int(ceil(size.width))
    let height = Int(ceil(size.height))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
        let context = try #require(
            CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(context)
    }
    return pixels
}
