import AppKit
import KasumiMarkdown
import Synchronization
import UniformTypeIdentifiers

@objc(KasumiMacDocument)
final class MacDocument: NSDocument {
    private struct Contents {
        var latest = ReaderDocument.WriteSnapshot(source: DocumentSource(text: ""), text: "")
        // A recovered copy doesn't establish what is in the original file.
        var savedText: String? = ""
        var recoverableText = ""
    }

    private struct SaveToken {
        let appKitToken: Any
        let text: String
    }

    private let contents = Mutex(Contents())
    private var watchTask: Task<Void, Never>?
    private(set) var session: MacReaderSession?

    nonisolated override class var autosavesInPlace: Bool { true }

    nonisolated override var fileURL: URL? {
        get { super.fileURL }
        set {
            super.fileURL = newValue
            if Thread.isMainThread {
                MainActor.assumeIsolated { fileLocationChanged() }
            } else {
                DispatchQueue.main.async { [weak self] in self?.fileLocationChanged() }
            }
        }
    }

    override var isDocumentEdited: Bool {
        if isDraft { return true }
        let pending = session?.source.pendingText
        return contents.withLock { contents in
            guard let saved = contents.savedText else { return true }
            return !hasSameSourceBytes(pending ?? contents.latest.text, saved)
        }
    }

    override var hasUnautosavedChanges: Bool {
        let editor = session?.source
        // Marked text remains edited, but autosave can only write committed text.
        let pending = editor?.isComposing == true ? nil : editor?.pendingText
        let hasOriginal = fileURL != nil && !isDraft
        return contents.withLock { contents in
            // Closing a named document removes its recovery copy. Its changes
            // still need to go through the native in-place save first.
            let baseline = hasOriginal ? contents.savedText : contents.recoverableText
            return baseline.map { hasSameSourceBytes(pending ?? contents.latest.text, $0) } != true
        }
    }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        let source = try DocumentSource(data: data)
        contents.withLock {
            $0.latest = .init(source: source, text: source.text)
            $0.savedText = source.text
            $0.recoverableText = source.text
        }
    }

    nonisolated override func data(ofType typeName: String) throws -> Data {
        let snapshot = contents.withLock { $0.latest }
        return try snapshot.data()
    }

    func setInitialText(_ text: String) {
        contents.withLock { $0.latest = .init(source: DocumentSource(text: text), text: text) }
    }

    override func updateChangeCount(_ change: ChangeType) {
        if change == .changeReadOtherContents {
            contents.withLock { $0.savedText = nil }
        }
        super.updateChangeCount(change)
    }

    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        let source = contents.withLock { $0.latest.source }
        session?.document.reload(source: source, fileURL: fileURL)
        session?.source.reloadText()
        refreshEditability()
        updateEditedWindows()
    }

    override func changeCountToken(for saveOperation: SaveOperationType) -> Any {
        switch saveOperation {
        case .saveOperation, .saveAsOperation, .saveToOperation:
            finishPendingEdits()
        default:
            session?.source.prepareAutosave()
        }
        let token = super.changeCountToken(for: saveOperation)
        return SaveToken(appKitToken: token, text: contents.withLock { $0.latest.text })
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: SaveOperationType) {
        guard let token = changeCountToken as? SaveToken else {
            super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
            return
        }
        contents.withLock {
            switch saveOperation {
            case .saveOperation, .saveAsOperation:
                $0.savedText = token.text
                $0.recoverableText = token.text
            case .autosaveInPlaceOperation:
                if !isDraft { $0.savedText = token.text }
                $0.recoverableText = token.text
            case .autosaveElsewhereOperation, .autosaveAsOperation:
                $0.recoverableText = token.text
            case .saveToOperation:
                break
            @unknown default:
                break
            }
        }
        super.updateChangeCount(withToken: token.appKitToken, for: saveOperation)
        updateEditedWindows()
    }

    override func canClose(
        withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
    ) {
        finishPendingEdits()
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }

    func finishPendingEdits() {
        session?.source.finishEditing()
    }

    override func makeWindowControllers() {
        guard session == nil else { return }
        let source = contents.withLock { $0.latest.source }
        let plainText =
            fileType.flatMap(UTType.init)?.conforms(to: .plainText) == true
            && fileType != UTType.kasumiMarkdown.identifier
        let model = ReaderDocument(
            source: source, defaultExtension: plainText ? "txt" : "md", isEditable: !isLocked && !isInViewingMode)
        model.onEdit = { [weak self] snapshot in self?.sourceEdited(snapshot) }
        let session = MacReaderSession(document: model)
        self.session = session
        model.setFileURL(fileURL)
        addWindowController(MacDocumentWindowController(session: session, undoManager: undoManager))
        updateEditedWindows()
        startWatch()
    }

    private func sourceEdited(_ snapshot: ReaderDocument.WriteSnapshot) {
        let firstUnsavedEdit = contents.withLock {
            let wasRecoverable = hasSameSourceBytes($0.latest.text, $0.recoverableText)
            $0.latest = snapshot
            return wasRecoverable && !hasSameSourceBytes(snapshot.text, $0.recoverableText)
        }
        updateEditedWindows()
        if firstUnsavedEdit { scheduleAutosaving() }
    }

    private func updateEditedWindows() {
        let edited = isDocumentEdited
        for controller in windowControllers where controller.window?.isDocumentEdited != edited {
            controller.setDocumentEdited(edited)
        }
    }

    func refreshEditability() {
        session?.document.isEditable = !isLocked && !isInViewingMode
    }

    private func fileLocationChanged() {
        guard let model = session?.document, model.fileURL != fileURL else { return }
        session?.viewport.flush()
        model.setFileURL(fileURL)
        refreshEditability()
        startWatch()
    }

    private func startWatch() {
        watchTask?.cancel()
        watchTask = nil
        guard let fileURL, !isInViewingMode else { return }
        let monitor = MacExternalFileMonitor(url: fileURL, document: self)
        watchTask = Task { await monitor.watch() }
    }

    override func close() {
        watchTask?.cancel()
        watchTask = nil
        session?.viewport.flush()
        super.close()
        session = nil
    }
}
