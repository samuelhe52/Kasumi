import AppKit
import KasumiMarkdown
import Observation
import SwiftUI

extension MacReaderSession {
    var canExport: Bool {
        document.previewIsCurrent && !outputInProgress && source.pendingText == nil
    }

    /// The parse an export renders, or nil while a reload or edit is still being parsed.
    private var exportableDocument: MarkdownDocument? {
        guard document.previewIsCurrent, source.pendingText == nil else { return nil }
        return document.snapshot?.parsed
    }

    func showExport() {
        guard canExport, exportableDocument != nil, let window, window.attachedSheet == nil else { return }
        outputInProgress = true
        // Resolve the document when rendering starts: an external save can
        // reload the reader while the sheet or its save panel is open.
        let job = MacExportJob(
            currentDocument: { [weak self] in self?.exportableDocument },
            currentTitle: { [weak self] in self?.document.title ?? "" },
            currentStyle: { self.style }
        ) { [weak self] in
            self?.outputInProgress = false
        }
        job.present(for: window)
    }
}

@MainActor @Observable
private final class MacExportJob: NSObject {
    private(set) var choosingDestination = false
    private(set) var rendering = false
    var busy: Bool { choosingDestination || rendering }
    private(set) var cancelling = false
    private(set) var progress: DocumentExportProgress?
    private(set) var error: String?

    private let currentDocument: () -> MarkdownDocument?
    private let currentTitle: () -> String
    private let currentStyle: () -> RenderStyle
    private let releaseOutput: () -> Void
    @ObservationIgnored private weak var sheet: NSWindow?
    @ObservationIgnored private var panel: NSSavePanel?
    @ObservationIgnored private var worker: Task<Void, Error>?
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var dismissAfterDestination = false

    var documentIsCurrent: Bool { currentDocument() != nil }

    init(
        currentDocument: @escaping () -> MarkdownDocument?, currentTitle: @escaping () -> String,
        currentStyle: @escaping () -> RenderStyle, releaseOutput: @escaping () -> Void
    ) {
        self.currentDocument = currentDocument
        self.currentTitle = currentTitle
        self.currentStyle = currentStyle
        self.releaseOutput = releaseOutput
    }

    func present(for window: NSWindow) {
        let view = MacExportSheet(job: self, options: ReaderExportOptions(style: currentStyle()))
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        let sheet = NSWindow(contentViewController: host)
        sheet.styleMask = [.titled]
        sheet.title = "Export"
        self.sheet = sheet
        NotificationCenter.default.addObserver(
            self, selector: #selector(parentWillClose(_:)), name: NSWindow.willCloseNotification, object: window)
        window.beginSheet(sheet) { _ in self.sheetDidEnd() }
    }

    func chooseDestination(options: ReaderExportOptions) {
        guard !busy, !closed, let sheet else { return }
        choosingDestination = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.contentType]
        panel.nameFieldStringValue = options.format.filename(for: currentTitle())
        panel.canCreateDirectories = true
        self.panel = panel
        panel.beginSheetModal(for: sheet) { [weak self] response in
            guard let self, !self.closed else { return }
            let url = self.panel?.url
            self.panel = nil
            self.choosingDestination = false
            if self.dismissAfterDestination {
                self.dismiss()
            } else if response == .OK, let url {
                self.start(options: options, to: url)
            }
        }
    }

    private func start(options: ReaderExportOptions, to url: URL) {
        progress = nil
        guard let document = currentDocument() else {
            error = String(localized: "The document changed before export began. Try again once it has updated.")
            return
        }
        rendering = true
        error = nil
        let title = currentTitle()
        let style = currentStyle()
        let (updates, continuation) = AsyncStream<DocumentExportProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let worker = Task.detached(priority: .userInitiated) { [document, title, style] in
            defer { continuation.finish() }
            try await options.write(document, title: title, style: style, to: url) { progress in
                continuation.yield(progress)
            }
        }
        self.worker = worker
        Task {
            for await update in updates where !closed && !cancelling { progress = update }
            let result = await worker.result
            self.worker = nil
            cancelling = false
            rendering = false
            if closed {
                releaseOutput()
            } else {
                switch result {
                case .success: dismiss()
                case .failure(let failure):
                    if !worker.isCancelled, !(failure is CancellationError) { error = failure.localizedDescription }
                }
            }
        }
    }

    func cancelOrDismiss() {
        if let worker {
            cancelling = true
            worker.cancel()
        } else if !busy {
            dismiss()
        }
    }

    @objc private func parentWillClose(_ notification: Notification) { dismiss() }

    private func dismiss() {
        guard !closed else { return }
        if let panel {
            // End the host sheet only after the attached save panel has ended.
            guard !dismissAfterDestination else { return }
            dismissAfterDestination = true
            panel.cancel(nil)
            return
        }
        let sheet = self.sheet
        sheetDidEnd()
        if let sheet { sheet.sheetParent?.endSheet(sheet) }
    }

    private func sheetDidEnd() {
        guard !closed else { return }
        closed = true
        NotificationCenter.default.removeObserver(self)
        panel?.cancel(nil)
        panel = nil
        // The document stays locked until the detached worker has stopped.
        if let worker { worker.cancel() } else { releaseOutput() }
    }
}

private struct MacExportSheet: View {
    let job: MacExportJob
    @State var options: ReaderExportOptions

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Format", selection: $options.format) {
                        ForEach(ReaderExportFormat.allCases) { Text($0.label).tag($0) }
                    }
                    if options.format == .pdf {
                        Picker("Paper Size", selection: $options.paper) {
                            ForEach(PaperPreset.allCases) { Text(verbatim: $0.label).tag($0) }
                        }
                        Picker("Margins", selection: $options.margins) {
                            ForEach(MarginPreset.allCases) { Text($0.label).tag($0) }
                        }
                        Toggle("Page Numbers", isOn: $options.pageNumbers)
                    } else {
                        MacExportSlider(
                            "Layout Width", value: $options.width, in: ReaderExportOptions.widthRange,
                            step: ReaderExportOptions.widthStep
                        ) { Text("\(Int($0)) pt") }
                        Picker("Resolution", selection: $options.scale) {
                            ForEach(ReaderExportOptions.scales, id: \.self) { scale in Text("\(Int(scale))×").tag(scale) }
                        }
                        .pickerStyle(.segmented)
                        if options.format == .jpg {
                            MacExportSlider(
                                "JPG Quality", value: $options.quality, in: ReaderExportOptions.qualityRange,
                                step: ReaderExportOptions.qualityStep
                            ) { Text($0, format: .percent.precision(.fractionLength(0))) }
                        }
                    }
                    MacExportSlider(
                        "Font Size", value: options.format == .pdf ? $options.pdfFontSize : $options.imageFontSize,
                        in: ReaderExportOptions.fontSizeRange, step: 1
                    ) { Text("\(Int($0)) pt") }
                } footer: {
                    Text(options.format.footer)
                }
                .disabled(job.busy)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            if let error = job.error {
                Text(error)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            HStack {
                if job.rendering { progressView }
                Spacer()
                // While rendering, Cancel stops the export and keeps the sheet open.
                Button("Cancel") { job.cancelOrDismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(job.cancelling || job.choosingDestination)
                Button("Export…") { job.chooseDestination(options: options) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(job.busy || !job.documentIsCurrent)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .frame(width: 460)
    }

    @ViewBuilder private var progressView: some View {
        if job.cancelling {
            ProgressView("Cancelling…")
        } else {
            switch job.progress {
            case nil: ProgressView("Loading Images…")
            case .layingOut: ProgressView("Laying Out…")
            case .rendering(let completed, let total):
                ProgressView(value: Double(completed), total: Double(total)) {
                    Text("Rendering \(completed) of \(total)…")
                }
            case .encoding: ProgressView("Writing File…")
            }
        }
    }
}

/// A slider row whose value snaps to `step` without drawing tick marks.
private struct MacExportSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueLabel: (Double) -> Text

    init(
        _ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
        valueLabel: @escaping (Double) -> Text
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.valueLabel = valueLabel
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(
                    value: Binding(
                        get: { value },
                        set: { value = min(range.upperBound, range.lowerBound + ((($0 - range.lowerBound) / step).rounded() * step)) }),
                    in: range
                )
                .labelsHidden()
                .accessibilityLabel(Text(title))
                .accessibilityValue(valueLabel(value))
                .frame(width: 180)
                valueLabel(value)
                    .monospacedDigit()
                    .frame(minWidth: 48, alignment: .trailing)
            }
        }
    }
}
