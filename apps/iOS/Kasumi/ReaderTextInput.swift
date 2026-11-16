import KasumiMarkdown
import UIKit

private final class ReaderTextPosition: UITextPosition {
    let value: TextPosition
    init(_ value: TextPosition) { self.value = value }
}

private final class ReaderTextRange: UITextRange {
    let value: TextRange
    init(_ value: TextRange) { self.value = value }
    override var start: UITextPosition { ReaderTextPosition(value.lowerBound) }
    override var end: UITextPosition { ReaderTextPosition(value.upperBound) }
    override var isEmpty: Bool { value.isEmpty }
}

private final class ReaderSelectionRect: UITextSelectionRect {
    private let geometry: CGRect
    private let first: Bool
    private let last: Bool
    init(_ rect: CGRect, first: Bool, last: Bool) {
        geometry = rect
        self.first = first
        self.last = last
    }
    override var rect: CGRect { geometry }
    override var writingDirection: NSWritingDirection { .natural }
    override var containsStart: Bool { first }
    override var containsEnd: Bool { last }
    override var isVertical: Bool { false }
}

/// UIKit owns selection gestures, handles, magnification, and the edit menu;
/// Kasumi supplies semantic text and geometry from the same snapshot it paints.
class ReaderTextInputView: UIView, UITextInput, UITextInteractionDelegate, UIGestureRecognizerDelegate {
    let rendered: RenderedDocument
    var onLink: ((URL) -> Void)?
    private var selection: ReaderTextRange?
    private var dismissingSelection = false
    private let textInteraction = UITextInteraction(for: .nonEditable)
    private lazy var stringTokenizer = UITextInputStringTokenizer(textInput: self)

    init(rendered: RenderedDocument) {
        self.rendered = rendered
        super.init(frame: CGRect(origin: .zero, size: rendered.size))
        textInteraction.textInput = self
        textInteraction.delegate = self
        addInteraction(textInteraction)
        let tap = UITapGestureRecognizer(target: self, action: #selector(openTappedLink(_:)))
        tap.delegate = self
        for gesture in textInteraction.gesturesForFailureRequirements {
            tap.require(toFail: gesture)
        }
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // ReaderPageView maps native text interaction through table scroll offsets.
    func documentPoint(_ point: CGPoint) -> CGPoint { point }
    func viewRect(_ rect: CGRect, clipped: Bool = false) -> CGRect { rect }
    func selectionGeometry(for range: TextRange) -> [CGRect] {
        rendered.selectionRects(for: range).map { viewRect($0, clipped: true) }.filter { !$0.isNull && !$0.isEmpty }
    }

    override var canBecomeFirstResponder: Bool { true }
    var isEditable: Bool { false }
    var hasText: Bool { !rendered.documentRange.isEmpty }
    weak var inputDelegate: (any UITextInputDelegate)?
    var tokenizer: any UITextInputTokenizer { stringTokenizer }
    var markedTextStyle: [NSAttributedString.Key: Any]?
    var markedTextRange: UITextRange? { nil }
    var beginningOfDocument: UITextPosition { ReaderTextPosition(rendered.documentRange.lowerBound) }
    var endOfDocument: UITextPosition { ReaderTextPosition(rendered.documentRange.upperBound) }
    var textInputView: UIView { self }
    var unobscuredContentRect: CGRect {
        guard let scroll = superview?.superview as? UIScrollView else { return bounds }
        return convert(scroll.bounds.inset(by: scroll.adjustedContentInset), from: scroll)
    }
    var selectedTextRange: UITextRange? {
        get { selection }
        set {
            // Do not accept positions retained from an obsolete page/layout.
            guard newValue == nil || checkedRange(newValue!) != nil else { return }
            selection = newValue as? ReaderTextRange
        }
    }

    // UIKit changes the selection through the property itself. Notify its input
    // delegate only for app-initiated changes, such as Select All and dismissal.
    func clearSelection() {
        inputDelegate?.selectionWillChange(self)
        selection = nil
        inputDelegate?.selectionDidChange(self)
        resignFirstResponder()
    }
    override func copy(_ sender: Any?) {
        guard let selection, !selection.isEmpty else { return }
        UIPasteboard.general.string = rendered.text(in: selection.value)
    }
    override func selectAll(_ sender: Any?) {
        inputDelegate?.selectionWillChange(self)
        selection = ReaderTextRange(rendered.documentRange)
        inputDelegate?.selectionDidChange(self)
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)): return selection.map { !$0.isEmpty } ?? false
        case #selector(selectAll(_:)): return hasText && selection?.value != rendered.documentRange
        default: return false
        }
    }
    func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        // Limit the read-only menu to supported operations (including hardware
        // Command-C/Command-A through the standard responder actions).
        UIMenu(children: [
            UIAction(title: String(localized: "Copy")) { [weak self] _ in self?.copy(nil) },
            UIAction(title: String(localized: "Select All")) { [weak self] _ in self?.selectAll(nil) }
        ])
    }

    func text(in range: UITextRange) -> String? {
        checkedRange(range).map { rendered.text(in: $0) }
    }
    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let start = checkedPosition(fromPosition), let end = checkedPosition(toPosition) else { return nil }
        return ReaderTextRange(TextRange(start, end))
    }
    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let start = checkedPosition(position), let result = rendered.position(from: start, offset: offset) else {
            return nil
        }
        return ReaderTextPosition(result)
    }
    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        guard let start = checkedPosition(position) else { return nil }
        switch direction {
        case .left, .right:
            guard offset != Int.min else { return nil }
            return self.position(from: position, offset: direction == .left ? -offset : offset)
        case .up, .down:
            let caret = viewRect(rendered.caretRect(for: start))
            let y = caret.midY + CGFloat(offset) * max(1, caret.height) * (direction == .up ? -1 : 1)
            return closestPosition(to: CGPoint(x: caret.minX, y: y))
        @unknown default: return nil
        }
    }
    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        let distance = offset(from: position, to: other)
        return distance == 0 ? .orderedSame : (distance > 0 ? .orderedAscending : .orderedDescending)
    }
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        guard let start = checkedPosition(from), let end = checkedPosition(toPosition) else { return 0 }
        return rendered.offset(from: start, to: end) ?? 0
    }
    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        guard let range = checkedRange(range) else { return nil }
        return ReaderTextPosition(direction == .left || direction == .up ? range.lowerBound : range.upperBound)
    }
    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        guard let start = checkedPosition(position) else { return nil }
        let text = rendered.text(in: rendered.documentRange) as NSString
        guard let offset = rendered.offset(from: rendered.documentRange.lowerBound, to: start) else { return nil }
        let backward = direction == .left || direction == .up
        let index = backward ? offset - 1 : offset
        guard index >= 0, index < text.length else { return nil }
        let range = text.rangeOfComposedCharacterSequence(at: index)
        guard let a = rendered.position(from: rendered.documentRange.lowerBound, offset: range.location),
            let b = rendered.position(from: a, offset: range.length) else { return nil }
        return ReaderTextRange(TextRange(a, b))
    }
    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        .natural
    }
    func firstRect(for range: UITextRange) -> CGRect {
        guard let range = checkedRange(range) else { return .zero }
        return selectionGeometry(for: range).first ?? viewRect(rendered.caretRect(for: range.lowerBound))
    }
    func caretRect(for position: UITextPosition) -> CGRect {
        checkedPosition(position).map { viewRect(rendered.caretRect(for: $0)) } ?? .zero
    }
    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        guard let range = checkedRange(range) else { return [] }
        let rects = selectionGeometry(for: range)
        return rects.enumerated().map { index, rect in
            ReaderSelectionRect(rect, first: index == 0, last: index == rects.count - 1)
        }
    }
    func closestPosition(to point: CGPoint) -> UITextPosition? {
        ReaderTextPosition(rendered.position(closestTo: documentPoint(point)))
    }
    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        guard let range = checkedRange(range) else { return nil }
        return ReaderTextPosition(min(
            range.upperBound, max(range.lowerBound, rendered.position(closestTo: documentPoint(point)))))
    }
    func characterRange(at point: CGPoint) -> UITextRange? {
        guard let position = closestPosition(to: point) else { return nil }
        return characterRange(byExtending: position, in: .right)
            ?? characterRange(byExtending: position, in: .left)
    }
    private func checkedPosition(_ position: UITextPosition) -> TextPosition? {
        guard let position = position as? ReaderTextPosition,
            rendered.offset(from: rendered.documentRange.lowerBound, to: position.value) != nil else { return nil }
        return position.value
    }
    private func checkedRange(_ range: UITextRange) -> TextRange? {
        guard let range = range as? ReaderTextRange,
            rendered.offset(from: range.value.lowerBound, to: range.value.upperBound) != nil else { return nil }
        return range.value
    }

    func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool {
        return hasText && becomeFirstResponder()
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Native text selection handles double taps and long presses. The link
        // recognizer only participates when a link is actually under the finger.
        dismissingSelection = !(selection?.isEmpty ?? true)
        return dismissingSelection || rendered.link(at: documentPoint(touch.location(in: self))) != nil
    }
    @objc private func openTappedLink(_ gesture: UITapGestureRecognizer) {
        if dismissingSelection { clearSelection(); return }
        guard let url = rendered.link(at: documentPoint(gesture.location(in: self))) else { return }
        onLink?(url)
    }

    // Read-only even if an input method or responder action requests editing.
    func insertText(_ text: String) {}
    func deleteBackward() {}
    func replace(_ range: UITextRange, withText text: String) {}
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {}
    func unmarkText() {}
    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}
}
