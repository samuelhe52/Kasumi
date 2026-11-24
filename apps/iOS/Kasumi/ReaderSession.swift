import KasumiMarkdown
import KasumiMarkdownUI
import Observation

/// Owns the Reader/Source switch and the reading place the two panes share.
@MainActor @Observable
final class ReaderSession {
    let document: ReaderDocument
    let viewport = ReaderViewport()
    let editor = SourceEditorState()
    private(set) var editing = false
    private(set) var previewing = false
    var showingSource: Bool { editing && !previewing }
    @ObservationIgnored private var reader: MarkdownReaderProxy?
    @ObservationIgnored private var pendingReaderLine: Int?
    /// The place handed over at the last switch. The destination keeps its finer
    /// position on the way back if the pane being left hasn't moved from here.
    @ObservationIgnored private var handoff: (line: Int, text: String)?
    @ObservationIgnored private var resumeFocus = false
    /// A Source outline jump waiting for the outline of exactly this text.
    @ObservationIgnored private var pendingSourceJump: (id: String, text: String)?
    private var sourceHeadingID: String?

    init(document: ReaderDocument) {
        self.document = document
        editor.onMove = { [weak self] in self?.updateSourceHeading() }
    }

    var outline: [OutlineItem] { document.snapshot?.parsed.outline ?? [] }
    var currentHeadingID: String? { showingSource ? sourceHeadingID : viewport.headingID }

    func connect(to proxy: MarkdownReaderProxy) { reader = proxy }

    func edit() {
        enterSource()
        editing = true
        previewing = false
    }

    func togglePreview() {
        if previewing {
            enterSource()
        } else {
            leaveSource(resumingFocus: editor.isFocused)
        }
        previewing.toggle()
    }

    func finishEditing() {
        if showingSource { leaveSource(resumingFocus: false) }
        resumeFocus = false
        editing = false
    }

    func jump(to item: OutlineItem) {
        if showingSource {
            // Until the preview catches up, the item's line belongs to older text.
            pendingSourceJump = (item.id, document.text)
            applySourceJump()
            return
        }
        pendingReaderLine = nil
        handoff = nil
        reader?.scroll(toAnchorID: item.id)
    }

    /// Called with the new pane in the window, so it can scroll and take focus.
    func paneDidAppear() {
        if showingSource {
            editor.applyPendingScroll()
            updateSourceHeading()
            if resumeFocus { editor.focus() }
            resumeFocus = false
        } else {
            restoreReaderPosition()
        }
    }

    func previewBecameCurrent() {
        applySourceJump()
        updateSourceHeading()
        // Let the replacement document reach the native reader first.
        Task { restoreReaderPosition() }
    }

    private func applySourceJump() {
        guard document.previewIsCurrent, let jump = pendingSourceJump else { return }
        pendingSourceJump = nil
        guard showingSource, jump.text.utf8.elementsEqual(document.text.utf8),
            let line = outline.first(where: { $0.id == jump.id })?.sourceLine
        else { return }
        editor.scroll(to: line)
        editor.applyPendingScroll()
        updateSourceHeading()
    }

    private func updateSourceHeading() {
        guard showingSource else { return }
        let line = editor.currentLine
        let heading = outline.last { $0.sourceLine.map { $0 <= line } ?? false }?.id
        if sourceHeadingID != heading { sourceHeadingID = heading }
    }

    private func enterSource() {
        // The reader reports no line while its layout is behind the document.
        let line = pendingReaderLine ?? reader?.topSourceLine ?? handoff?.line ?? 1
        if isMoved(from: line) { editor.scroll(to: line) }
        // A reader that hasn't reached the place yet still has to on the way back.
        handoff = pendingReaderLine == nil ? (line, document.text) : nil
        pendingReaderLine = nil
    }

    private func leaveSource(resumingFocus: Bool) {
        // Dismissing the keyboard resizes the editor, so read its place first.
        let line = editor.currentLine
        pendingSourceJump = nil
        resumeFocus = resumingFocus
        editor.dismissKeyboard()
        if isMoved(from: line) { pendingReaderLine = line }
        handoff = (line, document.text)
    }

    private func isMoved(from line: Int) -> Bool {
        handoff.map { $0.line != line || !$0.text.utf8.elementsEqual(document.text.utf8) } ?? true
    }

    private func restoreReaderPosition() {
        guard !showingSource, document.previewIsCurrent, let line = pendingReaderLine else { return }
        pendingReaderLine = nil
        reader?.scroll(toSourceLine: line, animated: false)
    }
}
