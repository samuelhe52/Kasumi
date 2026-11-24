import AppKit
import SwiftUI

/// Use a window-level split so AppKit can place window chrome beside the sidebar.
final class MacNavigatorSplit: NSSplitViewController, NSToolbarDelegate {
    private static let sidebar = NSToolbarItem.Identifier("Sidebar")
    private static let outline = NSToolbarItem.Identifier("Outline")
    private static let source = NSToolbarItem.Identifier("Source")
    private let session: MacReaderSession
    private var navigator: NSSplitViewItem?
    private weak var sourceItem: NSToolbarItem?

    init(session: MacReaderSession, undoManager: UndoManager?) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebarHost = NSHostingController(rootView: MacNavigatorPane(session: session))
        sidebarHost.sizingOptions = []
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebar.minimumThickness = 165
        sidebar.maximumThickness = 330
        sidebar.preferredThicknessFraction = 0.2
        sidebar.canCollapse = false
        sidebar.isCollapsed = !MacPanePreferences().navigatorVisible
        addSplitViewItem(sidebar)
        navigator = sidebar

        let workspace = NSHostingController(
            rootView: MacReaderScreen(
                session: session, undoManager: undoManager,
                setNavigatorVisible: { [weak self] in self?.setNavigatorVisible($0) },
                refreshSourceToolbar: { [weak self] in self?.refreshSourceToolbar() }))
        workspace.sceneBridgingOptions = []
        workspace.sizingOptions = []
        let detail = NSSplitViewItem(viewController: workspace)
        detail.automaticallyAdjustsSafeAreaInsets = false
        addSplitViewItem(detail)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(session:undoManager:) instead") }

    func installToolbar(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "KasumiDocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.outline, Self.source]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Self.sidebar:
            makeToolbarItem(identifier, title: "Sidebar", symbol: "sidebar.left", action: #selector(toggleSidebar(_:)))
        case .sidebarTrackingSeparator:
            NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitView, dividerIndex: 0)
        case Self.outline:
            makeToolbarItem(identifier, title: "Outline", symbol: "sidebar.right", action: #selector(toggleOutline))
        case Self.source:
            makeSourceItem(identifier)
        default:
            nil
        }
    }

    override func toggleSidebar(_ sender: Any?) {
        MacPanePreferences().navigatorVisible.toggle()
    }

    @objc private func toggleOutline() { MacPanePreferences().outlineVisible.toggle() }

    @objc private func toggleSource() { session.toggleSource() }

    private func makeSourceItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = makeToolbarItem(
            identifier, title: "Source", symbol: "chevron.left.forwardslash.chevron.right",
            action: #selector(toggleSource))
        sourceItem = item
        refreshSourceToolbar()
        return item
    }

    private func refreshSourceToolbar() {
        guard let sourceItem else { return }
        let showingSource = session.showingSource
        let label = showingSource ? "Reader" : "Source"
        let symbol = showingSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right"
        sourceItem.label = label
        sourceItem.toolTip = label
        sourceItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        sourceItem.isEnabled = session.document.snapshot != nil
    }

    private func makeToolbarItem(
        _ identifier: NSToolbarItem.Identifier, title: String, symbol: String, action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        item.action = action
        item.label = title
        item.toolTip = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.autovalidates = false
        return item
    }

    private func setNavigatorVisible(_ visible: Bool) {
        guard let navigator, navigator.isCollapsed == visible else { return }
        if view.window == nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            navigator.isCollapsed = !visible
        } else {
            navigator.animator().isCollapsed = !visible
        }
    }
}

private struct MacNavigatorPane: View {
    let session: MacReaderSession

    var body: some View {
        MacNavigator(documentURL: session.document.fileURL) { url in
            (NSDocumentController.shared as? MacDocumentController)?.open(url, from: session.window, fragment: nil)
        }
    }
}
