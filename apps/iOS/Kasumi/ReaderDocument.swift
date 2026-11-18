import Foundation
import KasumiMarkdown
import Observation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let kasumiMarkdown =
        UTType("net.daringfireball.markdown")
        ?? UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct ReaderSnapshot: Sendable {
    let revision: UUID
    let source: DocumentSource
    let text: String
    let parsed: MarkdownDocument

    init(
        source: DocumentSource, text: String, fileExtension: String, baseURL: URL?,
        parsePlainTextAsMarkdown: Bool = false, revision: UUID = UUID()
    ) {
        self.revision = revision
        self.source = source
        self.text = text
        let ext = fileExtension.lowercased()
        parsed =
            (ext == "txt" || ext == "text") && !parsePlainTextAsMarkdown
            ? MarkdownDocument(plainText: text, baseURL: baseURL)
            : MarkdownDocument(markdown: text, baseURL: baseURL)
    }
}

@MainActor @Observable
final class ReaderDocument: Document, Identifiable {
    let id = UUID()
    nonisolated static let readableContentTypes: [UTType] = [.kasumiMarkdown, .plainText]
    let configuration: URLDocumentConfiguration
    private(set) var snapshot: ReaderSnapshot?
    private(set) var text = ""
    private(set) var previewIsCurrent = false
    private(set) var parsePlainTextAsMarkdown = false
    @ObservationIgnored private var source = DocumentSource(text: "")
    @ObservationIgnored private var sourceRevision = UUID()
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    /// The revision whose preview publishes with animation, so the reader crossfades it.
    @ObservationIgnored private var animatedRevision: UUID?
    @ObservationIgnored private var lastTyping: ContinuousClock.Instant?

    var fileURL: URL? { configuration.fileURL }
    var title: String { fileURL?.lastPathComponent ?? "Untitled" }
    var canEdit: Bool { snapshot != nil && !source.isLossy }
    var isPlainText: Bool {
        let ext = fileURL?.pathExtension.lowercased()
        return ext == "txt" || ext == "text"
    }

    init(configuration: URLDocumentConfiguration) {
        self.configuration = configuration
    }

    deinit { previewTask?.cancel() }

    struct Reader: DocumentReader {
        @concurrent
        func read(from url: sending URL, progress: consuming Subprogress) async throws -> sending ReaderSnapshot {
            let source = try DocumentSource(data: Data(contentsOf: url))
            return ReaderSnapshot(
                source: source, text: source.text, fileExtension: url.pathExtension,
                baseURL: url.deletingLastPathComponent())
        }
    }

    struct WriteSnapshot: Sendable {
        let source: DocumentSource
        let text: String
    }

    struct Writer: DocumentWriter {
        @concurrent
        func write(
            snapshot: sending WriteSnapshot, to destination: sending URL,
            previous: sending WriteSnapshot?, progress: consuming Subprogress
        ) async throws {
            try snapshot.source.data(replacingText: snapshot.text).write(to: destination, options: .atomic)
        }
    }

    nonisolated func reader(configuration: sending ReadConfiguration) -> sending Reader { Reader() }
    nonisolated func writer(configuration: sending WriteConfiguration) -> sending Writer { Writer() }

    func snapshot(contentType: UTType) async throws -> sending WriteSnapshot {
        // Saving never waits for the preview or uses its potentially older text.
        WriteSnapshot(source: source, text: text)
    }

    func apply(snapshot: sending ReaderSnapshot, previous: sending ReaderSnapshot?) async throws {
        sourceRevision = snapshot.revision
        source = snapshot.source
        text = snapshot.text
        // The reader parses plain text as text; keep the current preview until
        // the Markdown parse replaces it, instead of flashing the text rendering.
        if parsePlainTextAsMarkdown && isPlainText && self.snapshot != nil {
            previewIsCurrent = false
            schedulePreview()
        } else {
            self.snapshot = snapshot
            previewIsCurrent = true
        }
    }

    func setParsePlainTextAsMarkdown(_ value: Bool) {
        guard isPlainText, value != parsePlainTextAsMarkdown else { return }
        parsePlainTextAsMarkdown = value
        previewIsCurrent = false
        sourceRevision = UUID()
        animatedRevision = sourceRevision
        schedulePreview()
    }

    /// Typing coalesces into one undo step until a pause, or until the editor
    /// reports a break (a new line or an edit elsewhere), as UITextView's own
    /// typing undo does. Undo and redo always register and end the burst.
    func setText(_ value: String, undoManager: UndoManager?, breaksTyping: Bool = false) {
        guard canEdit, !value.utf8.elementsEqual(text.utf8) else { return }
        let now = ContinuousClock.now
        let continuesBurst = !breaksTyping && lastTyping.map { now - $0 < .seconds(1) } == true
        if !continuesBurst {
            let old = text
            undoManager?.registerUndo(withTarget: self) { [weak undoManager] target in
                target.setText(old, undoManager: undoManager, breaksTyping: true)
                target.lastTyping = nil
            }
            undoManager?.setActionName("Typing")
        }
        lastTyping = now
        text = value
        previewIsCurrent = false
        sourceRevision = UUID()
        schedulePreview()
    }

    private func schedulePreview() {
        guard previewTask == nil else { return }
        // One parser owns the slot until completion. Edits coalesce during both
        // the delay and synchronous parsing; obsolete results never publish.
        previewTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                guard let self, self.snapshot?.revision != self.sourceRevision else { break }
                let revision = self.sourceRevision
                let source = self.source
                let text = self.text
                let ext = self.fileURL?.pathExtension ?? "md"
                let baseURL = self.fileURL?.deletingLastPathComponent()
                let parsePlainTextAsMarkdown = self.parsePlainTextAsMarkdown
                let worker = Task.detached(priority: .userInitiated) {
                    ReaderSnapshot(
                        source: source, text: text, fileExtension: ext, baseURL: baseURL,
                        parsePlainTextAsMarkdown: parsePlainTextAsMarkdown, revision: revision)
                }
                let next = await worker.value
                guard !Task.isCancelled else { break }
                if self.sourceRevision == revision {
                    withAnimation(self.animatedRevision == revision ? .default : nil) {
                        self.snapshot = next
                        self.previewIsCurrent = true
                    }
                    self.animatedRevision = nil
                }
            }
            self?.previewTask = nil
        }
    }
}
