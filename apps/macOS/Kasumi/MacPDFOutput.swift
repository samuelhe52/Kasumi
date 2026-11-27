import AppKit
import KasumiMarkdown
import PDFKit

extension MacReaderSession {
    func printDocument() {
        guard canExport, let snapshot = document.snapshot, let window else { return }
        var style = self.style
        style.codeBlockStyle = ReaderCodeBlockStyle.exporting(fontSize: style.preset.printFontSize)
        let title = document.title
        outputInProgress = true
        Task {
            defer { outputInProgress = false }
            do {
                try await Self.printPDF(snapshot.parsed, style: style, title: title, window: window)
            } catch {
                window.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
            }
        }
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
