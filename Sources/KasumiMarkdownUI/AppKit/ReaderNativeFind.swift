#if os(macOS)
import AppKit
import KasumiMarkdown
import os

@MainActor final class ReaderNativeFind: NSObject, @preconcurrency NSTextFinderClient, @preconcurrency NSTextFinderBarContainer {
    weak var owner: MarkdownReaderView?
    let finder = NSTextFinder()
    var presentationPending = false
    private(set) var selection: NSRange?
    private let semanticText = OSAllocatedUnfairLock(initialState: "")

    override init() {
        super.init()
        finder.isIncrementalSearchingEnabled = true
    }
    isolated deinit {
        finder.client = nil
        finder.findBarContainer = nil
    }

    func installString(_ string: String) {
        finder.noteClientStringWillChange()
        semanticText.withLock { $0 = string }
    }

    func noteStringWillChange() {
        installString("")
        clearSelection()
    }

    func clearSelection() {
        finder.cancelFindIndicator()
        guard selection != nil else { return }
        selection = nil
        selectionDidChange()
    }

    private func selectionDidChange() {
        guard let owner else { return }
        owner.setHighlightsNeedDisplay()
        NSAccessibility.post(element: owner.canvas, notification: .selectedTextChanged)
    }

    var isEditable: Bool { false }
    var isSelectable: Bool { owner?.rendered != nil }
    var allowsMultipleSelection: Bool { false }
    nonisolated var string: String { semanticText.withLock { $0 } }

    var firstSelectedRange: NSRange { selection ?? owner?.canvas.selection ?? NSRange(location: 0, length: 0) }

    var selectedRanges: [NSValue] {
        get { [NSValue(range: firstSelectedRange)] }
        set {
            guard let range = newValue.first?.rangeValue,
                owner?.rendered?.readerTextRange(for: range) != nil
            else { clearSelection(); return }
            guard selection != range else { return }
            selection = range
            selectionDidChange()
        }
    }

    var visibleCharacterRanges: [NSValue] {
        guard let owner else { return [] }
        let range = owner.canvas.accessibilityVisibleCharacterRange()
        return range.length > 0 ? [NSValue(range: range)] : []
    }

    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        // NSTextFinder's client and the canvas have the same owning reader.
        guard let owner else { preconditionFailure("Find has no reader viewport") }
        outRange.pointee = NSRange(location: 0, length: owner.canvas.accessibilityNumberOfCharacters())
        return owner.canvas
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        owner?.canvas.rects(for: range).map { NSValue(rect: $0) }
    }

    func scrollRangeToVisible(_ range: NSRange) { owner?.revealNativeFindMatch(range) }

    // Forward the container contract to NSScrollView so the actual system bar
    // controls layout while we can observe its visibility, including its close button.
    var findBarView: NSView? {
        get { owner?.nativeFindBarContainer.findBarView }
        set { owner?.nativeFindBarContainer.findBarView = newValue }
    }

    var isFindBarVisible: Bool {
        get { owner?.nativeFindBarContainer.isFindBarVisible == true }
        set {
            guard let owner else { return }
            let container = owner.nativeFindBarContainer
            let before = container.isFindBarVisible
            container.isFindBarVisible = newValue
            if before != container.isFindBarVisible { owner.findBarVisibilityChanged() }
        }
    }

    var contentView: NSView? { owner?.canvas }
    func findBarViewDidChangeHeight() { owner?.nativeFindBarContainer.findBarViewDidChangeHeight() }
}

@MainActor func readerFindAction(from sender: Any?) -> NSTextFinder.Action? {
    let tag = (sender as? any NSValidatedUserInterfaceItem)?.tag ?? (sender as? NSControl)?.tag
    return tag.flatMap(NSTextFinder.Action.init(rawValue:))
}
#endif
