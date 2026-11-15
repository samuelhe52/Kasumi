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
    @State private var confirmDelete = false
    @State private var columns: NavigationSplitViewVisibility = .detailOnly

    private var regular: Bool { horizontalSizeClass == .regular }
    private var pair: DocumentThemePair { DocumentThemePair.builtin.first { $0.id == pairID } ?? DocumentThemePair.builtin.first { $0.id == "mono" }! }
    private var theme: DocumentTheme { colorScheme == .dark ? pair.dark : pair.light }
    private var preset: TypographyPreset { TypographyPreset.builtin.first { $0.id == presetID } ?? .default }
    private var style: RenderStyle {
        var style = RenderStyle(preset: preset, theme: theme, fontSize: fontSize > 0 ? min(28, max(12, fontSize)) : nil)
        style.insets.left = regular ? 40 : 20; style.insets.right = regular ? 40 : 20
        return style
    }
    private var paper: Color {
        if let rendered = viewport.rendered { return Color(cgColor: rendered.backgroundColor) }
        return theme.document["paper"].map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) } ?? Color(.sRGB, white: colorScheme == .dark ? 0.15 : 0.98, opacity: 1)
    }

    var body: some View {
        Group {
            if regular {
                NavigationSplitView(columnVisibility: $columns) {
                    outline
                        .navigationTitle("Outline")
                        .toolbar(removing: .sidebarToggle)
                } detail: { reader }
                .toolbar(removing: .sidebarToggle)
            } else {
                reader
            }
        }
        .background(paper.ignoresSafeArea())
        .sheet(isPresented: $showOutline) {
            NavigationStack {
                outline
                    .navigationTitle("Outline")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showOutline = false } } }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(paper)
        }
        .sheet(isPresented: Binding(get: { showAppearance && !regular }, set: { showAppearance = $0 })) {
            AppearanceSettings(presetID: $presetID, pairID: $pairID, fontSize: $fontSize)
        }
        .onChange(of: presetID) { _, _ in fontSize = 0 }
        .onChange(of: scenePhase) { _, phase in if phase != .active { viewport.flush() } }
        .onDisappear { viewport.flush() }
    }

    private var reader: some View {
        Group {
            if let snapshot = document.snapshot, let parsed = snapshot.parsed {
                ReadingSurface(document: parsed, revision: snapshot.revision, style: style,
                    outline: parsed.outline, fileURL: document.fileURL, viewport: viewport,
                    openLink: { url in openURL(url) })
                    .ignoresSafeArea(.container, edges: [.top, .bottom])
            } else if let error = document.snapshot?.error {
                ContentUnavailableView("Could Not Decode Document", systemImage: "doc.badge.exclamationmark", description: Text(error))
            } else {
                ProgressView("Opening document…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(paper.ignoresSafeArea())
        .toolbar(removing: .sidebarToggle)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isImport {
                // Pinned items never move into the overflow menu, which long
                // pasted-text titles would otherwise force.
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button("Delete", systemImage: "trash") { confirmDelete = true }
                        .accessibilityIdentifier("reader-delete")
                        .confirmationDialog("Delete \(document.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive, action: delete)
                        } message: {
                            Text("This can't be undone.")
                        }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Outline", systemImage: "list.bullet.indent") {
                    if regular { withAnimation { columns = columns == .detailOnly ? .all : .detailOnly } }
                    else { showOutline = true }
                }
                .accessibilityIdentifier("reader-outline")
                Button("Appearance", systemImage: "textformat.size") { showAppearance = true }
                    .accessibilityIdentifier("reader-appearance")
                    .popover(isPresented: Binding(get: { showAppearance && regular }, set: { showAppearance = $0 })) {
                        AppearanceSettings(presetID: $presetID, pairID: $pairID, fontSize: $fontSize)
                            .frame(width: 360)
                    }
            }
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
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
                do { try FileManager.default.removeItem(at: target) }
                catch { NSLog("Delete failed %@: %@", target.lastPathComponent, error.localizedDescription) }
            }
            if let coordinationError { NSLog("Delete failed %@: %@", url.lastPathComponent, coordinationError.localizedDescription) }
        }
    }

    private var outline: some View {
        ReaderOutline(items: document.snapshot?.parsed?.outline ?? [], currentID: viewport.headingID) { item in
            viewport.jump(to: item.id)
            showOutline = false
        }
    }
}

private struct ReaderOutline: View {
    let items: [OutlineItem]
    let currentID: String?
    let select: (OutlineItem) -> Void
    @State private var query = ""

    private var filteredItems: [OutlineItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? items : items.filter { $0.title.localizedStandardContains(search) }
    }
    private var baseLevel: Int { items.map(\.level).min() ?? 1 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredItems) { item in
                        let current = currentID == item.id
                        let depth = min(3, max(0, item.level - baseLevel))
                        Button { select(item) } label: {
                            HStack(spacing: 10) {
                                Capsule()
                                    .fill(current ? Color.accentColor : .clear)
                                    .frame(width: 3, height: 20)
                                Text(item.title)
                                    .font(depth == 0 ? .body.weight(.semibold) : .subheadline)
                                    .fontWeight(current ? .semibold : nil)
                                    .foregroundStyle(current ? Color.accentColor : Color.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.leading, 12 + CGFloat(depth) * 12)
                            .padding(.trailing, 12)
                            .padding(.vertical, 12)
                            .frame(minHeight: 44)
                            .background(current ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, depth == 0 && item.id != filteredItems.first?.id ? 8 : 0)
                        .id(item.id)
                        .accessibilityAddTraits(current ? .isSelected : [])
                        .accessibilityValue("Heading level \(item.level)")
                        .accessibilityIdentifier("outline-" + item.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("No Headings", systemImage: "list.bullet.indent", description: Text("Headings in this document appear here."))
                } else if filteredItems.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .defaultScrollAnchor(.top)
            .onAppear {
                if let currentID { proxy.scrollTo(currentID, anchor: .center) }
            }
        }
        .searchable(text: $query, prompt: "Find a heading")
    }
}

/// A compact panel: one row of type controls above a grid of theme cards.
/// Its content doesn't grow, so the sheet's only detent is the content height.
fileprivate struct AppearanceSettings: View {
    @Binding var presetID: String
    @Binding var pairID: String
    @Binding var fontSize: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private var preset: TypographyPreset {
        TypographyPreset.builtin.first { $0.id == presetID } ?? .default
    }
    private var size: Double { fontSize > 0 ? min(28, max(12, fontSize)) : preset.defaultFontSize }

    var body: some View {
        NavigationStack {
            // Scrolls only when accessibility text sizes outgrow the screen.
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .frame(idealHeight: 330)
        .presentationDetents([.height(330)])
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                sizeControl
                presetMenu
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(DocumentThemePair.builtin) { card($0) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .padding(.top, 8)
    }

    private var sizeControl: some View {
        HStack(spacing: 0) {
            Button {
                fontSize = max(12, size - 1)
            } label: {
                Text("A").font(.footnote.weight(.medium)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(size <= 12).accessibilityLabel("Decrease font size")
            Text("\(Int(size))").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 28).accessibilityIdentifier("reader-font-size")
                .accessibilityLabel("Font size \(Int(size))")
            Button {
                fontSize = min(28, size + 1)
            } label: {
                Text("A").font(.title2.weight(.medium)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(size >= 28).accessibilityLabel("Increase font size")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity).frame(height: 48)
        .background(.fill.tertiary, in: Capsule())
    }

    private var presetMenu: some View {
        Menu {
            Picker("Typography", selection: $presetID) {
                ForEach(TypographyPreset.builtin) { Text($0.name).tag($0.id) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(preset.name).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(.fill.tertiary, in: Capsule())
        }
        .tint(.primary)
        .accessibilityLabel("Typography, \(preset.name)")
    }

    private func card(_ pair: DocumentThemePair) -> some View {
        let theme = colorScheme == .dark ? pair.dark : pair.light
        let selected = pairID == pair.id
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            pairID = pair.id
        } label: {
            VStack(spacing: 2) {
                Text("Aa").font(.title.weight(.semibold))
                Text(pair.name).font(.caption.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(color(theme.document["text"]!))
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(color(theme.document["paper"]!), in: shape)
            .overlay {
                if selected {
                    shape.strokeBorder(.tint, lineWidth: 3)
                } else {
                    shape.strokeBorder(.separator)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pair.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("theme-" + pair.id)
    }

    private func color(_ value: DocumentColor) -> Color {
        Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}
