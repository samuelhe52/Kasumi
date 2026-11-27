import CoreGraphics
import Foundation
import KasumiMarkdown
import UniformTypeIdentifiers

enum ReaderExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf, png, jpg
    var id: Self { self }
    var label: LocalizedStringResource {
        switch self {
        case .pdf: "PDF"
        case .png: "Long PNG"
        case .jpg: "Long JPG"
        }
    }
    var footer: LocalizedStringResource {
        switch self {
        case .pdf: "Uses the current theme and fonts."
        case .png, .jpg:
            "Exports the full document in the current reading style. For very long documents, lower the width or resolution, or choose PDF."
        }
    }
    var contentType: UTType {
        switch self {
        case .pdf: .pdf
        case .png: .png
        case .jpg: .jpeg
        }
    }

    func filename(for title: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        let name = title.components(separatedBy: unsafe).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = (name as NSString).deletingPathExtension.trimmingCharacters(in: trim)
        return "\(stem.isEmpty ? "Untitled" : stem).\(rawValue)"
    }
}

enum PaperPreset: String, CaseIterable, Identifiable, Sendable {
    case a3, a4, a5, letter, legal, tabloid
    var id: Self { self }
    var label: String {
        switch self {
        case .a3: "A3"
        case .a4: "A4"
        case .a5: "A5"
        case .letter: "US Letter"
        case .legal: "US Legal"
        case .tabloid: "US Tabloid"
        }
    }
    var size: CGSize {
        switch self {
        case .a3: CGSize(width: 841.89, height: 1190.551)
        case .a4: CGSize(width: 595.276, height: 841.89)
        case .a5: CGSize(width: 419.528, height: 595.276)
        case .letter: CGSize(width: 612, height: 792)
        case .legal: CGSize(width: 612, height: 1008)
        case .tabloid: CGSize(width: 792, height: 1224)
        }
    }
}

enum MarginPreset: String, CaseIterable, Identifiable, Sendable {
    case narrow, moderate, normal, wide
    var id: Self { self }
    var label: LocalizedStringResource {
        switch self {
        case .narrow: "Narrow (0.25 in)"
        case .moderate: "Moderate (0.5 in)"
        case .normal: "Normal (1 in)"
        case .wide: "Wide (1.5 in)"
        }
    }
    var points: CGFloat {
        switch self {
        case .narrow: 18
        case .moderate: 36
        case .normal: 72
        case .wide: 108
        }
    }
}

struct ReaderExportOptions: Sendable {
    static let widthRange: ClosedRange<Double> = 320...1600
    static let widthStep = 40.0
    static let scales: [Double] = [1, 2, 3]
    static let qualityRange: ClosedRange<Double> = 0.6...1
    static let qualityStep = 0.05
    static let fontSizeRange: ClosedRange<Double> = 6...36

    var format = ReaderExportFormat.pdf
    var width = 600.0
    var scale = 2.0
    var quality = 0.9
    var paper = PaperPreset.a4
    var margins = MarginPreset.normal
    var pdfFontSize: Double
    var imageFontSize: Double
    var pageNumbers = true

    var fontSize: Double { format == .pdf ? pdfFontSize : imageFontSize }

    init(style: RenderStyle) {
        pdfFontSize = Double(style.preset.printFontSize)
        imageFontSize = Double(style.fontSize ?? style.preset.defaultFontSize)
    }

    /// Render on a worker task; the caller owns the task and destination lifecycle.
    func write(
        _ document: MarkdownDocument, title: String, style: RenderStyle, to url: URL,
        progress: DocumentExportProgressHandler? = nil
    ) async throws {
        try Task.checkCancellation()
        await DocumentExport.preloadImages(document)
        try Task.checkCancellation()

        let fontSize = self.fontSize
        var exportStyle = style
        exportStyle.fontSize = fontSize
        exportStyle.codeBlockStyle = ReaderCodeBlockStyle.exporting(fontSize: fontSize)
        try autoreleasepool {
            switch format {
            case .pdf:
                var options = PDFExportOptions()
                options.title = title
                options.pageNumbers = pageNumbers
                options.paperSize = paper.size
                let margin = margins.points
                options.margins = .init(top: margin, left: margin, bottom: margin, right: margin)
                options.fontSize = fontSize
                try DocumentExport.writePDF(document, style: exportStyle, options: options, to: url, progress: progress)
            case .png, .jpg:
                var options = ImageExportOptions()
                options.format = format == .jpg ? .jpeg : .png
                options.scale = scale
                options.jpegQuality = quality
                try DocumentExport.writeImage(
                    document, style: exportStyle, width: width, options: options, to: url, progress: progress)
            }
        }
    }
}
