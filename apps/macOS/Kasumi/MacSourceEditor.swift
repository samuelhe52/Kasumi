import AppKit
import KasumiMarkdown
import SwiftUI

func hasSameSourceBytes(_ lhs: String, _ rhs: String) -> Bool {
    // NSTextView can vend an NSString-backed String, whose UTF-8 count
    // requires transcoding. Its UTF-16 length is already available.
    guard lhs.utf16.count == rhs.utf16.count else { return false }
    if lhs.isEmpty { return true }
    var left = lhs
    var right = rhs
    return left.withUTF8 { leftBytes in
        right.withUTF8 { rightBytes in
            leftBytes.count == rightBytes.count
                && memcmp(leftBytes.baseAddress!, rightBytes.baseAddress!, leftBytes.count) == 0
        }
    }
}

struct MacSourceEditor: NSViewRepresentable {
    let document: ReaderDocument
    let controller: MacSourceEditorController
    let style: RenderStyle
    let undoManager: UndoManager?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = SourceScrollView(controller: controller)
        scrollView.verticalScroller = MacScroller()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        // TextKit 1 gives the editor a direct mapping between laid-out glyphs
        // and UTF-16 offsets, including wrapped lines.
        let textView = SourceTextView(frame: scrollView.bounds)
        textView.sourceController = controller
        textView.setAccessibilityLabel("Markdown Source")
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 24, height: 18)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        scrollView.documentView = textView
        controller.attach(textView, to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        controller.update(document: document, undoManager: undoManager, style: style)
    }
}

private final class SourceTextView: NSTextView {
    weak var sourceController: MacSourceEditorController?

    override func unmarkText() {
        let wasComposing = hasMarkedText()
        super.unmarkText()
        // A candidate can become committed without replacing any characters.
        if wasComposing { sourceController?.checkEditorText() }
    }
}

private final class SourceScrollView: NSScrollView {
    private weak var controller: MacSourceEditorController?

    init(controller: MacSourceEditorController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(controller:) instead") }

    override func layout() {
        super.layout()
        controller?.viewDidLayout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller?.viewDidLayout()
    }
}

@MainActor @Observable
final class MacSourceEditorController: NSObject, NSTextViewDelegate, @MainActor NSTextStorageDelegate {
    private(set) var topLine = 1
    @ObservationIgnored private(set) weak var textView: NSTextView?
    @ObservationIgnored private(set) weak var scrollView: NSScrollView?
    @ObservationIgnored private weak var document: ReaderDocument?
    @ObservationIgnored private weak var documentUndoManager: UndoManager?
    @ObservationIgnored private var loadedText: String?
    @ObservationIgnored private var editorNeedsSync = false
    @ObservationIgnored private var checkingTextStorage = false
    @ObservationIgnored private var reloadingText = false
    @ObservationIgnored private var lineStarts: [Int]?
    @ObservationIgnored private var pendingLocation: (line: Int, focus: Bool)?
    /// The requested line while the viewport stays at `y`. A line too near the
    /// end to reach the top is `clamped`, and then follows its text through edits.
    @ObservationIgnored private var mappedLocation: (y: CGFloat, character: Int, clamped: Bool)?
    @ObservationIgnored private var editCount = 0
    private static let synchronousFormattingLimit = 50_000
    @ObservationIgnored private var scheduled = false
    @ObservationIgnored private var showFindWhenReady = false

    /// Where the editor is, or is about to be.
    var currentLine: Int { pendingLocation?.line ?? topLine }

    var isFindPresented: Bool { scrollView?.isFindBarVisible == true }

    func attach(_ textView: NSTextView, to scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
        textView.delegate = self
        textView.textStorage?.delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)
    }

    func update(document: ReaderDocument, undoManager: UndoManager?, style: RenderStyle) {
        self.document = document
        documentUndoManager = undoManager
        guard let textView, let scrollView else { return }
        if loadedText.map({ hasSameSourceBytes($0, document.text) }) != true {
            reloadText()
        }
        textView.isEditable = document.canEdit
        let readingSize = style.fontSize ?? style.preset.defaultFontSize
        let font = NSFont.monospacedSystemFont(ofSize: max(10, readingSize - 3), weight: .regular)
        let paper = style.theme.document["paper"].map(Self.color) ?? .textBackgroundColor
        let ink = style.theme.document["text"].map(Self.color) ?? .textColor
        if textView.font != font { textView.font = font }
        if textView.textColor != ink {
            textView.textColor = ink
            textView.insertionPointColor = ink
        }
        textView.backgroundColor = paper
        scrollView.backgroundColor = paper
        schedulePositionUpdate()
    }

    /// NSTextView registers its typing operations with the document's undo
    /// manager. NSDocument observes those registrations to schedule autosave.
    func undoManager(for view: NSTextView) -> UndoManager? { documentUndoManager }

    func textDidChange(_ notification: Notification) {
        editorNeedsSync = true
        synchronizeText()
    }

    var pendingText: String? {
        guard editorNeedsSync, let textView, let loadedText else { return nil }
        let text = textView.string
        return hasSameSourceBytes(text, loadedText) ? nil : text
    }

    var isComposing: Bool { textView?.hasMarkedText() == true }

    func prepareAutosave() {
        guard !isComposing else { return }
        synchronizeText(force: true)
        textView?.breakUndoCoalescing()
    }

    func finishEditing() {
        if isComposing { textView?.unmarkText() }
        prepareAutosave()
    }

    func reloadText() {
        guard let document, let textView, let scrollView else { return }
        reloadingText = true
        defer { reloadingText = false }
        loadedText = document.text
        editorNeedsSync = false
        if textView.hasMarkedText() { textView.unmarkText() }
        guard !hasSameSourceBytes(textView.string, document.text) else { return }
        let selection = textView.selectedRange()
        let y = scrollView.contentView.bounds.minY
        textView.undoManager?.removeAllActions(withTarget: textView)
        textView.string = document.text
        textView.setSelectedRange(NSRange(location: min(selection.location, document.text.utf16.count), length: 0))
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: y))
        lineStarts = nil
        mappedLocation = nil
        schedulePositionUpdate()
    }

    private func synchronizeText(force: Bool = false) {
        guard !reloadingText, !isComposing, force || editorNeedsSync,
            let textView, let document, let loadedText
        else { return }
        let value = textView.string
        editorNeedsSync = false
        guard !hasSameSourceBytes(value, loadedText) else { return }
        self.loadedText = value
        lineStarts = nil
        if mappedLocation?.clamped == false { mappedLocation = nil }
        document.setText(value, undoManager: nil)
        schedulePositionUpdate()
    }

    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        editCount += 1
        // Accessibility and text services can write through the text storage.
        checkEditorText()
        guard let mapped = mappedLocation, range.location < mapped.character else { return }
        let replacedEnd = NSMaxRange(range) - delta
        mappedLocation?.character =
            mapped.character >= replacedEnd ? mapped.character + delta : min(mapped.character, NSMaxRange(range))
    }

    func checkEditorText() {
        guard !reloadingText else { return }
        editorNeedsSync = true
        guard !checkingTextStorage else { return }
        checkingTextStorage = true
        DispatchQueue.main.async { [weak self] in
            self?.checkingTextStorage = false
            self?.synchronizeText()
        }
    }

    func scroll(to line: Int, focus: Bool = false) {
        pendingLocation = (line, focus)
        schedulePositionUpdate()
    }

    func resignFocus() {
        pendingLocation = nil
        if let textView, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
    }

    func apply(_ command: @escaping @Sendable (String, NSRange) -> SourceEdit) {
        guard let textView, textView.isEditable, let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        let text = textView.string
        // A command can parse the document. Keep small ones synchronous so that
        // typing straight after the shortcut lands inside the markers.
        guard storage.length > Self.synchronousFormattingLimit else {
            apply(command(text, selection))
            return
        }
        let edits = editCount
        Task { [weak self] in
            let edit = await Task.detached(priority: .userInitiated) { command(text, selection) }.value
            guard let self, editCount == edits, self.textView?.selectedRange() == selection else { return }
            apply(edit)
        }
    }

    private func apply(_ edit: SourceEdit) {
        guard let textView, textView.isEditable else { return }
        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.text) else { return }
        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.text)
        let length = textView.textStorage?.length ?? 0
        let start = min(edit.selection.location, length)
        textView.setSelectedRange(NSRange(location: start, length: min(edit.selection.length, length - start)))
        textView.didChangeText()
        textView.breakUndoCoalescing()
        textView.window?.makeFirstResponder(textView)
    }

    func presentFindWhenReady() {
        showFindWhenReady = true
        schedulePositionUpdate()
    }

    func performFind(_ action: NSTextFinder.Action) {
        if action == .hideFindInterface { showFindWhenReady = false }
        guard let textView else { return }
        if action != .hideFindInterface { textView.window?.makeFirstResponder(textView) }
        let item = NSMenuItem(title: "", action: #selector(NSTextView.performTextFinderAction(_:)), keyEquivalent: "")
        item.tag = action.rawValue
        textView.performTextFinderAction(item)
    }

    func viewDidLayout() {
        if pendingLocation != nil || showFindWhenReady { schedulePositionUpdate() }
    }

    @objc private func boundsChanged() { schedulePositionUpdate() }

    private func schedulePositionUpdate() {
        guard textView != nil, !scheduled else { return }
        scheduled = true
        // A SwiftUI representable can be updated during layout or before it is
        // attached; AppKit must finish sizing the clip view before scrolling.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            scheduled = false
            updatePosition()
        }
    }

    private func updatePosition() {
        guard let textView, let scrollView, let manager = textView.layoutManager,
            let container = textView.textContainer, textView.window != nil, scrollView.contentSize.height > 0
        else { return }
        let starts = sourceLineStarts(in: textView)
        let clip = scrollView.contentView
        let origin = textView.textContainerOrigin

        if let request = pendingLocation {
            pendingLocation = nil
            let line = min(starts.count, max(1, request.line))
            let character = starts[line - 1]
            let selection = NSRange(location: character, length: 0)
            manager.ensureLayout(for: container)
            let fragment: CGRect
            if character == textView.textStorage?.length {
                fragment = manager.extraLineFragmentUsedRect
            } else {
                fragment = manager.lineFragmentRect(
                    forGlyphAt: manager.glyphIndexForCharacter(at: character), effectiveRange: nil)
            }
            if request.focus {
                textView.setSelectedRange(selection)
                textView.window?.makeFirstResponder(textView)
            }
            let y = line == 1 ? 0 : origin.y + fragment.minY
            let target = CGRect(origin: CGPoint(x: 0, y: y), size: clip.bounds.size)
            clip.scroll(to: clip.constrainBoundsRect(target).origin)
            scrollView.reflectScrolledClipView(clip)
            mappedLocation = (clip.bounds.minY, character, clip.bounds.minY < y - 1)
        }

        let y = clip.bounds.minY
        let line: Int
        if let mappedLocation, abs(y - mappedLocation.y) < 0.5 {
            line = Self.line(containing: mappedLocation.character, in: starts)
        } else if y <= origin.y || textView.textStorage?.length == 0 {
            line = 1
            mappedLocation = nil
        } else {
            mappedLocation = nil
            let character = manager.characterIndex(
                for: CGPoint(x: container.lineFragmentPadding, y: y - origin.y + 0.5),
                in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            line = Self.line(containing: character, in: starts)
        }
        if topLine != line { topLine = line }
        if showFindWhenReady {
            showFindWhenReady = false
            performFind(.showFindInterface)
        }
    }

    private static func line(containing character: Int, in starts: [Int]) -> Int {
        var lower = 0
        var upper = starts.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if starts[middle] <= character { lower = middle + 1 } else { upper = middle }
        }
        return max(1, lower)
    }

    private func sourceLineStarts(in textView: NSTextView) -> [Int] {
        if let lineStarts { return lineStarts }
        var starts = [0]
        var wasCarriageReturn = false
        for (offset, unit) in textView.string.utf16.enumerated() {
            if unit == 0x0D {
                starts.append(offset + 1)
            } else if unit == 0x0A {
                if wasCarriageReturn {
                    starts[starts.count - 1] = offset + 1
                } else {
                    starts.append(offset + 1)
                }
            }
            wasCarriageReturn = unit == 0x0D
        }
        lineStarts = starts
        return starts
    }

    private static func color(_ value: DocumentColor) -> NSColor {
        NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
    }
}
