import AppKit

final class MacDocumentWindowController: NSWindowController, NSMenuItemValidation {
    enum Placement {
        case automatic, separate
        case tab(NSWindow)
    }

    private var didPlaceWindow = false
    private var readerHasLayout = false
    private var presentation: Task<Void, Never>?
    /// Where the window goes when first shown.
    var placement = Placement.automatic

    init(session: MacReaderSession, undoManager: UndoManager?) {
        let host = MacNavigatorSplit(session: session, undoManager: undoManager)
        let contentSize = NSSize(width: 1000, height: 720)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true)
        window.tabbingIdentifier = "KasumiDocument"
        window.identifier = NSUserInterfaceItemIdentifier("KasumiDocument")
        window.restorationClass = NSDocumentController.self
        window.isRestorable = true
        window.contentMinSize = NSSize(width: 460, height: 320)
        window.contentViewController = host
        host.installToolbar(in: window)
        window.setContentSize(contentSize)
        window.center()
        super.init(window: window)
        session.attach(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(session:undoManager:) instead") }

    override func restoreState(with coder: NSCoder) {
        didPlaceWindow = true
        super.restoreState(with: coder)
    }

    override func showWindow(_ sender: Any?) {
        guard presentation == nil else { return }
        // Don't retain a tab target past the first showing.
        let placement = self.placement
        self.placement = .automatic
        let places = !didPlaceWindow && canJoinTabGroup
        didPlaceWindow = true
        // Look the target up now, while an open request still knows its source.
        let target = places ? destination(for: placement) : nil
        let preparesReader =
            places && !readerHasLayout && (document as? MacDocument)?.session?.showingSource == false
        if preparesReader, let window {
            // A reader can lay out in an attached but unordered window.
            if let target { window.setFrame(target.frame, display: false) }
            window.contentView?.layoutSubtreeIfNeeded()
        }
        guard preparesReader || isSlidingIn(outgoingTab(for: target)) else {
            present(sender, places: places, target: target, placement: placement)
            return
        }

        var separate = false
        if case .separate = placement { separate = true }
        presentation = Task { @MainActor [weak self, weak target] in
            // Keep the current tab on screen until the new one has a viewport,
            // but let a slow document show its progress indicator.
            if preparesReader {
                await Self.poll(for: .milliseconds(500)) { self?.readerHasLayout == false }
            }
            // Selecting a tab replaces the window Stage Manager is sliding in.
            await Self.poll(for: .milliseconds(750)) {
                guard let self else { return false }
                return self.isSlidingIn(self.outgoingTab(for: target))
            }
            guard let self else { return }
            presentation = nil
            guard (document as? MacDocument)?.session != nil else { return }
            present(sender, places: places, target: target, placement: separate ? .separate : .automatic)
        }
    }

    func readerDidLayOut() {
        readerHasLayout = true
    }

    private static func poll(for limit: Duration, while condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline, condition() {
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private var canJoinTabGroup: Bool {
        guard let window, let document = document as? MacDocument else { return false }
        return !window.isVisible && (window.tabGroup?.windows.count ?? 0) < 2 && !document.isInViewingMode
    }

    /// The key window, if showing this window would replace it as the selected tab.
    private func outgoingTab(for target: NSWindow?) -> NSWindow? {
        guard let window, let key = NSApp.keyWindow, key !== window else { return nil }
        return (target?.tabGroup?.selectedWindow ?? target ?? window.tabGroup?.selectedWindow) === key ? key : nil
    }

    /// Stage Manager scales the window without changing `NSWindow.frame`, and
    /// posts nothing when it finishes, so compare with the width on screen.
    private func isSlidingIn(_ window: NSWindow?) -> Bool {
        guard let window, window.windowNumber > 0 else { return false }
        // Quartz Window Services encodes window IDs as raw CFArray values.
        var windowID = UnsafeRawPointer(bitPattern: window.windowNumber)
        let ids = CFArrayCreate(nil, &windowID, 1, nil)
        let descriptions = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]]
        guard let bounds = descriptions?.first?[kCGWindowBounds as String] as? NSDictionary,
            let presented = CGRect(dictionaryRepresentation: bounds)
        else { return false }
        // WindowServer rounds its bounds to whole points.
        return abs(presented.width - window.frame.width) > 2
    }

    private func present(_ sender: Any?, places: Bool, target: NSWindow?, placement: Placement) {
        if places, canJoinTabGroup, let window {
            // An earlier target may have closed. Files opened together at launch
            // had none, because no window was on screen yet.
            let usable = target.flatMap { target -> NSWindow? in
                let selected = target.tabGroup?.selectedWindow ?? target
                return selected.isVisible && !selected.isMiniaturized ? selected : nil
            }
            if let target = usable ?? destination(for: placement) {
                if let group = target.tabGroup {
                    group.insertWindow(window, at: group.windows.count)
                } else {
                    target.addTabbedWindow(window, ordered: .above)
                }
            }
        }
        if case .separate = placement, let window {
            let tabbingMode = window.tabbingMode
            window.tabbingMode = .disallowed
            super.showWindow(sender)
            window.tabbingMode = tabbingMode
        } else {
            super.showWindow(sender)
        }
    }

    private func destination(for placement: Placement) -> NSWindow? {
        guard let window else { return nil }
        return switch placement {
        case .separate: nil
        case .tab(let target): target
        case .automatic:
            (NSDocumentController.shared as? MacDocumentController)?
                .destination(for: window, url: (document as? MacDocument)?.fileURL)
        }
    }

    private var commandSession: MacReaderSession? {
        guard let window, window.attachedSheet == nil, NSApp.keyWindow === window else {
            return nil
        }
        return (document as? MacDocument)?.session
    }

    @objc func performReaderCommand(_ item: NSMenuItem) {
        guard let session = commandSession, let command = item.representedObject as? MacReaderCommand,
            command.isEnabled(for: session)
        else { return }
        command.perform(in: session)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(newWindowForTab(_:)) {
            return commandSession != nil && (document as? MacDocument)?.isInViewingMode == false
        }
        guard let command = item.representedObject as? MacReaderCommand, let session = commandSession else {
            return false
        }
        return command.validate(item, for: session)
    }

    override func newWindowForTab(_ sender: Any?) {
        // A version browser window isn't a place for new documents.
        guard let window, (document as? MacDocument)?.isInViewingMode == false else { return }
        (NSDocumentController.shared as? MacDocumentController)?.newDocument(inTabOf: window)
    }
}
