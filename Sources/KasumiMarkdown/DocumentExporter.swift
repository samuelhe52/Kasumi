import CoreText
import ImageIO
import UniformTypeIdentifiers

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

public enum DocumentExportError: LocalizedError {
    case invalidGeometry, cannotCreateImage, cannotWriteImage, cannotCreatePDF, cannotWritePDF
    case imageTooLarge(width: Int, height: Int)
    case incompleteLayout
    public var errorDescription: String? {
        switch self {
        case .invalidGeometry: "The export size or margins are invalid."
        case .cannotCreateImage: "Not enough memory for a picture this size. Lower the scale or width."
        case .cannotWriteImage: "The image could not be written."
        case .cannotCreatePDF: "The PDF could not be created."
        case .cannotWritePDF: "The PDF could not be written."
        case .incompleteLayout: "The requested image includes unmeasured text. Create a full layout before exporting."
        case .imageTooLarge(let width, let height):
            "The picture would be \(width)×\(height) pixels. Lower the scale or width, or export a PDF instead."
        }
    }
}

public struct PDFExportOptions: Sendable {
    public var paperSize = CGSize(width: 595.276, height: 841.89)
    public var margins = DocumentInsets(top: 72, left: 72, bottom: 72, right: 72)
    /// Nil uses the typography preset's print size.
    public var fontSize: CGFloat? = nil
    public var pageNumbers = true
    public var footerTemplate = "{page}"
    public var headerTemplate = ""
    public var title = ""
    public var date = Date()
    public init() {}
}

enum DocumentExporter {
    /// Publish only a finished file; cancellation or encoding failure preserves
    /// any existing destination and removes this job's sibling staging file.
    static func writeAtomically(to url: URL, _ write: (URL) throws -> Void) throws {
        guard url.isFileURL else { throw DocumentExportError.invalidGeometry }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try Task.checkCancellation()
        let staging = url.deletingLastPathComponent().appendingPathComponent(".kasumi-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try write(staging)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: url)
        }
    }

    static func writeImage(
        _ document: ParsedDocument, style: Typography, width: CGFloat, scale: CGFloat = 2, to url: URL
    ) throws {
        var options = ImageExportOptions()
        options.scale = scale
        if ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) { options.format = .jpeg }
        try writeImage(document, style: style, width: width, options: options, to: url)
    }

    static func writeImage(
        _ document: ParsedDocument, style: Typography, width: CGFloat, insets: DocumentInsets = .reader,
        options: ImageExportOptions, to url: URL, progress: DocumentExportProgressHandler? = nil
    ) throws {
        guard width.isFinite, width > 0,
            [insets.top, insets.left, insets.bottom, insets.right].allSatisfy({ $0.isFinite && $0 >= 0 })
        else { throw DocumentExportError.invalidGeometry }
        try validate(options)
        try Task.checkCancellation()
        progress?(.layingOut)
        let layout = DocumentTypesetter.layout(document, width: width, style: style, insets: insets)
        try Task.checkCancellation()
        try writeImage(layout, style: style, options: options, to: url, progress: progress)
    }

    static func writeImage(
        _ layout: DocumentLayout, style: Typography, scale: CGFloat = 2, region: CGRect? = nil, to url: URL
    ) throws {
        var options = ImageExportOptions()
        options.scale = scale
        try writeImage(layout, style: style, options: options, region: region, to: url)
    }

    static func writeImage(
        _ layout: DocumentLayout, style: Typography, options: ImageExportOptions, region: CGRect? = nil,
        to url: URL, progress: DocumentExportProgressHandler? = nil
    ) throws {
        try writeAtomically(to: url) { staging in
            try autoreleasepool {
                let image = try makeImage(layout, style: style, options: options, region: region, progress: progress)
                guard
                    let destination = CGImageDestinationCreateWithURL(
                        staging as CFURL, options.format.typeIdentifier, 1, nil)
                else { throw DocumentExportError.cannotWriteImage }
                try encode(image, to: destination, options: options, progress: progress)
            }
        }
    }

    static func imageData(
        _ layout: DocumentLayout, style: Typography, scale: CGFloat = 2, region: CGRect? = nil,
        format: DocumentImageFormat = .png, quality: CGFloat = 0.9
    ) throws -> Data {
        var options = ImageExportOptions()
        options.scale = scale
        options.format = format
        options.jpegQuality = quality
        let image = try makeImage(layout, style: style, options: options, region: region)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, format.typeIdentifier, 1, nil)
        else { throw DocumentExportError.cannotCreateImage }
        try encode(image, to: destination, options: options)
        return data as Data
    }

    private static func encode(
        _ image: CGImage, to destination: CGImageDestination, options: ImageExportOptions,
        progress: DocumentExportProgressHandler? = nil
    ) throws {
        try Task.checkCancellation()
        progress?(.encoding)
        let properties: CFDictionary? =
            options.format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: options.jpegQuality] as CFDictionary : nil
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw DocumentExportError.cannotWriteImage }
        try Task.checkCancellation()
    }

    private static func validate(_ options: ImageExportOptions) throws {
        guard options.scale.isFinite, options.scale > 0,
            options.jpegQuality.isFinite, (0...1).contains(options.jpegQuality), options.maximumBitmapBytes > 0
        else { throw DocumentExportError.invalidGeometry }
    }

    private static func makeImage(
        _ layout: DocumentLayout, style: Typography, options: ImageExportOptions, region: CGRect?,
        progress: DocumentExportProgressHandler? = nil
    ) throws -> CGImage {
        try Task.checkCancellation()
        try validate(options)
        let region = region ?? CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
        let scale = options.scale
        guard region.width.isFinite, region.height.isFinite, region.width > 0, region.height > 0,
            region.minX.isFinite, region.minY.isFinite,
            (region.width * scale).isFinite, (region.height * scale).isFinite,
            region.width * scale < CGFloat(Int.max), region.height * scale < CGFloat(Int.max)
        else { throw DocumentExportError.invalidGeometry }
        let pixelWidth = Int(ceil(region.width * scale))
        let pixelHeight = Int(ceil(region.height * scale))
        // Explicit row stride makes the budget match the actual pixel allocation.
        guard pixelWidth <= 32768, pixelHeight <= 32768,
            Double(pixelWidth) * Double(pixelHeight) * 4 <= Double(options.maximumBitmapBytes)
        else { throw DocumentExportError.imageTooLarge(width: pixelWidth, height: pixelHeight) }
        guard
            let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: options.format == .jpeg
                    ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw DocumentExportError.cannotCreateImage }
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        let paperRect = CGRect(
            x: 0, y: 0, width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
        // Fill rounded-up edge pixels too; JPEG has no alpha channel. PNG
        // retains translucent theme paper without partially covered edge rows.
        if options.format == .jpeg {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(paperRect)
        }
        context.setFillColor(style.paperColor.cgColor)
        context.fill(paperRect)
        context.translateBy(x: -region.minX, y: -region.minY)
        let count = layout.paragraphs.count
        // Paint decorations once, then text in batches without building the
        // reader's semantic selection/search indexes or holding its layout lock.
        var batch = layout
        batch.paragraphs = []
        DocumentTypesetter.draw(batch, in: context)
        batch.backgrounds = []
        batch.rules = []
        for start in stride(from: 0, to: count, by: 32) {
            try Task.checkCancellation()
            let end = min(count, start + 32)
            batch.paragraphs = Array(layout.paragraphs[start..<end])
            try autoreleasepool {
                try Task.checkCancellation()
                DocumentTypesetter.draw(batch, in: context)
            }
            progress?(.rendering(completed: end, total: count))
        }
        try Task.checkCancellation()
        guard let image = context.makeImage() else { throw DocumentExportError.cannotCreateImage }
        return image
    }

    static func writePDF(
        _ document: ParsedDocument, style: Typography, options: PDFExportOptions = PDFExportOptions(), to url: URL
    ) throws {
        try writePDF(document, style: style, options: options, to: url, progress: nil)
    }

    static func writePDF(
        _ document: ParsedDocument, style: Typography, options: PDFExportOptions, to url: URL,
        progress: DocumentExportProgressHandler?
    ) throws {
        try writeAtomically(to: url) { staging in
            // A URL-only CGDataConsumer does not expose write failures. Use a
            // file stream so a full disk cannot publish a silently truncated PDF.
            guard let stream = CFWriteStreamCreateWithFile(nil, staging as CFURL), CFWriteStreamOpen(stream) else {
                throw DocumentExportError.cannotWritePDF
            }
            defer { CFWriteStreamClose(stream) }
            var callbacks = CGDataConsumerCallbacks(
                putBytes: { info, bytes, count in
                    guard let info else { return 0 }
                    let stream = Unmanaged<CFWriteStream>.fromOpaque(info).takeUnretainedValue()
                    var written = 0
                    while written < count {
                        let amount = CFWriteStreamWrite(
                            stream, bytes.assumingMemoryBound(to: UInt8.self).advanced(by: written), count - written)
                        guard amount > 0 else { return written }
                        written += amount
                    }
                    return written
                }, releaseConsumer: nil)
            guard
                let consumer = CGDataConsumer(info: Unmanaged.passUnretained(stream).toOpaque(), cbks: &callbacks)
            else {
                throw DocumentExportError.cannotCreatePDF
            }
            try withExtendedLifetime(stream) {
                try renderPDF(document, style: style, options: options, consumer: consumer, progress: progress)
                if CFWriteStreamCopyError(stream) != nil { throw DocumentExportError.cannotWritePDF }
            }
        }
    }

    static func pdfData(_ document: ParsedDocument, style: Typography, options: PDFExportOptions = PDFExportOptions())
        throws -> Data
    {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw DocumentExportError.cannotCreatePDF
        }
        try renderPDF(document, style: style, options: options, consumer: consumer)
        return data as Data
    }

    private static func renderPDF(
        _ document: ParsedDocument, style: Typography, options: PDFExportOptions, consumer: CGDataConsumer,
        progress: DocumentExportProgressHandler? = nil
    ) throws {
        try Task.checkCancellation()
        let size = options.paperSize
        let m = options.margins
        let values = [size.width, size.height, m.top, m.left, m.bottom, m.right]
        let footerHeight: CGFloat = options.pageNumbers && !options.footerTemplate.isEmpty ? 24 : 0
        let headerHeight: CGFloat = options.headerTemplate.isEmpty ? 0 : 24
        let contentWidth = size.width - m.left - m.right
        let contentHeight = size.height - m.top - m.bottom - footerHeight - headerHeight
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }),
            options.fontSize.map({ $0.isFinite && $0 > 0 }) ?? true,
            contentWidth >= 20, contentHeight >= 20 else {
            throw DocumentExportError.invalidGeometry
        }
        var pageStyle = style
        pageStyle.limitWidth = false
        // Native active-style PDF uses the profile's printed body size rather
        // than the reading size/zoom, retaining families and relative scales.
        pageStyle.size = options.fontSize ?? style.printBodySize
        progress?(.layingOut)
        let layout = DocumentTypesetter.layout(document, width: contentWidth, style: pageStyle, insets: .zero)
        try Task.checkCancellation()
        let slices = try DocumentPaginator.pages(for: layout, contentHeight: contentHeight)
        let pages = slices.isEmpty ? [DocumentPageSlice(range: 0..<0, scale: 1)] : slices
        var mediaBox = CGRect(origin: .zero, size: size)
        let metadata: [CFString: Any] = [kCGPDFContextTitle: options.title, kCGPDFContextCreator: "KasumiMarkdown"]
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata as CFDictionary) else {
            throw DocumentExportError.cannotCreatePDF
        }
        defer { context.closePDF() }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: options.date)
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            autoreleasepool {
                context.beginPDFPage(nil)
                context.saveGState()
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                context.setFillColor(style.paperColor.cgColor)
                context.fill(mediaBox)
                context.saveGState()
                let continuationHeight = page.continuationHeader.map { $0.upperBound - $0.lowerBound } ?? 0
                let occupiedHeight = min(contentHeight, (continuationHeight + page.range.upperBound - page.range.lowerBound) * page.scale)
                context.clip(
                    to: CGRect(x: m.left, y: m.top + headerHeight, width: contentWidth, height: occupiedHeight))
                context.translateBy(x: m.left + contentWidth * (1 - page.scale) / 2, y: m.top + headerHeight)
                context.scaleBy(x: page.scale, y: page.scale)
                if let header = page.continuationHeader {
                    context.saveGState()
                    context.clip(to: CGRect(x: 0, y: 0, width: contentWidth, height: continuationHeight))
                    context.translateBy(x: 0, y: -header.lowerBound)
                    DocumentTypesetter.draw(layout, in: context, sourceRange: header)
                    context.restoreGState()
                }
                context.clip(to: CGRect(
                    x: 0, y: continuationHeight, width: contentWidth,
                    height: page.range.upperBound - page.range.lowerBound))
                context.translateBy(x: 0, y: continuationHeight)
                context.translateBy(x: 0, y: -page.range.lowerBound)
                DocumentTypesetter.draw(layout, in: context, sourceRange: page.range)
                context.restoreGState()
                func drawTemplate(_ template: String, y: CGFloat) {
                    let value = template.replacingOccurrences(of: "{page}", with: String(index + 1))
                        .replacingOccurrences(
                            of: "{pages}", with: String(pages.count)
                        ).replacingOccurrences(of: "{file}", with: options.title).replacingOccurrences(
                            of: "{date}", with: date)
                    let attributed = NSAttributedString(
                        string: value,
                        attributes: [.font: PlatformFont.systemFont(ofSize: 10), .foregroundColor: style.secondaryColor]
                    )
                    let line = CTLineCreateWithAttributedString(attributed)
                    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                    context.saveGState()
                    context.translateBy(x: max(m.left, (size.width - width) / 2), y: y)
                    context.scaleBy(x: 1, y: -1)
                    context.textPosition = .zero
                    CTLineDraw(line, context)
                    context.restoreGState()
                }
                if !options.headerTemplate.isEmpty { drawTemplate(options.headerTemplate, y: m.top + 10) }
                if options.pageNumbers && !options.footerTemplate.isEmpty {
                    drawTemplate(options.footerTemplate, y: size.height - max(10, m.bottom))
                }
                context.restoreGState()
                context.endPDFPage()
            }
            progress?(.rendering(completed: index + 1, total: pages.count))
        }
        try Task.checkCancellation()
    }
}
