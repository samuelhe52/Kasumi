import SwiftUI

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
