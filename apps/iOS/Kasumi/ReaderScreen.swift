import KasumiMarkdown
import SwiftUI

struct ReaderScreen: View {
    let document: ReaderDocument
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("reader.preset") private var presetID = "serif"
    @AppStorage("reader.theme-pair") private var pairID = "mono"
    @AppStorage("reader.font-size") private var fontSize: Double = 0
    @State private var viewport = ReaderViewport()
    @State private var find = ReaderFindState()
    @State private var pendingLink: URL?
    @State private var showLinkConfirmation = false
    @State private var showLinkFailure = false
    @State private var showAppearance = false
    @State private var showOutline = false
    @State private var showInspector = false
    @State private var showDeleteConfirmation = false
    @State private var handoffID = UUID()
    @State private var windowScene: UIWindowScene?

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
        reader
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
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    readerMenu
                }
            }
            .background(paper.ignoresSafeArea())
            .sheet(isPresented: $showOutline) { outlineSheet }
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
            Button("Find in Document", systemImage: "magnifyingglass") { find.isPresented = true }
                .accessibilityIdentifier("reader-find")
            Button("Appearance", systemImage: "textformat.size") { showAppearance = true }
                .accessibilityIdentifier("reader-appearance")
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

    private var outlineSheet: some View {
        NavigationStack {
            outline
                .navigationTitle("Outline")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showOutline = false } }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(paper)
    }

    private var reader: some View {
        Group {
            if let snapshot = document.snapshot, let parsed = snapshot.parsed {
                ReadingSurface(
                    document: parsed, revision: snapshot.revision, style: style, fontRevision: fontStore.revision,
                    outline: parsed.outline, fileURL: document.fileURL, viewport: viewport, find: find,
                    findPresented: find.isPresented, findRevision: find.navigationRevision, findBarHeight: find.barHeight,
                    openLink: { url in
                        pendingLink = url
                        showLinkConfirmation = true
                    }
                )
                .ignoresSafeArea(.container, edges: [.top, .bottom])
            } else if let error = document.snapshot?.error {
                ContentUnavailableView(
                    "Could Not Decode Document", systemImage: "doc.badge.exclamationmark",
                    description: Text(error))
            } else {
                ProgressView("Opening document…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(paper.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            if find.isPresented { ReaderFindBar(find: find) }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var outline: some View {
        ReaderOutline(
            items: document.snapshot?.parsed?.outline ?? [], currentID: viewport.headingID,
            searchable: !regular
        ) { item in
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
