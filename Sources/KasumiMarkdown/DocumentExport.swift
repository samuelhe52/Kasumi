import CoreGraphics
import Foundation
import UniformTypeIdentifiers

public enum DocumentExport {
    public static func pdf(
        _ document: MarkdownDocument, style: RenderStyle,
        pageSize: CGSize = CGSize(width: 595.276, height: 841.89),
        margins: DocumentInsets = .init(top: 72, left: 72, bottom: 72, right: 72)
    ) throws -> Data {
        var options = PDFExportOptions()
        options.paperSize = pageSize
        options.margins = margins
        return try DocumentExporter.pdfData(document.parsed, style: style.typography, options: options)
    }

    /// Export frozen geometry. Viewport snapshots support measured regions only;
    /// exporting unmeasured content throws `DocumentExportError.incompleteLayout`.
    /// Use the full-session overload or default constructor for a complete image.
    public static func png(_ rendered: RenderedDocument, scale: CGFloat = 2, region: CGRect? = nil) throws -> Data {
        try rendered.imageData(scale: scale, region: region)
    }
}

public enum DocumentImageFormat: Sendable {
    case png, jpeg

    var typeIdentifier: CFString {
        switch self {
        case .png: UTType.png.identifier as CFString
        case .jpeg: UTType.jpeg.identifier as CFString
        }
    }
}

public struct ImageExportOptions: Sendable {
    public var format: DocumentImageFormat = .png
    public var scale: CGFloat = 2
    public var jpegQuality: CGFloat = 0.9
    /// Raw pixel budget, not a cap on total process memory or encoder workspace.
    /// Oversized requests fail before allocating a bitmap. Lower width/scale or use PDF.
    public var maximumBitmapBytes: Int = 128 * 1024 * 1024
    public init() {}
}

public enum DocumentExportProgress: Sendable, Equatable {
    case layingOut
    case rendering(completed: Int, total: Int)
    case encoding
}

/// Called synchronously on the exporting thread. UI clients must hop to their actor.
public typealias DocumentExportProgressHandler = @Sendable (DocumentExportProgress) -> Void

extension DocumentExport {
    /// Optional resource preflight; local images load during layout. Remote
    /// failures use the renderer's placeholder, just as in the reader.
    @discardableResult public static func preloadImages(_ document: MarkdownDocument) async -> Bool {
        await DocumentImageStore.shared.preload(document.parsed)
    }

    /// Synchronous headless export. Call on a worker task; cancellation is checked
    /// around layout and between pages. The completed file replaces `url` atomically.
    public static func writePDF(
        _ document: MarkdownDocument, style: RenderStyle, options: PDFExportOptions = .init(), to url: URL,
        progress: DocumentExportProgressHandler? = nil
    ) throws {
        try DocumentExporter.writePDF(
            document.parsed, style: style.typography, options: options, to: url, progress: progress)
    }

    /// File-backed PNG/JPEG encoding avoids retaining a full encoded Data result.
    /// ImageIO still requires a complete, budgeted source bitmap. Cancellation is
    /// cooperative; layout and encoder finalization cannot be interrupted midway.
    public static func writeImage(
        _ document: MarkdownDocument, style: RenderStyle, width: CGFloat, options: ImageExportOptions = .init(),
        to url: URL, progress: DocumentExportProgressHandler? = nil
    ) throws {
        try DocumentExporter.writeImage(
            document.parsed, style: style.typography, width: width, insets: style.insets,
            options: options, to: url, progress: progress)
    }

    /// Like `png`, this requires an exact layout for the requested image region.
    public static func jpeg(
        _ rendered: RenderedDocument, scale: CGFloat = 2, quality: CGFloat = 0.9, region: CGRect? = nil
    ) throws -> Data {
        try rendered.imageData(scale: scale, region: region, format: .jpeg, quality: quality)
    }
}
