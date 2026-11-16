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
    @State private var showAppearance = false
    @State private var showOutline = false
    @State private var showInspector = false
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
            // Items declared on the content inside an inspector don't reach the
            // DocumentGroup bar, so the toolbar is attached outside it.
            .toolbar { toolbarItems }
            .background(paper.ignoresSafeArea())
            .sheet(isPresented: $showOutline) { outlineSheet }
            .sheet(
                isPresented: Binding(get: { showAppearance && !regular }, set: { showAppearance = $0 })
            ) {
                AppearanceSettings(presetID: $presetID, pairID: $pairID, fontSize: $fontSize)
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

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if regular {
            // iPad has room for every item, so Delete needn't be pinned,
            // and the inspector toggle keeps the trailing edge.
            if isImport {
                ToolbarItem(placement: .topBarTrailing) { deleteButton }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                appearanceButton
                Button("Outline", systemImage: "sidebar.trailing") {
                    withAnimation { showInspector.toggle() }
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .accessibilityIdentifier("reader-outline")
            }
        } else {
            if isImport {
                // Pinned items never move into the overflow menu, which long
                // pasted-text titles would otherwise force.
                ToolbarItem(placement: .topBarPinnedTrailing) { deleteButton }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Outline", systemImage: "list.bullet.indent") { showOutline = true }
                    .accessibilityIdentifier("reader-outline")
                appearanceButton
            }
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
                    outline: parsed.outline, fileURL: document.fileURL, viewport: viewport,
                    openLink: { url in openURL(url) }
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
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var deleteButton: some View {
        ReaderDeleteButton(title: document.title, onConfirm: delete)
    }

    private var appearanceButton: some View {
        ReaderAppearanceButton(
            isPresented: $showAppearance, regular: regular,
            presetID: $presetID, pairID: $pairID, fontSize: $fontSize)
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

    /// Pasted and downloaded documents can be deleted from the toolbar after a
    /// confirmation. The file is removed after closing; coordination waits for
    /// the document's file session to let go.
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
