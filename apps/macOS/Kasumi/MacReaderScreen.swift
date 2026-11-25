import AppKit
import KasumiMarkdown
@_spi(KasumiApp) import KasumiMarkdownUI
import SwiftUI
import UniformTypeIdentifiers

struct MacReaderScreen: View {
    let session: MacReaderSession
    let undoManager: UndoManager?
    let refreshSourceToolbar: () -> Void
    private var document: ReaderDocument { session.document }
    @Environment(\.colorScheme) private var colorScheme
    private var preferences = MacAppearancePreferences()
    private let fonts = FontStore.shared

    private var style: RenderStyle {
        let appearance = preferences.appearance
        return appearance.style(
            dark: colorScheme == .dark, regular: true, preferredOpen: fonts.preferredOpen,
            spacing: preferences.presetSpacing[appearance.preset])
    }

    var body: some View {
        let style = self.style
        MacWorkspace(
            reader: MacReadingPane(session: session, style: style, layoutRevision: fonts.revision, openLink: openLink),
            source: MacSourceEditor(
                document: document, controller: session.source, style: style, undoManager: undoManager),
            showingSource: session.showingSource
        )
        // The panes scroll beneath the header, so their paper is its background.
        .ignoresSafeArea(edges: .top)
        .onChange(of: style, initial: true) { _, style in session.style = style }
        .onChange(of: session.showingSource) { refreshSourceToolbar() }
        .onChange(of: document.snapshot != nil) { refreshSourceToolbar() }
        .onChange(of: document.previewIsCurrent) { _, current in
            if current { session.previewBecameCurrent() }
        }
    }

    private func openFile(_ url: URL, fragment: String? = nil) {
        (NSDocumentController.shared as? MacDocumentController)?.open(url, from: session.window, fragment: fragment)
    }

    private func openLink(_ url: URL) {
        let type = UTType(filenameExtension: url.pathExtension)
        // File APIs ignore a remote host and would read the local path instead.
        let isLocal = url.isFileURL && ["", "localhost"].contains(url.host()?.lowercased() ?? "")
        if isLocal, MacFolderListing.supports(url) || type?.conforms(to: .kasumiMarkdown) == true {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            components?.fragment = nil
            components?.query = nil
            if let documentURL = components?.url { openFile(documentURL, fragment: url.fragment) }
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased()) {
            NSWorkspace.shared.open(url)
        } else {
            // A document must not launch local files or arbitrary URL handlers.
            NSSound.beep()
        }
    }
}

private struct MacWorkspace: NSViewControllerRepresentable {
    let reader: MacReadingPane
    let source: MacSourceEditor
    let showingSource: Bool

    func makeNSViewController(context: Context) -> MacWorkspaceController {
        MacWorkspaceController(reader: reader)
    }

    func updateNSViewController(_ controller: MacWorkspaceController, context: Context) {
        controller.update(reader: reader, source: source, showingSource: showingSource)
    }
}

private final class MacWorkspaceController: NSViewController {
    private let reader: NSHostingController<MacReadingPane>
    private var source: NSHostingController<MacSourcePane>?
    private var activePane: NSViewController?

    init(reader: MacReadingPane) {
        self.reader = Self.host(reader)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(reader:) instead") }

    override func loadView() { view = NSView() }

    func update(reader: MacReadingPane, source: MacSourceEditor, showingSource: Bool) {
        if self.reader.rootView.style != reader.style || self.reader.rootView.layoutRevision != reader.layoutRevision {
            self.reader.rootView = reader
        }
        if let sourceHost = self.source, sourceHost.rootView.editor.style != source.style {
            sourceHost.rootView = MacSourcePane(editor: source)
        }
        if showingSource {
            let sourceHost = self.source ?? Self.host(MacSourcePane(editor: source))
            self.source = sourceHost
            show(sourceHost)
        } else {
            show(self.reader)
        }
    }

    private func show(_ pane: NSViewController) {
        guard activePane !== pane else { return }
        // Keep both hosts alive while removing the inactive view from the window's event routing.
        activePane?.view.removeFromSuperview()
        activePane?.removeFromParent()
        addChild(pane)
        pane.view.frame = view.bounds
        pane.view.autoresizingMask = [.width, .height]
        view.addSubview(pane.view)
        activePane = pane
    }

    private static func host<Content: View>(_ content: Content) -> NSHostingController<Content> {
        let host = NSHostingController(rootView: content)
        host.sceneBridgingOptions = []
        host.sizingOptions = []
        return host
    }
}

private struct MacSourcePane: View {
    let editor: MacSourceEditor

    var body: some View { editor.ignoresSafeArea(edges: .top) }
}

private struct MacReadingPane: View {
    @Bindable var session: MacReaderSession
    let style: RenderStyle
    let layoutRevision: Int
    let openLink: (URL) -> Void

    var body: some View {
        MarkdownReaderScope { proxy in
            content.onAppear { session.connect(to: proxy) }
        }
    }

    @ViewBuilder private var content: some View {
        let document = session.document
        if let snapshot = document.snapshot {
            MarkdownReader(
                document: snapshot.parsed, style: style, documentURL: document.fileURL,
                initialAnchor: session.viewport.prepare(fileURL: document.fileURL),
                isActive: !session.showingSource, layoutRevision: layoutRevision
            )
            .markdownFindNavigator(isPresented: $session.readerFindPresented)
            .markdownRemoteImages(.http)
            .markdownScroller(MacScroller.self)
            .onMarkdownFirstLayout { [weak session] in
                (session?.window?.windowController as? MacDocumentWindowController)?.readerDidLayOut()
            }
            .onMarkdownLink(openLink)
            .onMarkdownPositionChange { anchor, heading in
                session.readerMoved(to: anchor, heading: heading)
            }
            .ignoresSafeArea(edges: .top)
        } else {
            ProgressView()
        }
    }
}
