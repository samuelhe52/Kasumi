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

struct FontPackageRow: View {
    let package: FontPackage
    var sample: String? = nil
    var contentInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var specimenSize = 24
    private let store = FontStore.shared

    private var selected: Bool {
        guard let choice = FontChoice.containing(package) else { return false }
        return store.active(choice)?.id == package.id
    }

    private var selectable: Bool { FontChoice.containing(package) != nil }
    private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.22) }

    var body: some View {
        let state = store.state(package)
        let installed = state == .installed
        let usage = FontChoice.containing(package)?.apple.role ?? package.role
        let label: String
        let identifier: String
        switch state {
        case .installed:
            label =
                selectable
                ? (selected ? "\(package.name), selected" : "Use \(package.name)")
                : "\(package.name), downloaded"
            identifier = selected ? "font-in-use-" : "font-use-"
        case .downloading(let value):
            label = "Cancel \(package.name) download, \(Int(value * 100)) percent"
            identifier = "font-cancel-"
        case .missing:
            label = "Download \(package.name)"
            identifier = "font-get-"
        case .failed(let message):
            label = "Retry downloading \(package.name). \(message)"
            identifier = "font-get-"
        }
        return Button {
            switch state {
            case .installed:
                if selectable { withAnimation(animation) { store.use(package) } }
            case .downloading: store.cancel(package)
            case .missing, .failed: store.install(package)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(package.name).font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(source).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    indicator(state).frame(width: 28, height: 28)
                }
                Text(usage).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ZStack(alignment: .leading) {
                    Text(sample ?? package.sample)
                        .font(.system(size: specimenSize, design: .serif))
                        .foregroundStyle(.tertiary)
                        .opacity(installed ? 0 : 1)
                    Text(sample ?? package.sample)
                        .font(
                            installed
                                ? .custom(package.postScriptNames[0], fixedSize: specimenSize)
                                : .system(size: specimenSize, design: .serif)
                        )
                        .foregroundStyle(.primary)
                        .opacity(installed ? 1 : 0)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: specimenSize * 1.6, alignment: .leading)
                .animation(animation, value: installed)
                if case .failed(let message) = state {
                    Text(message).font(.footnote).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(contentInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!installed || selectable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(usage)
        .accessibilityAddTraits(!installed || selectable ? .isButton : [])
        .accessibilityAddTraits(selected && selectable ? .isSelected : [])
        .accessibilityRemoveTraits(installed && !selectable ? .isButton : [])
        .accessibilityIdentifier(identifier + package.id)
    }

    private var source: String {
        if package.isApple { return "Apple" }
        let size = package.byteCount.map { $0.formatted(.byteCount(style: .file)) }
        return ["Open source", size].compactMap { $0 }.joined(separator: " · ")
    }

    private func indicator(_ state: FontStore.State) -> some View {
        let installed = state == .installed
        let downloading = if case .downloading = state { true } else { false }
        return ZStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                .opacity(installed && selected && selectable ? 1 : 0)
            Image(systemName: "circle").foregroundStyle(.tertiary)
                .opacity(installed && !selected && selectable ? 1 : 0)
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                .opacity(installed && !selectable ? 1 : 0)
            Image(systemName: "arrow.down.circle").foregroundStyle(Color.accentColor)
                .opacity(state == .missing ? 1 : 0)
            Image(systemName: "arrow.clockwise.circle").foregroundStyle(Color.accentColor)
                .opacity(state.isFailure ? 1 : 0)
            ZStack {
                if downloading { ProgressView() }
            }
            .opacity(downloading ? 1 : 0)
        }
        .font(.system(size: 22))
        .animation(animation, value: selected)
        .animation(animation, value: state.phase)
    }
}

extension FontStore.State {
    var isFailure: Bool { if case .failed = self { true } else { false } }

    /// The state without download progress.
    var phase: Int {
        switch self {
        case .missing: 0
        case .downloading: 1
        case .installed: 2
        case .failed: 3
        }
    }
}
