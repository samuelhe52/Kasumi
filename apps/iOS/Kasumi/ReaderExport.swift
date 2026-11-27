import KasumiMarkdown
import Observation
import SwiftUI
import UIKit

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
        document: MarkdownDocument, title: String, style: RenderStyle, options: ReaderExportOptions,
        printOutput: Bool
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
        let url = folder.appendingPathComponent(options.format.filename(for: title))
        let task = Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try await options.write(document, title: title, style: style, to: url)
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
    @State private var options: ReaderExportOptions
    @State private var job = ReaderExportJob()

    init(document: MarkdownDocument, title: String, style: RenderStyle) {
        self.document = document
        self.title = title
        self.style = style
        _options = State(initialValue: ReaderExportOptions(style: style))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $options.format.animation()) {
                        ForEach(ReaderExportFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .accessibilityIdentifier("export-format")
                    if options.format == .pdf {
                        Picker("Paper Size", selection: $options.paper) {
                            ForEach(PaperPreset.allCases) { preset in
                                Text(verbatim: preset.label).tag(preset)
                            }
                        }
                        Picker("Margins", selection: $options.margins) {
                            ForEach(MarginPreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        Toggle("Page Numbers", isOn: $options.pageNumbers)
                    } else {
                        Stepper(value: $options.width, in: ReaderExportOptions.widthRange, step: ReaderExportOptions.widthStep) {
                            Text("Layout Width: \(Int(options.width)) pt")
                        }
                        .accessibilityIdentifier("export-width")
                        Picker("Resolution", selection: $options.scale) {
                            ForEach(ReaderExportOptions.scales, id: \.self) { scale in
                                Text("\(Int(scale))×").tag(scale)
                            }
                        }
                        if options.format == .jpg {
                            LabeledContent("JPG Quality") {
                                Text(options.quality, format: .percent.precision(.fractionLength(0)))
                            }
                            Slider(value: $options.quality, in: ReaderExportOptions.qualityRange, step: ReaderExportOptions.qualityStep) {
                                Text("JPG Quality")
                            }
                        }
                    }
                    Stepper(
                        value: options.format == .pdf ? $options.pdfFontSize : $options.imageFontSize,
                        in: ReaderExportOptions.fontSizeRange, step: 1
                    ) {
                        Text("Font Size: \(options.fontSize, specifier: "%.0f") pt")
                            .contentTransition(.numericText())
                            .animation(.default, value: options.fontSize)
                    }
                    .accessibilityIdentifier("export-font-size")
                } footer: {
                    // One Text keeps the footer's identity so a format change cross-fades it.
                    Text(options.format.footer).contentTransition(.opacity)
                }
                .disabled(locked)
                .opacity(locked ? 0.4 : 1)
                Section {
                    Button("Export and Share", systemImage: "square.and.arrow.up") { start(printOutput: false) }
                        .disabled(locked)
                        .opacity(locked ? 0.4 : 1)
                        .accessibilityIdentifier("export-share")
                    if options.format == .pdf {
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
            document: document, title: title, style: style, options: options, printOutput: printOutput)
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
