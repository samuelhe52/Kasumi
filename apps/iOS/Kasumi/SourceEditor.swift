import Observation
import SwiftUI
import UIKit

/// Commands and position for the editor of one document session.
@MainActor @Observable
final class SourceEditorState {
    @ObservationIgnored weak var textView: SourceTextView?
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored var onMove: () -> Void = {}
    @ObservationIgnored private var lineStarts: [Int]?
    @ObservationIgnored private var pendingLine: Int?
    /// The requested line's start while the viewport stays at `top`. A line near
    /// the end may never reach the top, and follows its text through edits.
    @ObservationIgnored private var mapped: (character: Int, top: CGFloat)?
    private(set) var canUndo = false
    private(set) var canRedo = false
    var isFocused = false

    func refreshHistory() {
        canUndo = undoManager?.canUndo == true
        canRedo = undoManager?.canRedo == true
        textView?.showHistory(canUndo: canUndo, canRedo: canRedo)
    }

    func undo() {
        textView?.unmarkText()
        undoManager?.undo()
        refreshHistory()
    }

    func redo() {
        textView?.unmarkText()
        undoManager?.redo()
        refreshHistory()
    }

    func dismissKeyboard() { textView?.resignFirstResponder() }
    func focus() { textView?.becomeFirstResponder() }

    /// Where the editor is, or is about to be, as a one-based source line.
    var currentLine: Int {
        if let pendingLine { return pendingLine }
        guard let textView else { return 1 }
        let character =
            mapped.flatMap { abs($0.top - textView.top) < 1 ? $0.character : nil } ?? textView.topCharacter
        return line(containing: character)
    }

    var hasPendingScroll: Bool { pendingLine != nil }

    /// Moves the viewport and caret to a line once the editor is on screen.
    func scroll(to line: Int) { pendingLine = line }

    func applyPendingScroll() {
        guard let line = pendingLine, let textView, textView.window != nil, textView.bounds.height > 0 else { return }
        pendingLine = nil
        let starts = lineStarts(in: textView)
        let character = starts[min(starts.count, max(1, line)) - 1]
        textView.selectedRange = NSRange(location: character, length: 0)
        textView.scrollToTop(character: character)
        mapped = (character, textView.top)
    }

    private func line(containing character: Int) -> Int {
        guard let textView else { return 1 }
        let starts = lineStarts(in: textView)
        var lower = 0
        var upper = starts.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if starts[middle] <= character { lower = middle + 1 } else { upper = middle }
        }
        return max(1, lower)
    }

    /// UTF-16 offsets of line starts. CR, LF and CRLF each end a line.
    private func lineStarts(in textView: UITextView) -> [Int] {
        if let lineStarts { return lineStarts }
        var starts = [0]
        var wasReturn = false
        for (offset, unit) in textView.text.utf16.enumerated() {
            if unit == 0x0A, wasReturn {
                starts[starts.count - 1] = offset + 1
            } else if unit == 0x0A || unit == 0x0D {
                starts.append(offset + 1)
            }
            wasReturn = unit == 0x0D
        }
        lineStarts = starts
        return starts
    }

    func textDidLoad() {
        lineStarts = nil
        mapped = nil
    }

    func textDidChange(from old: String, to new: String) {
        lineStarts = nil
        guard let mapped else { return }
        let change = SourceEditor.changedRange(from: old, to: new)
        guard change.location <= mapped.character else { return }
        let shifted = mapped.character + new.utf16.count - old.utf16.count
        self.mapped?.character = max(change.location, shifted)
    }
}

struct SourceEditor: UIViewRepresentable {
    let document: ReaderDocument
    let state: SourceEditorState
    let paper: Color
    let undoManager: UndoManager?

    func makeCoordinator() -> Coordinator { Coordinator(document: document, state: state) }

    func makeUIView(context: Context) -> SourceEditorView {
        let container = SourceEditorView()
        container.backgroundColor = UIColor(paper)
        let view = container.textView
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedSystemFont(ofSize: 16, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = UIColor(paper)
        view.textColor = .label
        view.tintColor = .systemBlue
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 32, right: 20)
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.spellCheckingType = .no
        if #available(iOS 26.0, *) { view.topEdgeEffect.style = .soft }
        view.accessibilityLabel = "Markdown source"
        view.accessibilityIdentifier = "source-editor"
        view.text = document.text
        view.editorState = state
        view.installKeyboardBar()
        state.textDidLoad()
        state.textView = view
        view.delegate = context.coordinator
        return container
    }

    func updateUIView(_ container: SourceEditorView, context: Context) {
        container.backgroundColor = UIColor(paper)
        let view = container.textView
        view.backgroundColor = UIColor(paper)
        context.coordinator.undoManager = undoManager
        state.undoManager = undoManager
        state.refreshHistory()
        // Do not replace text storage during typing or marked-text composition.
        // Undo/redo and external file reloads are the only programmatic updates.
        if view.markedTextRange == nil, !view.text.utf8.elementsEqual(document.text.utf8) {
            let changed = Self.changedRange(from: view.text, to: document.text)
            let old = view.text ?? ""
            let offset = view.contentOffset
            view.text = document.text
            state.textDidChange(from: old, to: document.text)
            // Keep the viewport, then reveal and select what undo/redo changed,
            // unless the editor is about to open at the reading place.
            view.setContentOffset(offset, animated: false)
            view.selectedRange = changed
            if !state.hasPendingScroll { view.scrollRangeToVisible(changed) }
        }
    }

    static func dismantleUIView(_ container: SourceEditorView, coordinator: Coordinator) {
        let view = container.textView
        view.resignFirstResponder()
        coordinator.publish(view)
        if coordinator.state.textView === view { coordinator.state.textView = nil }
        view.delegate = nil
    }

    /// The span of `new`, in UTF-16 units, that differs from `old`.
    static func changedRange(from old: String, to new: String) -> NSRange {
        let a = Array(old.utf16)
        let b = Array(new.utf16)
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
            suffix += 1
        }
        return NSRange(location: prefix, length: b.count - prefix - suffix)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let document: ReaderDocument
        let state: SourceEditorState
        weak var undoManager: UndoManager?
        private var typingLocation: Int?
        private var breaksTyping = false
        private var applyingCommand = false

        init(document: ReaderDocument, state: SourceEditorState) {
            self.document = document
            self.state = state
        }

        func publish(_ view: UITextView) {
            // Track visible source, including an IME candidate, so a save never
            // captures older text. updateUIView leaves marked storage untouched.
            state.textDidChange(from: document.text, to: view.text)
            document.setText(view.text, undoManager: undoManager, breaksTyping: breaksTyping)
            breaksTyping = false
            state.refreshHistory()
        }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
        ) -> Bool {
            // Typing continues at the caret and backspace ends there; any other
            // location or a new line starts a new undo step. Marked-text
            // replacements start at the composition, which is contiguous too.
            let contiguous = range.location == typingLocation || NSMaxRange(range) == typingLocation
            breaksTyping = applyingCommand || !contiguous || text.contains("\n")
            typingLocation = range.location + text.utf16.count
            return true
        }

        /// Bar commands are one undo step each, separate from typing.
        func apply(_ edit: SourceEdit, in view: UITextView) {
            view.unmarkText()
            guard let start = view.position(from: view.beginningOfDocument, offset: edit.range.location),
                let end = view.position(from: start, offset: edit.range.length),
                let range = view.textRange(from: start, to: end)
            else { return }
            breaksTyping = true
            applyingCommand = true
            view.replace(range, withText: edit.text)
            applyingCommand = false
            publish(view)  // No-op when the delegate already published.
            typingLocation = nil
            view.selectedRange = edit.selection
            view.scrollRangeToVisible(edit.selection)
        }

        func textViewDidChange(_ textView: UITextView) { publish(textView) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { state.onMove() }
        func textViewDidBeginEditing(_ textView: UITextView) { state.isFocused = true }
        func textViewDidEndEditing(_ textView: UITextView) {
            publish(textView)
            state.isFocused = false
        }
    }
}

/// Paper fills the safe area behind the keyboard; text ends at its top edge.
final class SourceEditorView: UIView {
    let textView = SourceTextView()
    private lazy var keyboardEdge = textView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor)

    override init(frame: CGRect) {
        super.init(frame: frame)
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        // Without a keyboard the text runs under the bottom bar like the reader;
        // the text view's own safe-area insets keep its last line reachable.
        keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            keyboardEdge
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The keyboard guide includes the clear history accessory. Run text under
    /// that accessory, like under the bottom bar, but stop at the keyboard's own
    /// glass, and inset the content so the caret stays above the capsule.
    override func layoutSubviews() {
        let accessory =
            keyboardLayoutGuide.layoutFrame.height > 0
            ? textView.inputAccessoryView?.bounds.height ?? 0 : 0
        if keyboardEdge.constant != accessory { keyboardEdge.constant = accessory }
        super.layoutSubviews()
        if textView.contentInset.bottom != accessory {
            textView.contentInset.bottom = accessory
            textView.verticalScrollIndicatorInsets.bottom = accessory
        }
    }
}

/// The document owns undo, including edits made before the editor is remounted.
/// Suppress UITextView's second, view-owned stack and route keyboard commands to
/// the document manager, whose registrations also drive DocumentGroup autosave.
final class SourceTextView: UITextView {
    weak var editorState: SourceEditorState?
    private var viewportSize = CGSize.zero
    override var undoManager: UndoManager? { nil }
    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "z", modifierFlags: .command, action: #selector(undoSource)),
            UIKeyCommand(input: "z", modifierFlags: [.command, .shift], action: #selector(redoSource)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(hideKeyboard))
        ]
    }

    // SwiftUI's keyboard toolbar placement only serves SwiftUI text fields,
    // and UIToolbar moves the trailing group into an overflow menu at iPhone
    // width. One glass capsule of plain buttons keeps every command visible.
    private lazy var undoButton = barButton("Undo", "arrow.uturn.backward", "source-keyboard-undo") {
        $0.editorState?.undo()
    }
    private lazy var redoButton = barButton("Redo", "arrow.uturn.forward", "source-keyboard-redo") {
        $0.editorState?.redo()
    }

    /// History and Markdown commands for characters that sit on the keyboard's
    /// second symbol page or behind a long press.
    func installKeyboardBar() {
        undoButton.isEnabled = false
        redoButton.isEnabled = false
        let heading = barButton("Heading", "number", "source-keyboard-heading") {
            $0.format { SourceFormatting.heading(in: $0, selection: $1) }
        }
        // A long press picks a level directly.
        heading.menu = UIMenu(
            title: "Heading",
            children: (1...6).map { (level: Int) -> UIMenuElement in
                UIAction(title: "Heading \(level)") { [weak self] _ in
                    self?.format { SourceFormatting.heading(in: $0, selection: $1, level: level) }
                }
            } + [
                UIAction(title: "Body Text") { [weak self] _ in
                    self?.format { SourceFormatting.heading(in: $0, selection: $1, level: 0) }
                }
            ])
        let dismiss = barButton("Hide Keyboard", "keyboard.chevron.compact.down", "source-keyboard-dismiss") {
            $0.resignFirstResponder()
        }
        let code = barButton("Code", "chevron.left.forwardslash.chevron.right", "source-keyboard-code") {
            $0.format { SourceFormatting.code(in: $0, selection: $1) }
        }
        let quote = barButton("Quote", "text.quote", "source-keyboard-quote") {
            $0.format { SourceFormatting.quote(in: $0, selection: $1) }
        }
        let link = barButton("Link", "link", "source-keyboard-link") {
            $0.format { SourceFormatting.link(in: $0, selection: $1) }
        }
        // Three commands on each side with equal gaps center Hide Keyboard.
        let leadingGap = UIView()
        let trailingGap = UIView()
        let row = UIStackView(arrangedSubviews: [
            undoButton, redoButton, heading, leadingGap, dismiss, trailingGap, code, quote, link
        ])
        leadingGap.widthAnchor.constraint(equalTo: trailingGap.widthAnchor).isActive = true
        row.axis = .horizontal
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        let capsuleHeight: CGFloat = 44
        let keyboardGap: CGFloat = 12
        let capsule: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            capsule = UIVisualEffectView(effect: glass)
            capsule.cornerConfiguration = .capsule()
        } else {
            capsule = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            capsule.layer.cornerRadius = capsuleHeight / 2
            capsule.clipsToBounds = true
        }
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.contentView.addSubview(row)

        // The capsule keeps the same breathing room above the keyboard that the
        // bottom bar has above the screen edge.
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: capsuleHeight + keyboardGap))
        host.autoresizingMask = .flexibleWidth
        host.addSubview(capsule)
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            capsule.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),
            capsule.topAnchor.constraint(equalTo: host.topAnchor),
            capsule.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -keyboardGap),
            row.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor)
        ])
        inputAccessoryView = host
    }

    func showHistory(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    private func format(_ command: (String, NSRange) -> SourceEdit) {
        guard let coordinator = delegate as? SourceEditor.Coordinator else { return }
        unmarkText()
        coordinator.apply(command(text, selectedRange), in: self)
    }

    private func barButton(
        _ title: String, _ symbol: String, _ identifier: String, action: @escaping (SourceTextView) -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.baseForegroundColor = .label
        let button = UIButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self] _ in if let self { action(self) } })
        button.accessibilityLabel = title
        button.accessibilityIdentifier = identifier
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let resized = viewportSize != bounds.size
        viewportSize = bounds.size
        if resized && isFirstResponder { scrollRangeToVisible(selectedRange) }
    }

    /// The content position below the top bar.
    var top: CGFloat { contentOffset.y + adjustedContentInset.top }

    var topCharacter: Int {
        let y = top - textContainerInset.top
        guard y > 0, let manager = textLayoutManager,
            let fragment = manager.textLayoutFragment(for: CGPoint(x: 0, y: y + 0.5))
        else { return 0 }
        return manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
    }

    func scrollToTop(character: Int) {
        guard let manager = textLayoutManager,
            let target = manager.location(manager.documentRange.location, offsetBy: character)
        else { return }
        // Estimated heights above the target would put it at the wrong place.
        if let range = NSTextRange(location: manager.documentRange.location, end: target) {
            manager.ensureLayout(for: range)
        }
        manager.ensureLayout(for: NSTextRange(location: target))
        layoutIfNeeded()
        let fragment = manager.textLayoutFragment(for: target)
        let y =
            character == 0
            ? 0 : textContainerInset.top + (fragment?.layoutFragmentFrame.minY ?? manager.usageBoundsForTextContainer.maxY)
        let maximum = max(0, contentSize.height - bounds.height + adjustedContentInset.bottom + adjustedContentInset.top)
        setContentOffset(CGPoint(x: 0, y: min(maximum, y) - adjustedContentInset.top), animated: false)
    }

    @objc private func hideKeyboard() { resignFirstResponder() }
    @objc private func undoSource() { editorState?.undo() }
    @objc private func redoSource() { editorState?.redo() }
}
