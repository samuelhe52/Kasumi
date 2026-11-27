import AppKit
import KasumiMarkdown
import KasumiMarkdownUI
import SwiftUI

@MainActor @Observable
final class MacReaderSession {
    // Copy requests from any reader window share the same pasteboard.
    private static var copyRequest = 0

    let document: ReaderDocument
    let viewport = ReaderViewport()
    let source = MacSourceEditorController()
    private(set) var showingSource: Bool
    var readerFindPresented = false
    var outputInProgress = false
    private var requestedReaderHeadingID: String?
    @ObservationIgnored private(set) weak var window: NSWindow?
    @ObservationIgnored private var reader: MarkdownReaderProxy?
    @ObservationIgnored private var pendingReaderLine: Int?
    /// The state at the switch to Source, while the reader still has that place.
    @ObservationIgnored private var sourceEntry: (line: Int, text: String)?
    /// A Source outline jump waiting for the outline of exactly this text.
    @ObservationIgnored private var pendingSourceJump: (id: String, text: String)?
    @ObservationIgnored private var pendingFragment: String?
    @ObservationIgnored private var readerIsReady = false
    @ObservationIgnored var style = RenderStyle()

    init(document: ReaderDocument, showingSource: Bool = false) {
        self.document = document
        self.showingSource = showingSource
        if showingSource { source.scroll(to: 1, focus: true) }
    }

    func attach(_ window: NSWindow) {
        self.window = window
    }

    func connect(to proxy: MarkdownReaderProxy) { reader = proxy }

    var outline: [OutlineItem] { document.snapshot?.parsed.outline ?? [] }

    var currentHeadingID: String? {
        if !showingSource { return requestedReaderHeadingID ?? viewport.headingID }
        return outline.last { item in
            item.sourceLine.map { $0 <= source.topLine } ?? false
        }?.id
    }

    func jump(to item: OutlineItem) {
        if showingSource {
            // Until the preview catches up, the item's line belongs to older text.
            pendingSourceJump = (item.id, document.text)
            applyPendingNavigation()
        } else {
            // The reader reports this heading once its scroll settles.
            pendingReaderLine = nil
            requestedReaderHeadingID = item.id
            reader?.scroll(toAnchorID: item.id, animated: false)
        }
    }

    func readerMoved(to anchor: ReadingAnchor, heading: String?) {
        requestedReaderHeadingID = nil
        viewport.moved(anchor: anchor, heading: heading)
        readerIsReady = true
        applyPendingNavigation()
    }

    /// Goes to a link's fragment once this document and its reader are ready.
    func follow(fragment: String) {
        pendingFragment = fragment
        applyPendingNavigation()
    }

    func previewBecameCurrent() {
        restoreReaderPosition()
        applyPendingNavigation()
    }

    private func applyPendingNavigation() {
        guard document.previewIsCurrent else { return }
        if let jump = pendingSourceJump {
            pendingSourceJump = nil
            if showingSource, jump.text == document.text { scrollSource(toHeading: jump.id) }
        }
        guard let fragment = pendingFragment, showingSource || readerIsReady else { return }
        pendingFragment = nil
        if showingSource {
            if scrollSource(toHeading: fragment) { return }
            // Footnotes and other anchors have a place only in the reader.
            toggleSource()
        }
        pendingReaderLine = nil
        DispatchQueue.main.async { [weak self] in
            self?.reader?.scroll(toAnchorID: fragment, animated: false)
        }
    }

    @discardableResult private func scrollSource(toHeading fragment: String) -> Bool {
        let id = fragment.removingPercentEncoding ?? fragment
        guard let line = outline.first(where: { $0.id == fragment || $0.id == id })?.sourceLine else { return false }
        source.scroll(to: line, focus: true)
        return true
    }

    func moveHeading(by step: Int) {
        let outline = self.outline
        let current = outline.firstIndex { $0.id == currentHeadingID } ?? -1
        let next = current + step
        if outline.indices.contains(next) { jump(to: outline[next]) }
    }

    func toggleSource() {
        guard document.snapshot != nil else { return }
        if showingSource {
            // The reader keeps a finer position than a source line, so move it
            // only if the source moved or changed.
            let line = source.currentLine
            if sourceEntry.map({ $0.line != line || $0.text != document.text }) ?? true { pendingReaderLine = line }
            sourceEntry = nil
            pendingSourceJump = nil
            readerFindPresented = source.isFindPresented
            source.performFind(.hideFindInterface)
            source.resignFocus()
            showingSource = false
            restoreReaderPosition()
        } else {
            let headingLine = requestedReaderHeadingID.flatMap { id in outline.first { $0.id == id }?.sourceLine }
            let line = pendingReaderLine ?? headingLine ?? reader?.topSourceLine ?? 1
            sourceEntry = pendingReaderLine == nil ? (line, document.text) : nil
            let followFind = readerFindPresented
            readerFindPresented = false
            pendingReaderLine = nil
            showingSource = true
            source.scroll(to: line, focus: true)
            if followFind { source.presentFindWhenReady() }
        }
    }

    private func restoreReaderPosition() {
        guard !showingSource, document.previewIsCurrent, pendingReaderLine != nil else { return }
        // Let the replacement document reach the native reader before
        // requesting a position in its new layout.
        DispatchQueue.main.async { [weak self] in
            guard let self, !showingSource, document.previewIsCurrent, let line = pendingReaderLine else { return }
            pendingReaderLine = nil
            reader?.scroll(toSourceLine: line, animated: false)
        }
    }

    func performFind(_ action: NSTextFinder.Action) {
        if showingSource {
            source.performFind(action)
        } else if action != .showReplaceInterface {
            // Keep the request if the reader is still attaching or laying out.
            if action == .showFindInterface { readerFindPresented = true }
            reader?.performTextFinderAction(action)
        }
    }

    func jumpToSelection() {
        if showingSource {
            source.textView?.centerSelectionInVisibleArea(nil)
        } else {
            reader?.jumpToSelection()
        }
    }

    func selectTab(_ index: Int?) {
        // An index past the last tab selects the last tab; `nil` means the last tab.
        guard let group = window?.tabGroup, !group.windows.isEmpty else { return }
        let selected = group.windows[min(index ?? .max, group.windows.count - 1)]
        group.selectedWindow = selected
        selected.makeKeyAndOrderFront(nil)
    }

    func showInFinder() {
        if let url = document.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func copyPath() {
        Self.copyRequest += 1
        guard let url = document.fileURL else { return }
        Self.copyToPasteboard(url.path)
    }

    func copyAsMarkdown() {
        Self.copyRequest += 1
        Self.copyToPasteboard(source.pendingText ?? document.text)
    }

    func copyAsPlainText() {
        Self.copyRequest += 1
        let request = Self.copyRequest
        let changeCount = NSPasteboard.general.changeCount
        let pending = source.pendingText
        let text = pending ?? document.text
        if document.isPlainText && !document.parsePlainTextAsMarkdown {
            Self.copyToPasteboard(text)
        } else if pending == nil, document.previewIsCurrent, let snapshot = document.snapshot {
            Self.copyToPasteboard(DocumentExport.plainText(snapshot.parsed))
        } else {
            let worker = Task.detached(priority: .userInitiated) {
                DocumentExport.plainText(MarkdownDocument(markdown: text))
            }
            Task {
                let plainText = await worker.value
                guard Self.copyRequest == request, NSPasteboard.general.changeCount == changeCount else { return }
                Self.copyToPasteboard(plainText)
            }
        }
    }

    private static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
