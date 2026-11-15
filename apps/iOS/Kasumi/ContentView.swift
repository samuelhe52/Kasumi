import KasumiMarkdown
import SwiftUI

struct ReaderScreen: View {
    let document: ReaderDocument
    var canClose = false
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
                NavigationStack { reader }
            }
        }
        .background(paper.ignoresSafeArea())
        .sheet(isPresented: $showOutline) {
            NavigationStack {
                outline
                    .navigationTitle("Outline")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden()
                    .toolbarBackground(paper, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showOutline = false } } }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(paper)
        }
        .sheet(isPresented: Binding(get: { showAppearance && !regular }, set: { showAppearance = $0 })) {
            AppearanceSettings(presetID: $presetID, pairID: $pairID, fontSize: $fontSize)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: presetID) { _, _ in fontSize = 0 }
        .onChange(of: scenePhase) { _, phase in if phase != .active { viewport.flush() } }
        .onDisappear { viewport.flush() }
    }

    private var reader: some View {
        Group {
            if document.needsURL {
                URLImportView(document: document)
            } else if let snapshot = document.snapshot, let parsed = snapshot.parsed {
                ReadingSurface(document: parsed, revision: snapshot.revision, style: style,
                    outline: parsed.outline, fileURL: document.fileURL, viewport: viewport,
                    openLink: { url in openURL(url) })
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
        .toolbarBackground(paper, for: .navigationBar)
        .toolbarVisibility(viewport.barsHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if canClose {
                ToolbarItem(placement: .topBarLeading) { Button("Close", systemImage: "xmark") { viewport.flush(); dismiss() } }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Outline", systemImage: "list.bullet.indent") {
                    viewport.barsHidden = false
                    if regular { withAnimation { columns = columns == .detailOnly ? .all : .detailOnly } }
                    else { showOutline = true }
                }
                .accessibilityIdentifier("reader-outline")
                Button("Appearance", systemImage: "textformat.size") { showAppearance = true; viewport.barsHidden = false }
                    .accessibilityIdentifier("reader-appearance")
                    .popover(isPresented: Binding(get: { showAppearance && regular }, set: { showAppearance = $0 })) {
                        AppearanceSettings(presetID: $presetID, pairID: $pairID, fontSize: $fontSize)
                            .frame(width: 360, height: 560)
                    }
            }
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
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a heading")
    }
}

private struct AppearanceSettings: View {
    @Binding var presetID: String
    @Binding var pairID: String
    @Binding var fontSize: Double
    @Environment(\.dismiss) private var dismiss
    private var preset: TypographyPreset { TypographyPreset.builtin.first { $0.id == presetID } ?? .default }
    private var size: Double { fontSize > 0 ? min(28, max(12, fontSize)) : preset.defaultFontSize }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Preset", selection: $presetID) {
                        ForEach(TypographyPreset.builtin) { Text($0.name).tag($0.id) }
                    }.pickerStyle(.menu)
                    LabeledContent("Size") {
                        HStack(spacing: 4) {
                            Button { fontSize = max(12, size - 1) } label: {
                                Image(systemName: "textformat.size.smaller").frame(width: 40, height: 32)
                            }
                            .disabled(size <= 12).accessibilityLabel("Decrease font size")
                            Text("\(Int(size))").monospacedDigit().frame(minWidth: 28)
                                .accessibilityIdentifier("reader-font-size")
                            Button { fontSize = min(28, size + 1) } label: {
                                Image(systemName: "textformat.size.larger").frame(width: 40, height: 32)
                            }
                            .disabled(size >= 28).accessibilityLabel("Increase font size")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section("Theme") {
                    ForEach(DocumentThemePair.builtin) { pair in
                        Button { pairID = pair.id } label: {
                            HStack {
                                swatch(pair.light)
                                swatch(pair.dark)
                                Text(pair.name).foregroundStyle(.primary).padding(.leading, 4)
                                Spacer()
                                if pairID == pair.id { Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold) }
                            }
                        }
                        .accessibilityLabel(pair.name)
                        .accessibilityIdentifier("theme-" + pair.id)
                    }
                }
            }
            .navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func swatch(_ theme: DocumentTheme) -> some View {
        let paper = theme.document["paper"]!, text = theme.document["text"]!
        return Text("Aa").font(.caption.weight(.medium))
            .foregroundStyle(Color(.sRGB, red: text.red, green: text.green, blue: text.blue, opacity: text.alpha))
            .frame(width: 30, height: 27)
            .background(Color(.sRGB, red: paper.red, green: paper.green, blue: paper.blue, opacity: paper.alpha), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.3)))
            .accessibilityHidden(true)
    }
}
