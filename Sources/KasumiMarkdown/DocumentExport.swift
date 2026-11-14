import CoreGraphics
import Foundation

public enum DocumentExport {
    public static func pdf(_ document: MarkdownDocument, style: RenderStyle,
                           pageSize: CGSize = CGSize(width: 595.276, height: 841.89),
                           margins: DocumentInsets = .init(top: 72, left: 72, bottom: 72, right: 72)) throws -> Data {
        var options = PDFExportOptions()
        options.paperSize = pageSize; options.margins = margins
        return try DocumentExporter.pdfData(document.parsed, style: style.typography, options: options)
    }

    public static func png(_ rendered: RenderedDocument, scale: CGFloat = 2, region: CGRect? = nil) throws -> Data {
        try rendered.imageData(scale: scale, region: region)
    }
}
