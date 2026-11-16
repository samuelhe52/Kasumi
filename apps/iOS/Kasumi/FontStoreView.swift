import SwiftUI

/// Groups the faces by the role they compete for, and says which one the
/// reader uses. Each role offers Apple's face and an open alternative.
struct FontStoreView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = FontStore.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(FontChoice.all) { choice in
                    Section(choice.title) {
                        FontPackageRow(package: choice.apple)
                        FontPackageRow(package: choice.open)
                    }
                }
                Section("Supporting Faces") {
                    ForEach(FontChoice.supporting) { FontPackageRow(package: $0) }
                }
            }
            .animation(.smooth, value: store.preferredOpen)
            .scrollEdgeEffectStyle(.soft, for: .top)
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

struct FontPackageRow: View {
    let package: FontPackage
    /// Offers Use on a downloaded face its role doesn't use.
    var allowsChoosing = true
    private let store = FontStore.shared

    private enum Usage: Equatable {
        case inUse
        /// Downloaded, but the named package is used instead.
        case unused(String)
        case standalone
    }

    private var usage: Usage {
        if let choice = FontChoice.containing(package) {
            guard let active = store.active(choice) else { return .standalone }
            return active.id == package.id ? .inUse : .unused(active.name)
        }
        // Supporting faces only pair with Songti SC.
        if let simplified = FontChoice.all.first, let active = store.active(simplified),
            active.id != simplified.apple.id
        {
            return .unused(active.name)
        }
        return .standalone
    }

    var body: some View {
        let state = store.state(package)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(package.name).font(.body)
                if state == .installed, let face = package.postScriptNames.first {
                    Text(package.sample).font(.custom(face, size: 17))
                        .accessibilityHidden(true)
                        .transition(.blurReplace)
                }
                Text(detail(state)).font(.footnote)
                    .foregroundStyle(state.isFailure ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 8)
            control(state)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
        .padding(.vertical, 2)
        // Animates state changes, not every progress tick.
        .animation(.smooth, value: state.phase)
        .animation(.smooth, value: usage)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("font-" + package.id)
        .swipeActions {
            if !package.isApple, state == .installed {
                Button("Remove", role: .destructive) { store.remove(package) }
            }
        }
    }

    private func detail(_ state: FontStore.State) -> String {
        var parts = [package.role]
        if let bytes = package.byteCount, state != .installed {
            parts.append(bytes.formatted(.byteCount(style: .file)))
        }
        if case .failed(let message) = state { parts = [message] }
        if state == .installed, case .unused(let other) = usage {
            parts = ["Downloaded · \(other) is in use"]
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func control(_ state: FontStore.State) -> some View {
        switch state {
        case .installed:
            switch usage {
            case .inUse:
                Text("In Use").font(.footnote.weight(.semibold)).foregroundStyle(.green)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.green.opacity(0.15), in: Capsule())
                    .accessibilityIdentifier("font-in-use-" + package.id)
            case .unused where allowsChoosing && FontChoice.containing(package) != nil:
                Button("Use") { store.use(package) }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .accessibilityIdentifier("font-use-" + package.id)
            case .unused:
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    .accessibilityLabel("Downloaded, not in use")
            case .standalone:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .accessibilityLabel("Installed")
            }
        case .downloading(let fraction):
            Button {
                store.cancel(package)
            } label: {
                ZStack {
                    if fraction > 0 {
                        ProgressView(value: fraction).progressViewStyle(.circular)
                            .animation(.linear(duration: 0.15), value: fraction)
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Downloading, \(Int(fraction * 100)) percent. Cancel")
        case .missing, .failed:
            Button(state.isFailure ? "Retry" : "Get") { store.install(package) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                .accessibilityIdentifier("font-get-" + package.id)
        }
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
