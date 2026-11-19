import KasumiMarkdown
import Observation
import SwiftUI
import UIKit

fileprivate enum ReaderExportFormat: String, CaseIterable, Identifiable, Sendable {
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
}

fileprivate enum PaperPreset: String, CaseIterable, Identifiable, Sendable {
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

fileprivate enum MarginPreset: String, CaseIterable, Identifiable, Sendable {
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

fileprivate struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// One worker per export sheet. Cancellation keeps the job busy until the worker
/// has actually stopped, so a second large bitmap cannot overlap the first.
@MainActor @Observable
fileprivate final class ReaderExportJob {
    var busy = false
    var cancelling = false
    var error: String?
    var sharedFile: ExportedFile?
    var printFile: ExportedFile?
    @ObservationIgnored private var worker: Task<URL, Error>?
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var identity = UUID()

    func start(
        document: MarkdownDocument, title: String, style: RenderStyle, format: ReaderExportFormat,
        width: Double, scale: Double, quality: Double, paper: PaperPreset, margins: MarginPreset,
        fontSize: Double, pageNumbers: Bool, printOutput: Bool
    ) {
        guard !busy, sharedFile == nil, printFile == nil else { return }
        clearFile()
        let id = UUID()
        identity = id
        busy = true
        cancelling = false
        error = nil
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KasumiExport-" + id.uuidString)
        directory = folder
        // URL construction prevents a source title from becoming a path.
        let stem = (title as NSString).deletingPathExtension
        let filename = (stem.isEmpty ? "Untitled" : stem).replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent(filename).appendingPathExtension(format.rawValue)
        var preparedStyle = style
        preparedStyle.fontSize = fontSize
        preparedStyle.codeBlockStyle = ReaderCodeBlockStyle.exporting(fontSize: fontSize)
        let exportStyle = preparedStyle
        let task = Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try Task.checkCancellation()
                _ = await DocumentExport.preloadImages(document)
                try Task.checkCancellation()
                try autoreleasepool {
                    if format == .pdf {
                        var options = PDFExportOptions()
                        options.title = title
                        options.pageNumbers = pageNumbers
                        options.paperSize = paper.size
                        options.margins = .init(
                            top: margins.points, left: margins.points, bottom: margins.points, right: margins.points)
                        options.fontSize = fontSize
                        try DocumentExport.writePDF(
                            document, style: exportStyle, options: options, to: url)
                    } else {
                        var options = ImageExportOptions()
                        options.format = format == .jpg ? .jpeg : .png
                        options.scale = scale
                        options.jpegQuality = quality
                        try DocumentExport.writeImage(
                            document, style: exportStyle, width: width, options: options, to: url)
                    }
                }
                try Task.checkCancellation()
                return url
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
        }
        worker = task
        Task { [weak self] in
            do {
                let url = try await task.value
                guard let self, self.identity == id, !task.isCancelled else {
                    try? FileManager.default.removeItem(at: folder)
                    self?.finish(id: id)
                    return
                }
                self.finish(id: id)
                if printOutput {
                    self.printFile = ExportedFile(url: url)
                } else {
                    self.sharedFile = ExportedFile(url: url)
                }
            } catch {
                guard let self, self.identity == id else { return }
                self.finish(id: id)
                self.clearFile()
                if !task.isCancelled, !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }

    private func finish(id: UUID) {
        guard identity == id else { return }
        busy = false
        cancelling = false
        worker = nil
    }

    func cancel() {
        guard busy else { return }
        cancelling = true
        worker?.cancel()
    }

    func clearFile() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    func close() {
        identity = UUID()
        worker?.cancel()
        worker = nil
        clearFile()
    }
}

struct ReaderExportSheet: View {
    let document: MarkdownDocument
    let title: String
    let style: RenderStyle
    @Environment(\.dismiss) private var dismiss
    @State private var format = ReaderExportFormat.pdf
    @State private var width = 600.0
    @State private var scale = 2.0
    @State private var quality = 0.9
    @State private var paper = PaperPreset.a4
    @State private var margins = MarginPreset.normal
    @State private var pdfFontSize: Double
    @State private var imageFontSize: Double
    @State private var pageNumbers = true
    @State private var job = ReaderExportJob()

    init(document: MarkdownDocument, title: String, style: RenderStyle) {
        self.document = document
        self.title = title
        self.style = style
        _pdfFontSize = State(initialValue: Double(style.preset.printFontSize))
        _imageFontSize = State(initialValue: Double(style.fontSize ?? style.preset.defaultFontSize))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $format.animation()) {
                        ForEach(ReaderExportFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .accessibilityIdentifier("export-format")
                    if format == .pdf {
                        Picker("Paper Size", selection: $paper) {
                            ForEach(PaperPreset.allCases) { preset in
                                Text(verbatim: preset.label).tag(preset)
                            }
                        }
                        Picker("Margins", selection: $margins) {
                            ForEach(MarginPreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        Toggle("Page Numbers", isOn: $pageNumbers)
                    } else {
                        Stepper(value: $width, in: 320...1600, step: 40) {
                            Text("Layout Width: \(Int(width)) pt")
                        }
                        .accessibilityIdentifier("export-width")
                        Picker("Resolution", selection: $scale) {
                            Text("1×").tag(1.0)
                            Text("2×").tag(2.0)
                            Text("3×").tag(3.0)
                        }
                        if format == .jpg {
                            LabeledContent("JPG Quality") {
                                Text(quality, format: .percent.precision(.fractionLength(0)))
                            }
                            Slider(value: $quality, in: 0.6...1, step: 0.05) { Text("JPG Quality") }
                        }
                    }
                    Stepper(value: format == .pdf ? $pdfFontSize : $imageFontSize, in: 6...36, step: 1) {
                        Text("Font Size: \(format == .pdf ? pdfFontSize : imageFontSize, specifier: "%.0f") pt")
                            .contentTransition(.numericText())
                            .animation(.default, value: format == .pdf ? pdfFontSize : imageFontSize)
                    }
                    .accessibilityIdentifier("export-font-size")
                } footer: {
                    // One Text keeps the footer's identity so a format change cross-fades it.
                    Text(format.footer).contentTransition(.opacity)
                }
                .disabled(locked)
                .opacity(locked ? 0.4 : 1)
                Section {
                    Button("Export and Share", systemImage: "square.and.arrow.up") { start(printOutput: false) }
                        .disabled(locked)
                        .opacity(locked ? 0.4 : 1)
                        .accessibilityIdentifier("export-share")
                    if format == .pdf {
                        Button("Print", systemImage: "printer") { start(printOutput: true) }
                            .disabled(locked)
                            .opacity(locked ? 0.4 : 1)
                            .accessibilityIdentifier("export-print")
                    }
                    if let error = job.error {
                        Text(error).foregroundStyle(.red)
                            .accessibilityIdentifier("export-error")
                    }
                }
            }
            .animation(.default, value: locked)
            .animation(.default, value: job.error)
            .softTopScrollEdge()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(job.busy ? "Cancel" : "Close", systemImage: "xmark") {
                        if job.busy { job.cancel() } else { dismiss() }
                    }
                    .disabled(job.cancelling)
                    .accessibilityIdentifier(job.busy ? "export-cancel" : "export-done")
                }
            }
            .sheet(item: $job.sharedFile, onDismiss: { job.clearFile() }) { file in
                ExportShareSheet(url: file.url)
                    .ignoresSafeArea()
            }
            .background {
                ExportPrintPresenter(file: job.printFile) { error in
                    job.printFile = nil
                    job.clearFile()
                    if let error { job.error = error.localizedDescription }
                }
            }
        }
        .onDisappear { job.close() }
    }

    /// Options stay in place and dim while a job or its share/print UI is active.
    private var locked: Bool { job.busy || job.sharedFile != nil || job.printFile != nil }

    private func start(printOutput: Bool) {
        job.start(
            document: document, title: title, style: style, format: format,
            width: width, scale: scale, quality: quality, paper: paper, margins: margins,
            fontSize: format == .pdf ? pdfFontSize : imageFontSize,
            pageNumbers: pageNumbers, printOutput: printOutput)
    }
}

fileprivate struct ExportShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Present from a persistent view in this sheet's own window, including iPad.
fileprivate struct ExportPrintPresenter: UIViewControllerRepresentable {
    let file: ExportedFile?
    let completed: (Error?) -> Void

    final class Controller: UIViewController {
        var presentedID: UUID?
        var printer: UIPrintInteractionController?
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed || navigationController?.isBeingDismissed == true { printer?.dismiss(animated: false) }
        }
    }

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        guard let file, controller.presentedID != file.id else { return }
        controller.presentedID = file.id
        let printer = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = file.url.deletingPathExtension().lastPathComponent
        info.outputType = .general
        printer.printInfo = info
        printer.printingItem = file.url
        controller.printer = printer
        // Updating a representable must not synchronously mutate SwiftUI state.
        Task { @MainActor in
            guard controller.view.window != nil else {
                completed(CocoaError(.featureUnsupported))
                return
            }
            let presented = printer.present(from: controller.view.bounds, in: controller.view, animated: true) {
                _, _, error in
                Task { @MainActor in completed(error) }
            }
            if !presented { completed(CocoaError(.featureUnsupported)) }
        }
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.printer?.dismiss(animated: false)
    }
}
