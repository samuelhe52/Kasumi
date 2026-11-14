#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import ImageIO
import UniformTypeIdentifiers
import CoreText

enum DocumentExportError: LocalizedError {
    case invalidGeometry, cannotCreateImage, cannotWriteImage, cannotCreatePDF, cannotWritePDF
    case imageTooLarge(width: Int, height: Int)
    var errorDescription: String? {
        switch self {
        case .invalidGeometry: "The export size or margins are invalid."
        case .cannotCreateImage: "Not enough memory for a picture this size. Lower the scale or width."
        case .cannotWriteImage: "The image could not be written."
        case .cannotCreatePDF: "The PDF could not be created."
        case .cannotWritePDF: "The PDF could not be written."
        case let .imageTooLarge(width, height): "The picture would be \(width)×\(height) pixels. Lower the scale or width, or export a PDF instead."
        }
    }
}

struct PDFExportOptions: Sendable {
    var paperSize = CGSize(width: 595.276, height: 841.89)
    var margins = DocumentInsets(top: 72, left: 72, bottom: 72, right: 72)
    var pageNumbers = true
    var footerTemplate = "{page}"
    var headerTemplate = ""
    var title = ""
    var date = Date()
    init() {}
}

enum DocumentExporter {
    static func writeImage(_ document: ParsedDocument, style: Typography, width: CGFloat, scale: CGFloat = 2, to url: URL) throws {
        guard width.isFinite, width > 0, scale.isFinite, scale > 0 else { throw DocumentExportError.invalidGeometry }
        let layout = DocumentTypesetter.layout(document, width: width, style: style)
        try writeImage(layout, style: style, scale: scale, to: url)
    }

    static func writeImage(_ layout: DocumentLayout, style: Typography, scale: CGFloat = 2, region: CGRect? = nil, to url: URL) throws {
        do { try imageData(layout, style: style, scale: scale, region: region).write(to: url, options: .atomic) }
        catch let error as DocumentExportError { throw error }
        catch { throw DocumentExportError.cannotWriteImage }
    }

    static func imageData(_ layout: DocumentLayout, style: Typography, scale: CGFloat = 2, region: CGRect? = nil) throws -> Data {
        let full = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
        let region = region ?? full
        guard region.width.isFinite, region.height.isFinite, region.width > 0, region.height > 0,
              region.minX.isFinite, region.minY.isFinite, scale.isFinite, scale > 0, (region.width * scale).isFinite, (region.height * scale).isFinite,
              region.width * scale < CGFloat(Int.max), region.height * scale < CGFloat(Int.max) else { throw DocumentExportError.invalidGeometry }
        let pixelWidth = Int(ceil(region.width * scale)), pixelHeight = Int(ceil(region.height * scale))
        guard pixelWidth <= 32768, pixelHeight <= 32768, Double(pixelWidth) * Double(pixelHeight) * 4 <= 512 * 1024 * 1024 else { throw DocumentExportError.imageTooLarge(width: pixelWidth, height: pixelHeight) }
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DocumentExportError.cannotCreateImage }
        context.translateBy(x: 0, y: CGFloat(pixelHeight)); context.scaleBy(x: scale, y: -scale)
        context.setFillColor(style.paperColor.cgColor); context.fill(CGRect(origin: .zero, size: region.size))
        context.translateBy(x: -region.minX, y: -region.minY)
        DocumentTypesetter.draw(layout, in: context)
        let data = NSMutableData()
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { throw DocumentExportError.cannotCreateImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw DocumentExportError.cannotWriteImage }
        return data as Data
    }

    static func writePDF(_ document: ParsedDocument, style: Typography, options: PDFExportOptions = PDFExportOptions(), to url: URL) throws {
        do { try pdfData(document, style: style, options: options).write(to: url, options: .atomic) }
        catch let error as DocumentExportError { throw error }
        catch { throw DocumentExportError.cannotWritePDF }
    }

    static func pdfData(_ document: ParsedDocument, style: Typography, options: PDFExportOptions = PDFExportOptions()) throws -> Data {
        let size = options.paperSize, m = options.margins
        let values = [size.width, size.height, m.top, m.left, m.bottom, m.right]
        let footerHeight: CGFloat = options.pageNumbers && !options.footerTemplate.isEmpty ? 24 : 0
        let headerHeight: CGFloat = options.headerTemplate.isEmpty ? 0 : 24
        let contentWidth = size.width - m.left - m.right
        let contentHeight = size.height - m.top - m.bottom - footerHeight - headerHeight
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }), contentWidth >= 20, contentHeight >= 20 else { throw DocumentExportError.invalidGeometry }
        var pageStyle = style
        pageStyle.limitWidth = false
        // Native active-style PDF uses the profile's printed body size rather
        // than the reading size/zoom, retaining families and relative scales.
        pageStyle.size = style.printBodySize
        let layout = DocumentTypesetter.layout(document, width: contentWidth, style: pageStyle, insets: .zero)
        let slices = try DocumentPaginator.pages(for: layout, contentHeight: contentHeight)
        let pages = slices.isEmpty ? [DocumentPageSlice(range: 0..<0, scale: 1)] : slices
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw DocumentExportError.cannotCreatePDF }
        var mediaBox = CGRect(origin: .zero, size: size)
        let metadata: [CFString: Any] = [kCGPDFContextTitle: options.title, kCGPDFContextCreator: "KasumiMarkdown"]
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata as CFDictionary) else { throw DocumentExportError.cannotCreatePDF }
        for (index, page) in pages.enumerated() {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
            context.setFillColor(style.paperColor.cgColor); context.fill(mediaBox)
            context.saveGState()
            let occupiedHeight = min(contentHeight, (page.range.upperBound - page.range.lowerBound) * page.scale)
            context.clip(to: CGRect(x: m.left, y: m.top + headerHeight, width: contentWidth, height: occupiedHeight))
            context.translateBy(x: m.left + contentWidth * (1 - page.scale) / 2, y: m.top + headerHeight)
            context.scaleBy(x: page.scale, y: page.scale)
            context.translateBy(x: 0, y: -page.range.lowerBound)
            DocumentTypesetter.draw(layout, in: context, sourceRange: page.range)
            context.restoreGState()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            func drawTemplate(_ template: String, y: CGFloat) {
                let value = template.replacingOccurrences(of: "{page}", with: String(index + 1)).replacingOccurrences(of: "{pages}", with: String(pages.count)).replacingOccurrences(of: "{file}", with: options.title).replacingOccurrences(of: "{date}", with: formatter.string(from: options.date))
                let attributed = NSAttributedString(string: value, attributes: [.font: PlatformFont.systemFont(ofSize: 10), .foregroundColor: style.secondaryColor])
                let line = CTLineCreateWithAttributedString(attributed)
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                context.saveGState()
                context.translateBy(x: max(m.left, (size.width - width) / 2), y: y)
                context.scaleBy(x: 1, y: -1); context.textPosition = .zero
                CTLineDraw(line, context)
                context.restoreGState()
            }
            if !options.headerTemplate.isEmpty { drawTemplate(options.headerTemplate, y: m.top + 10) }
            if options.pageNumbers && !options.footerTemplate.isEmpty { drawTemplate(options.footerTemplate, y: size.height - max(10, m.bottom)) }
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
