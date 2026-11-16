import KasumiMarkdown
import Observation
import SwiftUI

@MainActor @Observable
final class ReaderFindState {
    var isPresented = false
    var barHeight: CGFloat = 0
    var query = "" { didSet { if query != oldValue { rebuild(resetIndex: true) } } }
    private(set) var matches: [TextRange] = []
    private(set) var currentIndex = 0
    private(set) var navigationRevision = 0
    @ObservationIgnored private var rendered: RenderedDocument?

    var currentRange: TextRange? { matches.indices.contains(currentIndex) ? matches[currentIndex] : nil }

    func install(_ rendered: RenderedDocument) {
        guard self.rendered !== rendered else { return }
        self.rendered = rendered
        rebuild(resetIndex: false)
    }
    func move(by delta: Int) {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + delta % matches.count + matches.count) % matches.count
        navigationRevision += 1
    }
    private func rebuild(resetIndex: Bool) {
        matches = rendered?.ranges(matching: query) ?? []
        currentIndex = resetIndex ? 0 : min(currentIndex, max(0, matches.count - 1))
        navigationRevision += 1
    }
}

struct ReaderFindBar: View {
    @Bindable var find: ReaderFindState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find in Document", text: $find.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit { find.move(by: 1) }
                    .accessibilityIdentifier("reader-find-query")
                if !find.query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { find.query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("reader-find-clear")
                }
                Button("Done") { find.isPresented = false }
                    .accessibilityIdentifier("reader-find-done")
            }
            HStack {
                Text(find.query.isEmpty ? "Enter text to find" :
                    (find.matches.isEmpty ? "No matches" : "\(find.currentIndex + 1) of \(find.matches.count)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader-find-count")
                    .accessibilityLabel("Find results")
                    .accessibilityValue(find.query.isEmpty ? "Enter text to find" :
                        (find.matches.isEmpty ? "No matches" : "\(find.currentIndex + 1) of \(find.matches.count)"))
                Spacer()
                Button("Previous Match", systemImage: "chevron.up") { find.move(by: -1) }
                    .frame(minWidth: 44, minHeight: 32)
                    .accessibilityIdentifier("reader-find-previous")
                Button("Next Match", systemImage: "chevron.down") { find.move(by: 1) }
                    .frame(minWidth: 44, minHeight: 32)
                    .accessibilityIdentifier("reader-find-next")
            }
            .labelStyle(.iconOnly)
            .disabled(find.matches.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { find.barHeight = $0 }
        .onAppear { focused = true }
        .onKeyPress(keys: ["g"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            find.move(by: press.modifiers.contains(.shift) ? -1 : 1)
            return .handled
        }
        .onKeyPress(.escape) { find.isPresented = false; return .handled }
    }
}
