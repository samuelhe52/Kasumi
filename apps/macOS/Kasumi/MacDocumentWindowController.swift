import AppKit

final class MacDocumentWindowController: NSWindowController, NSMenuItemValidation {
    private var didPlaceWindow = false

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
        if !didPlaceWindow {
            didPlaceWindow = true
            if let window, let document = document as? MacDocument,
                !window.isVisible, (window.tabGroup?.windows.count ?? 0) < 2, !document.isInViewingMode,
                let controller = NSDocumentController.shared as? MacDocumentController,
                let target = controller.destination(for: window, url: document.fileURL)
            {
                if let group = target.tabGroup {
                    group.insertWindow(window, at: group.windows.count)
                } else {
                    target.addTabbedWindow(window, ordered: .above)
                }
            }
        }
        super.showWindow(sender)
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
        guard let command = item.representedObject as? MacReaderCommand, let session = commandSession else {
            return false
        }
        return command.validate(item, for: session)
    }

    override func newWindowForTab(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }
}
