import AppKit
import KasumiMarkdown
import PDFKit
import UniformTypeIdentifiers

extension MacReaderSession {
    func outputPDF(printing: Bool) {
        guard !outputInProgress, document.previewIsCurrent, let snapshot = document.snapshot, let window else { return }
        var style = self.style
        style.codeBlockStyle = ReaderCodeBlockStyle.exporting
        let title = document.title
        outputInProgress = true
        Task {
            defer { outputInProgress = false }
            do {
                if printing {
                    try await Self.printPDF(snapshot.parsed, style: style, title: title, window: window)
                } else {
                    try await Self.savePDF(snapshot.parsed, style: style, title: title, window: window)
                }
            } catch {
                window.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
            }
        }
    }

    private static func savePDF(
        _ document: MarkdownDocument, style: RenderStyle, title: String, window: NSWindow
    ) async throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (title as NSString).deletingPathExtension + ".pdf"
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
        try await Task.detached(priority: .userInitiated) {
            var options = PDFExportOptions()
            options.title = title
            _ = await DocumentExport.preloadImages(document)
            try DocumentExport.writePDF(document, style: style, options: options, to: url)
        }.value
    }

    private static func printPDF(
        _ document: MarkdownDocument, style: RenderStyle, title: String, window: NSWindow
    ) async throws {
        let printInfo = (window.windowController?.document as? NSDocument)?.printInfo ?? NSPrintInfo.shared
        let pageSize = printInfo.paperSize
        let data = try await Task.detached(priority: .userInitiated) {
            _ = await DocumentExport.preloadImages(document)
            return try DocumentExport.pdf(document, style: style, pageSize: pageSize)
        }.value
        guard let pdf = PDFDocument(data: data),
            let operation = pdf.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true)
        else { throw DocumentExportError.cannotCreatePDF }
        operation.jobTitle = title
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
