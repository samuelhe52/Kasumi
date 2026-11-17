import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing

@testable import KasumiMarkdown

@Suite struct CodeBlockPresentationTests {
    @Test func copyPayloadAndCaptionsStayOutsideSemanticText() throws {
        let code = "\tlet café = \"👩‍💻\";\n\n"
        let source =
            "```RuSt title=example\n" + code
            + "```\n\n```\nplain\n```\n\n```unknown-language\nliteral\n```\n\n```swift\n```"
        let document = MarkdownDocument(markdown: source)
        let rendered = RenderedDocument(
            document, width: 360, style: RenderStyle(codeBlockStyle: ReaderCodeBlockStyle.reading))
        #expect(rendered.codeBlocks.map(\.language) == ["RuSt", nil, "unknown-language", "swift"])
        #expect(rendered.codeBlocks[0].source == code)
        #expect(rendered.codeBlocks[1].source == "plain\n")
        #expect(rendered.codeBlocks[2].source == "literal\n")
        #expect(rendered.codeBlocks[3].source.isEmpty)
        #expect(Set(rendered.codeBlocks.map(\.id)).count == 4)
        #expect(rendered.ranges(matching: "Rust").isEmpty)
        #expect(rendered.ranges(matching: "unknown-language").isEmpty)
        #expect(!rendered.text(in: rendered.documentRange).contains("Copy"))
        let match = try #require(rendered.ranges(matching: "café").first)
        #expect(rendered.text(in: match) == "café")
        #expect(
            rendered.selectionRects(for: match).allSatisfy {
                $0.minY >= rendered.codeBlocks[0].contentFrame.minY
            })
    }

    @Test func readerOwnsControlGeometryAndSelectsDifferentExportStyling() throws {
        let document = DocumentParser.parse("```" + String(repeating: "long-language", count: 10) + "\nlet x = 1;\n```")
        for width: CGFloat in [60, 180, 360] {
            var style = Typography()
            style.codeBlockStyle = ReaderCodeBlockStyle.reading
            let layout = DocumentTypesetter.layout(document, width: width, style: style, insets: .zero)
            let code = try #require(layout.codeBlocks.first)
            let button = try #require(ReaderCodeBlockStyle.copyButtonFrame(in: code.block))
            #expect(code.block.frame.contains(button))
            #expect(button.height == 36 && button.width == 44)
            let labelFrame = try #require(code.labelFrame)
            #expect(labelFrame.isEmpty || labelFrame.maxX <= button.minX)
            #expect(code.block.contentFrame.minY >= button.maxY)
            if let label = code.label {
                #expect(CTLineGetTypographicBounds(label, nil, nil, nil) <= labelFrame.width + 0.01)
            }
            style.codeBlockStyle = ReaderCodeBlockStyle.exporting
            let exported = DocumentTypesetter.layout(document, width: width, style: style, insets: .zero)
            let compact = try #require(exported.codeBlocks.first)
            #expect(compact.block.captionFrame?.height == 28)
            #expect(ReaderCodeBlockStyle.copyButtonFrame(in: compact.block) == nil)
            #expect(exported.height < layout.height)
        }
    }

    @Test func publicStylesKeepDefaultsIndependentAndCaptionsOptional() throws {
        let document = MarkdownDocument(markdown: "```rust\nlet x = 1;\n```")
        let basic = RenderedDocument(document, width: 360, style: RenderStyle())
        let normal = try #require(basic.codeBlocks.first)
        #expect(normal.captionFrame == nil)
        #expect(abs(normal.contentFrame.minY - normal.frame.minY - 10) < 0.001)
        #expect(abs(normal.frame.maxY - normal.contentFrame.maxY - 10) < 0.001)
        #expect(ReaderCodeBlockStyle.copyButtonFrame(in: normal) == nil)

        let customStyle = CodeBlockStyle(
            drawsBackground: false, cornerRadius: 7,
            padding: .init(top: 5, left: 8, bottom: 3, right: 6), caption: .init(height: 31))
        let custom = RenderedDocument(document, width: 360, style: RenderStyle(codeBlockStyle: customStyle))
        let block = try #require(custom.codeBlocks.first)
        #expect(block.captionFrame?.height == 31)
        #expect(abs(block.contentFrame.minY - block.frame.minY - 36) < 0.001)
        #expect(abs(block.contentFrame.minX - block.frame.minX - 8) < 0.001)
        #expect(abs(block.frame.maxX - block.contentFrame.maxX - 6) < 0.001)
        #expect(abs(block.frame.maxY - block.contentFrame.maxY - 3) < 0.001)
        #expect(basic.text(in: basic.documentRange) == custom.text(in: custom.documentRange))
        #expect(normal.source == block.source)
        #expect(normal.captionFrame == nil)  // A second style never mutates a snapshot.
        var typography = RenderStyle(codeBlockStyle: customStyle).typography
        let noBackground = DocumentTypesetter.layout(document.parsed, width: 360, style: typography)
        #expect(noBackground.backgrounds.isEmpty)
        typography.codeBlockStyle.caption = nil
        let noCaption = DocumentTypesetter.layout(document.parsed, width: 360, style: typography)
        #expect(noCaption.codeBlocks[0].block.captionFrame == nil)
        #expect(abs(noBackground.height - noCaption.height - 31) < 0.001)
    }

    @Test(arguments: ["one-light", "one-dark"])
    func roundedCornersAndCaptionReachTheRaster(_ theme: String) throws {
        var style = Typography()
        style.codeBlockStyle = CodeBlockStyle(
            backgroundColor: DocumentColor(red: 0.1, green: 0.4, blue: 0.7), cornerRadius: 10, caption: .init())
        style.dark = theme.hasSuffix("dark")
        if style.dark { style.darkThemeID = theme } else { style.lightThemeID = theme }
        let document = DocumentParser.parse("```rust\nlet value = 42;\n```")
        let layout = DocumentTypesetter.layout(document, width: 360, style: style)
        let code = try #require(layout.codeBlocks.first)
        let width = 360
        let height = Int(ceil(layout.height))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(style.paperColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        DocumentTypesetter.draw(layout, in: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        func rgb(_ color: PlatformColor) throws -> [Int] {
            let color = try #require(color.kasumiSRGB)
            return [color.redComponent, color.greenComponent, color.blueComponent].map { Int(round($0 * 255)) }
        }
        func matches(_ x: Int, _ y: Int, _ rgb: [Int]) -> Bool {
            let offset = (y * width + x) * 4
            return (0..<3).allSatisfy { abs(Int(bytes[offset + $0]) - rgb[$0]) <= 3 }
        }
        let frame = code.block.frame
        let paper = try rgb(style.paperColor)
        let background = try rgb(try #require(style.codeBlockStyle.backgroundColor?.nsColor))
        #expect(matches(Int(frame.minX) + 1, Int(frame.minY) + 1, paper))
        #expect(matches(Int(frame.maxX) - 2, Int(frame.maxY) - 2, paper))
        #expect(matches(Int(frame.midX), Int(frame.minY) + 2, background))
        let caption = try rgb(style.secondaryColor)
        var captionPixels = 0
        let labelFrame = try #require(code.labelFrame)
        for y in Int(labelFrame.minY)..<Int(labelFrame.maxY) {
            for x in Int(labelFrame.minX)..<Int(labelFrame.maxX) where matches(x, y, caption) {
                captionPixels += 1
            }
        }
        #expect(captionPixels > 5)
        style.codeBlockStyle.drawsBackground = false
        let unpainted = DocumentTypesetter.layout(document, width: 360, style: style)
        context.setFillColor(style.paperColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        DocumentTypesetter.draw(unpainted, in: context)
        #expect(matches(Int(frame.midX), Int(frame.minY) + 2, paper))
    }

    @Test func paginationKeepsHeaderWithFirstLineWithoutShrinkingLongBlocks() throws {
        let lines = (0..<30).map { "let value_\($0) = \($0);" }.joined(separator: "\n")
        let document = DocumentParser.parse("Before.\n\n```rust\n" + lines + "\n```\n\nAfter.")
        var style = Typography()
        style.codeBlockStyle = ReaderCodeBlockStyle.exporting
        let layout = DocumentTypesetter.layout(document, width: 360, style: style, insets: .zero)
        let code = try #require(layout.codeBlocks.first)
        let paragraph = try #require(
            layout.paragraphs.first { $0.paragraph.attributed.string.hasPrefix("let value_0") })
        let first = try #require(paragraph.paragraph.lines.first)
        let firstBottom = paragraph.origin.y + first.origin.y + first.descent
        let pages = try DocumentPaginator.pages(for: layout, contentHeight: code.block.frame.minY + 48)
        #expect(pages.count > 2)
        #expect(pages.allSatisfy { abs($0.scale - 1) < 0.001 })
        #expect(!pages.contains { $0.range.upperBound > code.block.frame.minY && $0.range.upperBound < firstBottom })
        #expect(pages.last!.range.upperBound >= code.block.frame.maxY)
        #expect(pages.dropFirst().contains { $0.continuationHeader != nil })
        for page in pages {
            let headerHeight = page.continuationHeader.map { $0.upperBound - $0.lowerBound } ?? 0
            #expect((page.range.upperBound - page.range.lowerBound + headerHeight) * page.scale <= code.block.frame.minY + 48 + 0.001)
        }
    }

    @Test func pdfContinuationCaptionsPreserveEveryLineOnShortAndNormalPages() throws {
        let lines = (0..<35).map { String(format: "item_%03d", $0) }
        let source = "Before.\n\n```rust\n" + lines.joined(separator: "\n") + "\n```\n\n```python\nlast_marker\n```\n\nAfter."
        let document = MarkdownDocument(markdown: source)
        let style = RenderStyle(codeBlockStyle: ReaderCodeBlockStyle.exporting)
        for height: CGFloat in [50, 100, 200] {
            let data = try DocumentExport.pdf(document, style: style, pageSize: CGSize(width: 250, height: height), margins: .zero)
            let pdf = try #require(PDFDocument(data: data))
            var text = ""
            for index in 0..<pdf.pageCount {
                let page = try #require(pdf.page(at: index))
                let content = page.string ?? ""
                text += content + "\n"
                if content.contains("item_") {
                    #expect(content.components(separatedBy: "Rust").count == 2)
                    let caption = try #require(pdf.findString("Rust", withOptions: []).first { $0.pages.contains(page) }?.bounds(for: page))
                    let firstMarker = lines.first { content.contains($0) }!
                    let code = try #require(pdf.findString(firstMarker, withOptions: []).first { $0.pages.contains(page) }?.bounds(for: page))
                    #expect(caption.minY >= code.maxY - 0.1, "Caption and code must not overlap")
                }
            }
            for line in lines + ["Before.", "After.", "last_marker"] {
                #expect(text.components(separatedBy: line).count == 2, "Every source line appears exactly once: \(line)")
            }
            #expect(text.components(separatedBy: "Python").count == 2)
        }
    }
}
