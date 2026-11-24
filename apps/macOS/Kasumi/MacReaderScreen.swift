import AppKit
import KasumiMarkdown
import KasumiMarkdownUI
import SwiftUI
import UniformTypeIdentifiers

struct MacReaderScreen: View {
    let session: MacReaderSession
    let undoManager: UndoManager?
    let setNavigatorVisible: (Bool) -> Void
    let refreshSourceToolbar: () -> Void
    private var document: ReaderDocument { session.document }
    @Environment(\.colorScheme) private var colorScheme
    private var panes = MacPanePreferences()
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
        MarkdownReaderScope { proxy in
            MacWorkspace(
                session: session, style: style, layoutRevision: fonts.revision, undoManager: undoManager,
                openLink: openLink)
            .inspector(isPresented: panes.$outlineVisible) {
                ReaderOutline(
                    items: session.outline, currentID: session.currentHeadingID, searchable: false, select: session.jump
                )
                .inspectorColumnWidth(min: 155, ideal: 210, max: 350)
                .accessibilityIdentifier("mac-outline")
            }
            .onAppear { session.connect(to: proxy) }
            .onChange(of: style, initial: true) { _, style in session.style = style }
            .onChange(of: panes.navigatorVisible, initial: true) { _, visible in setNavigatorVisible(visible) }
            .onChange(of: session.showingSource) { refreshSourceToolbar() }
            .onChange(of: document.snapshot != nil) { refreshSourceToolbar() }
        }
        .softTopScrollEdge()
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

private struct MacWorkspace: View {
    let session: MacReaderSession
    let style: RenderStyle
    let layoutRevision: Int
    let undoManager: UndoManager?
    let openLink: (URL) -> Void

    var body: some View {
        let showingSource = session.showingSource
        ZStack {
            MacReadingPane(session: session, style: style, layoutRevision: layoutRevision, openLink: openLink)
                .opacity(showingSource ? 0 : 1)
                .allowsHitTesting(!showingSource)
                .accessibilityHidden(showingSource)
            if session.hasOpenedSource {
                MacSourceEditor(
                    document: session.document, controller: session.source, style: style, undoManager: undoManager
                )
                .opacity(showingSource ? 1 : 0)
                .allowsHitTesting(showingSource)
                .accessibilityHidden(!showingSource)
            }
        }
        .softTopScrollEdge()
        .onChange(of: session.document.previewIsCurrent) { _, current in
            if current { session.previewBecameCurrent() }
        }
    }
}

private struct MacReadingPane: View {
    @Bindable var session: MacReaderSession
    let style: RenderStyle
    let layoutRevision: Int
    let openLink: (URL) -> Void

    var body: some View {
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
            .onMarkdownLink(openLink)
            .onMarkdownPositionChange { anchor, heading in
                session.readerMoved(to: anchor, heading: heading)
            }
            .softTopScrollEdge()
        } else {
            ProgressView()
        }
    }
}
