#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import CoreText
import Foundation
import PDFKit
import ImageIO
import Testing
@testable import KasumiMarkdown

@Test func typographyProfileMathOptionsReachInlineAndDisplayAttachments() throws {
    let values = ProfileValues([.mathFont: .string("newcm-book"), .mathRadicalGap: .number(2), .mathFracBarOverhang: .number(0.1)])
    let style = Typography().applying(values)
    let source = "\\frac{x}{y}+\\sqrt{z}"
    let inline = style.attributed([InlineRun(source, traits: [.math])])
    let attachment = try #require(inline.attribute(.kasumiMath, at: 0, effectiveRange: nil) as? MathAttachment)
    let expected = MathTypesetter.layout(source, size: 16, display: false, options: style.mathOptions)
    #expect(attachment.result.box.width == expected.box.width && attachment.result.box.ascent == expected.box.ascent)
    for drawing in attachment.result.box.drawings {
        if case let .glyph(font, _, _) = drawing { #expect(CTFontCopyPostScriptName(font) as String == "NewCMMath-Book") }
    }
    let document = DocumentParser.parse("$$\n" + source + "\n$$")
    let layout = DocumentTypesetter.layout(document, width: 500, style: style)
    let display = try #require(layout.text.attribute(.kasumiMath, at: 0, effectiveRange: nil) as? MathAttachment)
    let displayExpected = MathTypesetter.layout(source, size: 16, display: true, options: style.mathOptions)
    #expect(display.result.box.width == displayExpected.box.width && display.result.box.ascent == displayExpected.box.ascent)
}

@Test func typographyPagellaMissingSymbolShowsCompleteSearchableSource() throws {
    let style = Typography().applying(ProfileValues([.mathFont: .string("pagella-math")]))
    let source = "A \\subsetneqq B"
    let text = style.attributed([InlineRun(source, traits: [.math])])
    #expect(text.string == source)
    #expect(text.attribute(.kasumiMath, at: 0, effectiveRange: nil) == nil)
    #expect(DocumentTextMap(text).matches("subsetneqq").count == 1)
    let regular = Typography().attributed([InlineRun(source, traits: [.math])])
    #expect(regular.attribute(.kasumiMath, at: 0, effectiveRange: nil) is MathAttachment)
    #expect(DocumentTextMap(regular).string == source)
}

@Test func typographyPDFUsesPrintedSizeWhileReaderAndPNGKeepReadingSize() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = DocumentParser.parse("Printed words")
    let style = Typography().applying(ProfileValues([.baseSize: .number(30), .printBodySize: .number(9)]))
    let reader = DocumentTypesetter.layout(document, width: 500, style: style)
    #expect((reader.text.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.pointSize == 30)
    let url = directory.appendingPathComponent("printed.pdf")
    var options = PDFExportOptions(); options.pageNumbers = false
    try DocumentExporter.writePDF(document, style: style, options: options, to: url)
    let pdf = try #require(PDFDocument(url: url)), page = try #require(pdf.page(at: 0))
    let printed = try #require(page.attributedString)
    let position = (printed.string as NSString).range(of: "Printed").location
    #expect(position != NSNotFound)
    let font = try #require(printed.attribute(.font, at: position, effectiveRange: nil) as? PlatformFont)
    #expect(abs(font.pointSize - 9) < 0.01)
    let png = directory.appendingPathComponent("reading.png")
    try DocumentExporter.writeImage(document, style: style, width: 500, scale: 1, to: png)
    let source = try #require(CGImageSourceCreateWithURL(png as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(CGFloat(image.height) == ceil(reader.height))
}
