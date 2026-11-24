import SwiftUI

/// Font selection and download management are separate: catalog rows never
/// disappear, and only open-source downloads can be removed.
struct FontStoreView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FontChoice.all) { choice in
                        NavigationLink {
                            FontChoiceScreen(choice: choice)
                        } label: {
                            FontChoiceSummary(choice: choice)
                        }
                        .accessibilityIdentifier("font-role-" + choice.id)
                    }
                }
                Section {
                    NavigationLink("Supporting Fonts") { SupportingFontsScreen() }
                        .accessibilityIdentifier("font-supporting")
                }
            }
            .softTopScrollEdge()
            .navigationTitle("Fonts")
            .navigationBarTitleDisplayMode(.inline)
            // Matches the appearance sheet it opens from.
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct FontChoiceSummary: View {
    let choice: FontChoice
    @ScaledMetric(relativeTo: .body) private var glyphSize = 28
    private let store = FontStore.shared

    var body: some View {
        let active = store.active(choice)
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(choice.title).font(.body)
                Text(active?.name ?? "System fallback")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("霞")
                .font(
                    active.map { .custom($0.postScriptNames[0], fixedSize: glyphSize) }
                        ?? .system(size: glyphSize)
                )
                .frame(width: glyphSize * 1.3, height: glyphSize * 1.5)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }
}

private struct FontChoiceScreen: View {
    let choice: FontChoice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let store = FontStore.shared

    private var sample: String {
        choice.id == "traditional" ? "霞光與晨霧，落筆成章。" : "霞光与晨雾，落笔成章。"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach([choice.apple, choice.open]) { package in
                    let selected = store.active(choice)?.id == package.id
                    FontPackageRow(package: package, sample: sample, contentInset: 16)
                        .background(
                            Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    selected ? Color.accentColor : Color(uiColor: .separator).opacity(0.3),
                                    lineWidth: selected ? 1.5 : 0.5
                                )
                                .animation(
                                    reduceMotion ? nil : .easeInOut(duration: 0.22), value: selected)
                        }
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollBounceBehavior(.basedOnSize)
        .softTopScrollEdge()
        .navigationTitle(choice.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if store.state(choice.open) == .installed {
                        Button("Remove Download", systemImage: "trash", role: .destructive) {
                            store.remove(choice.open)
                        }
                    }
                    if case .open(_, let license, let url) = choice.open.source {
                        Link(destination: url) {
                            Label(license, systemImage: "arrow.up.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Manage \(choice.open.name)")
                .accessibilityIdentifier("font-more-" + choice.open.id)
            }
        }
    }

}

private struct SupportingFontsScreen: View {
    var body: some View {
        List {
            Section {
                ForEach(FontChoice.supporting) { FontPackageRow(package: $0) }
            }
        }
        .softTopScrollEdge()
        .navigationTitle("Supporting Fonts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
