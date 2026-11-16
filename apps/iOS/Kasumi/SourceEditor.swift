import Observation
import SwiftUI
import UIKit

/// View-local state survives compact Source/Preview switches and size changes.
@MainActor @Observable
final class SourceEditorState {
    @ObservationIgnored var selection = NSRange(location: 0, length: 0)
    @ObservationIgnored var offset = CGPoint.zero
    @ObservationIgnored weak var textView: SourceTextView?
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var resumeFocus = false
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

    func previewDidChange(isVisible: Bool) {
        if isVisible {
            resumeFocus = isFocused
            dismissKeyboard()
        } else if resumeFocus {
            resumeFocus = false
            textView?.becomeFirstResponder()
        }
    }

    func finishEditing() {
        resumeFocus = false
        dismissKeyboard()
    }
}

struct SourceEditor: UIViewRepresentable {
    let document: ReaderDocument
    let state: SourceEditorState
    let paper: Color
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager

    func makeCoordinator() -> Coordinator { Coordinator(document: document, state: state) }

    func makeUIView(context: Context) -> SourceEditorView {
        let container = SourceEditorView()
        container.backgroundColor = UIColor(paper)
        container.alpha = isVisible ? 1 : 0
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
        view.topEdgeEffect.style = .soft
        view.accessibilityLabel = "Markdown source"
        view.accessibilityIdentifier = "source-editor"
        view.text = document.text
        view.selectedRange = clamped(state.selection, length: (view.text as NSString).length)
        view.pendingOffset = state.offset
        view.editorState = state
        view.installKeyboardBar()
        state.textView = view
        view.delegate = context.coordinator
        return container
    }

    func updateUIView(_ container: SourceEditorView, context: Context) {
        ReaderPaneTransition.update(container, visible: isVisible, reduceMotion: reduceMotion)
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
            let offset = view.contentOffset
            view.text = document.text
            // Keep the viewport, then reveal and select what undo/redo changed.
            view.setContentOffset(offset, animated: false)
            view.selectedRange = changed
            view.scrollRangeToVisible(changed)
        }
    }

    static func dismantleUIView(_ container: SourceEditorView, coordinator: Coordinator) {
        let view = container.textView
        view.resignFirstResponder()
        coordinator.publish(view)
        coordinator.remember(view)
        if coordinator.state.textView === view { coordinator.state.textView = nil }
        view.delegate = nil
    }

    /// The span of `new`, in UTF-16 units, that differs from `old`.
    static func changedRange(from old: String, to new: String) -> NSRange {
        let a = Array(old.utf16), b = Array(new.utf16)
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
            suffix += 1
        }
        return NSRange(location: prefix, length: b.count - prefix - suffix)
    }

    private func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(range.location, length)
        return NSRange(location: location, length: min(range.length, length - location))
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
            document.setText(view.text, undoManager: undoManager, breaksTyping: breaksTyping)
            breaksTyping = false
            state.refreshHistory()
        }

        func remember(_ view: UITextView) {
            state.selection = view.selectedRange
            state.offset = view.contentOffset
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
        func textViewDidBeginEditing(_ textView: UITextView) { state.isFocused = true }
        func textViewDidEndEditing(_ textView: UITextView) {
            publish(textView)
            state.isFocused = false
        }
        func textViewDidChangeSelection(_ textView: UITextView) { remember(textView) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { state.offset = scrollView.contentOffset }
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
        let accessory = keyboardLayoutGuide.layoutFrame.height > 0
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
    var pendingOffset: CGPoint?
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
        let leadingGap = UIView(), trailingGap = UIView()
        let row = UIStackView(arrangedSubviews: [
            undoButton, redoButton, heading, leadingGap, dismiss, trailingGap, code, quote, link
        ])
        leadingGap.widthAnchor.constraint(equalTo: trailingGap.widthAnchor).isActive = true
        row.axis = .horizontal
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        let glass = UIGlassEffect()
        glass.isInteractive = true
        let capsule = UIVisualEffectView(effect: glass)
        capsule.cornerConfiguration = .capsule()
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.contentView.addSubview(row)

        // The capsule keeps the same breathing room above the keyboard that the
        // bottom bar has above the screen edge.
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 56))
        host.autoresizingMask = .flexibleWidth
        host.addSubview(capsule)
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            capsule.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),
            capsule.topAnchor.constraint(equalTo: host.topAnchor),
            capsule.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -12),
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
        if let offset = pendingOffset, bounds.width > 0, bounds.height > 0 {
            pendingOffset = nil
            let maximum = max(-adjustedContentInset.top, contentSize.height - bounds.height + adjustedContentInset.bottom)
            setContentOffset(
                CGPoint(x: 0, y: min(maximum, max(-adjustedContentInset.top, offset.y))), animated: false)
        } else if resized && isFirstResponder {
            scrollRangeToVisible(selectedRange)
        }
    }
    @objc private func hideKeyboard() { resignFirstResponder() }
    @objc private func undoSource() { editorState?.undo() }
    @objc private func redoSource() { editorState?.redo() }
}
