import AppKit
import KasumiMarkdown
import SwiftUI

enum MacPane: String {
    case navigator = "mac.navigator-visible"
    case outline = "mac.outline-visible"

    var isVisible: Bool {
        get { UserDefaults.standard.object(forKey: rawValue) as? Bool ?? true }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: rawValue) }
    }
}

/// Use a window-level split so AppKit can place window chrome beside the sidebar.
final class MacNavigatorSplit: NSSplitViewController, NSToolbarDelegate {
    private static let sidebar = NSToolbarItem.Identifier("Sidebar")
    private static let outline = NSToolbarItem.Identifier("Outline")
    private static let source = NSToolbarItem.Identifier("Source")
    private let session: MacReaderSession
    private var tabSelection: NSKeyValueObservation?
    private var navigator: NSSplitViewItem?
    private var inspector: NSSplitViewItem?
    private weak var sourceItem: NSToolbarItem?

    init(session: MacReaderSession, undoManager: UndoManager?) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        splitView = MacDropSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebarHost = NSHostingController(rootView: MacNavigatorPane(session: session))
        sidebarHost.sizingOptions = []
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebar.minimumThickness = 165
        sidebar.maximumThickness = 330
        sidebar.preferredThicknessFraction = 0.2
        sidebar.canCollapse = false
        sidebar.isCollapsed = !MacPane.navigator.isVisible
        addSplitViewItem(sidebar)
        navigator = sidebar

        let workspace = NSHostingController(
            rootView: MacReaderScreen(
                session: session, undoManager: undoManager,
                refreshSourceToolbar: { [weak self] in self?.refreshSourceToolbar() }))
        workspace.sceneBridgingOptions = []
        workspace.sizingOptions = []
        let detail = NSSplitViewItem(viewController: workspace)
        detail.automaticallyAdjustsSafeAreaInsets = false
        addSplitViewItem(detail)

        let outline = NSHostingController(rootView: MacOutlinePane(session: session))
        outline.sizingOptions = []
        outline.view.frame.size.width = 210
        let inspector = NSSplitViewItem(inspectorWithViewController: outline)
        inspector.minimumThickness = 155
        inspector.maximumThickness = 350
        inspector.preferredThicknessFraction = 0.21
        inspector.holdingPriority = .defaultHigh
        inspector.canCollapse = false
        inspector.isCollapsed = !MacPane.outline.isVisible
        addSplitViewItem(inspector)
        self.inspector = inspector
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(session:undoManager:) instead") }

    func installToolbar(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "KasumiDocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        tabSelection = window.observe(\.tabGroup?.selectedWindow, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                if window.tabGroup?.selectedWindow === window { self?.applyPanePreferences(animated: false) }
            }
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.sidebar, .sidebarTrackingSeparator, .inspectorTrackingSeparator, .flexibleSpace, Self.outline,
            Self.source
        ]
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
        case .inspectorTrackingSeparator:
            NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitView, dividerIndex: 1)
        case Self.outline:
            makeToolbarItem(identifier, title: "Outline", symbol: "sidebar.right", action: #selector(toggleOutline))
        case Self.source:
            makeSourceItem(identifier)
        default:
            nil
        }
    }

    override func toggleSidebar(_ sender: Any?) {
        toggle(.navigator)
    }

    @objc private func toggleOutline() { toggle(.outline) }

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

    func toggle(_ pane: MacPane) {
        pane.isVisible.toggle()
        // AppKit reports unselected tabs as visible. Leave their split untouched until selection.
        for window in NSApp.windows {
            guard let split = window.contentViewController as? MacNavigatorSplit,
                (window.tabGroup?.selectedWindow ?? window) === window
            else { continue }
            split.applyPanePreferences(animated: split === self)
        }
    }

    private func applyPanePreferences(animated: Bool) {
        setVisible(MacPane.navigator.isVisible, item: navigator, animated: animated)
        setVisible(MacPane.outline.isVisible, item: inspector, animated: animated)
    }

    private func setVisible(_ visible: Bool, item: NSSplitViewItem?, animated: Bool) {
        guard let item, item.isCollapsed == visible else { return }
        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            item.isCollapsed = !visible
        } else {
            item.animator().isCollapsed = !visible
        }
    }
}

private struct MacOutlinePane: View {
    let session: MacReaderSession

    var body: some View {
        ReaderOutline(
            items: session.outline, currentID: session.currentHeadingID, searchable: false, select: session.jump
        )
        .accessibilityIdentifier("mac-outline")
        .modifier(MacPaperWash())
    }
}

private struct MacNavigatorPane: View {
    let session: MacReaderSession

    var body: some View {
        MacNavigator(documentURL: session.document.fileURL) { url in
            (NSDocumentController.shared as? MacDocumentController)?.open(url, from: session.window, fragment: nil)
        }
        .modifier(MacPaperWash())
    }
}

/// Tints a side pane toward the page, leaving the system material visible so it still reads as chrome.
private struct MacPaperWash: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private var preferences = MacAppearancePreferences()

    func body(content: Content) -> some View {
        let paper = preferences.appearance.theme(dark: colorScheme == .dark).document["paper"]
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                (paper.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha * 0.5) }
                    ?? .clear)
                    .ignoresSafeArea()
                    // The page shows a new theme only after its layout, so ease toward it.
                    .animation(.easeInOut(duration: 0.2), value: paper)
            }
    }
}
