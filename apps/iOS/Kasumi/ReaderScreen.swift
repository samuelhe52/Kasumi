import KasumiMarkdown
import KasumiMarkdownUI
import SwiftUI

struct ReaderScreen: View {
    let document: ReaderDocument
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("reader.preset") private var presetID = "serif"
    @AppStorage("reader.theme-pair") private var pairID = "mono"
    @AppStorage("reader.font-size") private var fontSize = ReaderAppearance.defaultFontSize
    @AppStorage("reader.preset-spacing") private var presetSpacing = ReaderPresetSpacing()
    @State private var viewport = ReaderViewport()
    @State private var readerWindow = ReaderWindowReference()
    @State private var findPresented = false
    @State private var pendingLink: URL?
    @State private var showLinkConfirmation = false
    @State private var showLinkFailure = false
    @State private var showAppearance = false
    @State private var showOutline = false
    @State private var showExport = false
    @State private var showInspector = false
    @State private var showDeleteConfirmation = false
    @State private var handoffID = UUID()
    @State private var windowScene: UIWindowScene?
    @State private var editingSource = false
    @State private var hasEditedSource = false
    @State private var showPreview = false
    @State private var editorState = SourceEditorState()

    private var regular: Bool { horizontalSizeClass == .regular }
    private var sourcePreviewPlacement: ToolbarItemPlacement {
        if #available(iOS 27.0, *) { return .topBarTrailing }
        return .topBarLeading
    }
    private var sourceDonePlacement: ToolbarItemPlacement {
        if #available(iOS 27.0, *) { return .topBarPinnedTrailing }
        return .topBarTrailing
    }
    private var appearance: ReaderAppearance {
        ReaderAppearance(presetID: presetID, pairID: pairID, fontSize: fontSize)
    }
    // Read in `style` so a downloaded face re-resolves the preset's families.
    private var fontStore: FontStore { .shared }
    private var style: RenderStyle {
        _ = fontStore.revision
        let appearance = self.appearance
        return appearance.style(
            dark: colorScheme == .dark, regular: regular, preferredOpen: fontStore.preferredOpen,
            spacing: presetSpacing[appearance.preset])
    }
    private var appearanceSettings: some View {
        AppearanceSettings(presetID: $presetID, pairID: $pairID, fontSize: $fontSize, presetSpacing: $presetSpacing)
    }
    private var paper: Color {
        return appearance.theme(dark: colorScheme == .dark).document["paper"].map {
            Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha)
        } ?? Color(.sRGB, white: colorScheme == .dark ? 0.15 : 0.98, opacity: 1)
    }

    var body: some View {
        MarkdownReaderScope { proxy in
            readerBody(scrollTo: { proxy.scroll(toAnchorID: $0) })
        }
    }

    private func readerBody(scrollTo: @escaping (String) -> Void) -> some View {
        readerChrome(scrollTo: scrollTo)
            .background(paper.ignoresSafeArea())
            .background {
                if #unavailable(iOS 26.0) {
                    Color.clear.alert(
                        "Delete \(document.title)?", isPresented: $showDeleteConfirmation
                    ) {
                        Button("Delete", role: .destructive, action: delete)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This can't be undone.")
                    }
                }
            }
            .sheet(isPresented: $showOutline) { outlineSheet(scrollTo: scrollTo) }
            .sheet(isPresented: $showExport) {
                if let parsed = document.snapshot?.parsed {
                    ReaderExportSheet(document: parsed, title: document.title, style: style)
                }
            }
            .sheet(
                isPresented: Binding(get: { showAppearance && (!regular || usesLegacyToolbar) }, set: { showAppearance = $0 })
            ) {
                appearanceSettings
            }
            .confirmationDialog("Open External Link?", isPresented: $showLinkConfirmation, titleVisibility: .visible) {
                Button("Open Link") {
                    guard let pendingLink else { return }
                    openURL(pendingLink) { accepted in showLinkFailure = !accepted }
                }
                Button("Cancel", role: .cancel) { pendingLink = nil }
            } message: {
                Text(pendingLink?.absoluteString ?? "")
            }
            .alert("Could Not Open Link", isPresented: $showLinkFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("No application could open this link.")
            }
            .fontOnboarding()
            .onChange(of: showPreview) { _, preview in
                editorState.previewDidChange(isVisible: preview)
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { viewport.flush() } }
            .onChange(of: paper) { _, color in readerWindow.value?.backgroundColor = UIColor(color) }
            // A file handed to the app while this reader shows closes it first.
            .background(
                WindowReader { window in
                    readerWindow.value = window
                    window.backgroundColor = UIColor(paper)
                    guard let scene = window.windowScene else { return }
                    windowScene = scene
                    DocumentBrowser.readerAppeared(handoffID, in: scene) { closeReader() }
                }
            )
            .onDisappear {
                viewport.flush()
                if let windowScene { DocumentBrowser.readerDisappeared(handoffID, in: windowScene) }
            }
    }

    private var usesLegacyToolbar: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    private var paneEdges: Edge.Set {
        usesLegacyToolbar ? .bottom : [.top, .bottom]
    }

    @ViewBuilder
    private func readerChrome(scrollTo: @escaping (String) -> Void) -> some View {
        if #available(iOS 26.0, *) {
            readerToolbar(scrollTo: scrollTo).toolbarTitleMenu { documentActions }
        } else {
            // On iOS 18 the document host can repeatedly lay out SwiftUI's
            // toolbar during opening and omit the system Back button on reopen.
            workspace
                .safeAreaInset(edge: .top, spacing: 0) { legacyReaderBar }
        }
    }

    private var legacyReaderBar: some View {
        HStack(spacing: 12) {
            if editingSource {
                SourceHistoryControls(state: editorState)
                Spacer()
                sourcePreviewButton
                sourceDoneButton
            } else {
                Button {
                    closeReader()
                } label: {
                    Image(systemName: "chevron.backward")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("reader-back")
                Text(verbatim: document.title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                findButton.frame(width: 44, height: 44)
                readerMenu.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(paper)
    }

    private func readerToolbar(scrollTo: @escaping (String) -> Void) -> some View {
        workspace
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            // On iPad the outline is a trailing inspector beside the text. Compact
            // widths use the full-height sheet below instead of the inspector's
            // own sheet, which has no Done button or paper background.
            .inspector(
                isPresented: Binding(get: { showInspector && regular }, set: { showInspector = $0 })
            ) {
                // Built only on iPad: even closed, the outline's search field
                // otherwise lands in the iPhone reader's bar.
                if regular {
                    outline(scrollTo: scrollTo)
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
                }
            }
            // Attach outside the inspector so the DocumentGroup receives the toolbar.
            .toolbar {
                if editingSource {
                    // Native bar items keep the soft scroll edge; a custom row
                    // under the bar would need its own opaque background.
                    ToolbarItem(placement: sourcePreviewPlacement) {
                        sourcePreviewButton
                    }
                    // History sits where the reader keeps its actions. The bottom
                    // bar hides behind the keyboard; SourceTextView carries the
                    // same pair above it.
                    ToolbarItemGroup(placement: .bottomBar) {
                        SourceHistoryControls(state: editorState)
                        Spacer()
                    }
                    // Done must never fall into the overflow menu on iPhone.
                    ToolbarItem(placement: sourceDonePlacement) {
                        sourceDoneButton
                    }
                } else {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        findButton
                        modernReaderMenu
                    }
                }
            }
    }

    private var findButton: some View {
        Button("Find", systemImage: "magnifyingglass") { findPresented = true }
            .labelStyle(.iconOnly)
            .keyboardShortcut("f", modifiers: .command)
            .disabled(document.snapshot == nil)
            .accessibilityIdentifier("reader-find")
    }

    private var sourcePreviewButton: some View {
        Button(
            showPreview ? "Show Source" : "Show Preview",
            systemImage: showPreview ? "square.and.pencil" : "eye"
        ) {
            showPreview.toggle()
        }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("source-preview-toggle")
    }

    private var sourceDoneButton: some View {
        Button("Done") {
            editorState.finishEditing()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                editingSource = false
            }
        }
        .accessibilityIdentifier("source-done")
    }

    @ViewBuilder
    private var documentActions: some View {
        Button("Copy Markdown", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = document.text
        }
        .disabled(document.snapshot == nil)
        if let url = document.fileURL {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var readerMenu: some View {
        Menu("Reader Actions", systemImage: "ellipsis") {
            if regular && !usesLegacyToolbar {
                Button("Outline", systemImage: "sidebar.trailing") {
                    withAnimation { showInspector.toggle() }
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .accessibilityIdentifier("reader-outline")
            } else {
                Button("Outline", systemImage: "list.bullet.indent") { showOutline = true }
                    .accessibilityIdentifier("reader-outline")
            }
            Button("Appearance", systemImage: "textformat.size") { showAppearance = true }
                .accessibilityIdentifier("reader-appearance")
            Button("Export", systemImage: "square.and.arrow.up") { showExport = true }
                .disabled(!document.previewIsCurrent)
                .accessibilityIdentifier("reader-export")
            if !editingSource {
                Button("Edit", systemImage: "square.and.pencil") {
                    hasEditedSource = true
                    showPreview = false
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        editingSource = true
                    }
                }
                .disabled(!document.canEdit)
                .accessibilityIdentifier("reader-edit-source")
            }
            if isImport {
                Section {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .accessibilityIdentifier("reader-delete")
                }
            }
            if document.isPlainText {
                Section {
                    Button(
                        document.parsePlainTextAsMarkdown ? "Parse as Text" : "Parse as Markdown",
                        systemImage: "chevron.left.forwardslash.chevron.right"
                    ) {
                        document.setParsePlainTextAsMarkdown(!document.parsePlainTextAsMarkdown)
                    }
                    .disabled(document.snapshot == nil)
                    .accessibilityIdentifier("reader-parse-as-markdown")
                }
            }
            if #unavailable(iOS 26.0) {
                Section { documentActions }
            }
        }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("reader-actions")
    }

    private var modernReaderMenu: some View {
        // Present from the persistent menu control, not its transient menu items.
        readerMenu
            .popover(
                isPresented: Binding(get: { showAppearance && regular }, set: { showAppearance = $0 })
            ) {
                appearanceSettings.frame(width: 360)
            }
            .confirmationDialog(
                "Delete \(document.title)?", isPresented: $showDeleteConfirmation, titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: delete)
            } message: {
                Text("This can't be undone.")
            }
    }

    /// Both panes stay mounted once editing starts, so the caret, scroll
    /// positions and find state survive Source/Preview switches.
    private var workspace: some View {
        let sourceVisible = editingSource && !showPreview
        let previewVisible = !editingSource || showPreview
        return ZStack {
            if hasEditedSource {
                SourceEditor(document: document, state: editorState, paper: paper, isVisible: sourceVisible)
                    .ignoresSafeArea(.all, edges: paneEdges)
            }
            reader(isActive: previewVisible)
        }
        .softTopScrollEdge()
    }

    private func outlineSheet(scrollTo: @escaping (String) -> Void) -> some View {
        NavigationStack {
            outline(scrollTo: scrollTo)
                .navigationTitle("Outline")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { showOutline = false }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(paper)
    }

    private func reader(isActive: Bool) -> some View {
        Group {
            if let snapshot = document.snapshot {
                let style = self.style
                let codeColor = style.theme.document["secondary_text"].map {
                    UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
                } ?? .secondaryLabel
                MarkdownReader(
                    document: snapshot.parsed, style: style, documentURL: document.fileURL,
                    initialAnchor: viewport.prepare(fileURL: document.fileURL),
                    isActive: isActive, layoutRevision: fontStore.revision
                )
                .markdownFindNavigator(isPresented: $findPresented)
                .markdownRemoteImages(.http)
                .markdownCodeBlockControl(id: codeColor) { block in
                    guard let frame = ReaderCodeBlockStyle.copyButtonFrame(in: block) else { return nil }
                    return ReaderCodeCopyButton(block: block, frame: frame, color: codeColor)
                }
                .onMarkdownPositionChange { anchor, heading in viewport.moved(anchor: anchor, heading: heading) }
                .onMarkdownLink { url in
                    pendingLink = url
                    showLinkConfirmation = true
                }
                // Paint behind the floating find panel as well as the toolbars.
                .ignoresSafeArea(.all, edges: paneEdges)
            } else {
                ProgressView("Opening document…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func outline(scrollTo: @escaping (String) -> Void) -> some View {
        ReaderOutline(
            items: document.snapshot?.parsed.outline ?? [], currentID: viewport.headingID,
            searchable: !regular
        ) { item in
            showPreview = true
            scrollTo(item.id)
            showOutline = false
        }
    }

    private var isImport: Bool { document.fileURL.map(ImportFolder.contains) ?? false }

    private func closeReader() {
        dismiss()
        if usesLegacyToolbar, let windowScene {
            // The iOS 18 document host can retain the reader under the browser
            // without delivering SwiftUI's onDisappear.
            viewport.flush()
            DocumentBrowser.readerDisappeared(handoffID, in: windowScene)
        }
    }

    /// Pasted and downloaded documents can be deleted from the reader controls
    /// after a confirmation. The file is removed after closing; coordination
    /// waits for the document's file session to let go.
    private func delete() {
        guard let url = document.fileURL else { return }
        viewport.forget()
        closeReader()
        Task.detached {
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(
                writingItemAt: url, options: .forDeleting, error: &coordinationError
            ) { target in
                do { try FileManager.default.removeItem(at: target) } catch {
                    NSLog("Delete failed %@: %@", target.lastPathComponent, error.localizedDescription)
                }
            }
            if let coordinationError {
                NSLog("Delete failed %@: %@", url.lastPathComponent, coordinationError.localizedDescription)
            }
        }
    }
}

private struct SourceHistoryControls: View {
    let state: SourceEditorState

    var body: some View {
        Button("Undo", systemImage: "arrow.uturn.backward", action: state.undo)
            .disabled(!state.canUndo)
            .accessibilityIdentifier("source-undo")
        Button("Redo", systemImage: "arrow.uturn.forward", action: state.redo)
            .disabled(!state.canRedo)
            .accessibilityIdentifier("source-redo")
    }
}

@MainActor
private final class ReaderWindowReference {
    weak var value: UIWindow?
}
