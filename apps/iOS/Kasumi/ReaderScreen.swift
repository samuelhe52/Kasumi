import KasumiMarkdown
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
    @AppStorage("reader.font-size") private var fontSize: Double = 0
    @State private var viewport = ReaderViewport()
    @State private var findRequest = 0
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
    private var appearance: ReaderAppearance {
        ReaderAppearance(presetID: presetID, pairID: pairID, fontSize: fontSize)
    }
    // Read in `style` so a downloaded face re-resolves the preset's families.
    private var fontStore: FontStore { .shared }
    private var style: RenderStyle {
        _ = fontStore.revision
        return appearance.style(
            dark: colorScheme == .dark, regular: regular, preferredOpen: fontStore.preferredOpen)
    }
    private var paper: Color {
        if let rendered = viewport.rendered { return Color(cgColor: rendered.backgroundColor) }
        return appearance.theme(dark: colorScheme == .dark).document["paper"].map {
            Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha)
        } ?? Color(.sRGB, white: colorScheme == .dark ? 0.15 : 0.98, opacity: 1)
    }

    var body: some View {
        workspace
            // On iPad the outline is a trailing inspector beside the text. Compact
            // widths use the full-height sheet below instead of the inspector's
            // own sheet, which has no Done button or paper background.
            .inspector(
                isPresented: Binding(get: { showInspector && regular }, set: { showInspector = $0 })
            ) {
                // Built only on iPad: even closed, the outline's search field
                // otherwise lands in the iPhone reader's bar.
                if regular {
                    outline
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
                }
            }
            // Attach outside the inspector so the DocumentGroup receives the toolbar.
            .toolbar {
                if editingSource {
                    // Native bar items keep the soft scroll edge; a custom row
                    // under the bar would need its own opaque background.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            showPreview ? "Show Source" : "Show Preview",
                            systemImage: showPreview ? "square.and.pencil" : "eye"
                        ) {
                            showPreview.toggle()
                        }
                        .accessibilityIdentifier("source-preview-toggle")
                    }
                    // History sits where the reader keeps its actions. The bottom
                    // bar hides behind the keyboard; SourceTextView carries the
                    // same pair above it.
                    ToolbarItemGroup(placement: .bottomBar) {
                        SourceHistoryControls(state: editorState)
                        Spacer()
                    }
                    // Done must never fall into the overflow menu on iPhone.
                    ToolbarItem(placement: .topBarPinnedTrailing) {
                        Button("Done") {
                            editorState.finishEditing()
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                editingSource = false
                            }
                        }
                        .accessibilityIdentifier("source-done")
                    }
                } else {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        readerMenu
                    }
                }
            }
            .background(paper.ignoresSafeArea())
            .sheet(isPresented: $showOutline) { outlineSheet }
            .sheet(isPresented: $showExport) {
                if let parsed = document.snapshot?.parsed {
                    ReaderExportSheet(document: parsed, title: document.title, style: style)
                }
            }
            .sheet(
                isPresented: Binding(get: { showAppearance && !regular }, set: { showAppearance = $0 })
            ) {
                AppearanceSettings(presetID: $presetID, pairID: $pairID, fontSize: $fontSize)
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
            .onChange(of: presetID) { _, _ in fontSize = 0 }
            .onChange(of: showPreview) { _, preview in
                editorState.previewDidChange(isVisible: preview)
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { viewport.flush() } }
            // A file handed to the app while this reader shows closes it first.
            .background(
                WindowReader { window in
                    guard let scene = window.windowScene else { return }
                    windowScene = scene
                    DocumentBrowser.readerAppeared(handoffID, in: scene) { dismiss() }
                }
            )
            .onDisappear {
                viewport.flush()
                if let windowScene { DocumentBrowser.readerDisappeared(handoffID, in: windowScene) }
            }
    }

    private var readerMenu: some View {
        Menu("Reader Actions", systemImage: "ellipsis") {
            if regular {
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
            Button("Find", systemImage: "magnifyingglass") { findRequest += 1 }
                .accessibilityIdentifier("reader-find")
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
        }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("reader-actions")
        // Present from the persistent menu control, not its transient menu items.
        .popover(
            isPresented: Binding(get: { showAppearance && regular }, set: { showAppearance = $0 })
        ) {
            AppearanceSettings(presetID: $presetID, pairID: $pairID, fontSize: $fontSize)
                .frame(width: 360)
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
                    .ignoresSafeArea(.all, edges: [.top, .bottom])
            }
            reader(isActive: previewVisible)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var outlineSheet: some View {
        NavigationStack {
            outline
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
                let parsed = snapshot.parsed
                ReadingSurface(
                    document: parsed, revision: snapshot.revision, style: style, fontRevision: fontStore.revision,
                    outline: parsed.outline, fileURL: document.fileURL, viewport: viewport, findRequest: findRequest,
                    isActive: isActive,
                    openLink: { url in
                        pendingLink = url
                        showLinkConfirmation = true
                    }
                )
                // Paint behind the floating find panel as well as the toolbars.
                .ignoresSafeArea(.all, edges: [.top, .bottom])
            } else {
                ProgressView("Opening document…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var outline: some View {
        ReaderOutline(
            items: document.snapshot?.parsed.outline ?? [], currentID: viewport.headingID,
            searchable: !regular
        ) { item in
            showPreview = true
            viewport.jump(to: item.id)
            showOutline = false
        }
    }

    private var isImport: Bool { document.fileURL.map(ImportFolder.contains) ?? false }

    /// Pasted and downloaded documents can be deleted from the reader controls
    /// after a confirmation. The file is removed after closing; coordination
    /// waits for the document's file session to let go.
    private func delete() {
        guard let url = document.fileURL else { return }
        viewport.forget()
        dismiss()
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
