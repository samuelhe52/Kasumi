import KasumiMarkdown
import SwiftUI

/// The document's headings, with the current one highlighted and a tap to jump.
struct ReaderOutline: View {
    let items: [OutlineItem]
    let currentID: String?
    /// `.searchable` renders nothing in the iPad inspector, so the outline
    /// there has no search.
    let searchable: Bool
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
                        Button {
                            select(item)
                        } label: {
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
                            .background(
                                current ? Color.accentColor.opacity(0.1) : .clear,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
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
                    ContentUnavailableView(
                        "No Headings", systemImage: "list.bullet.indent",
                        description: Text("Headings in this document appear here."))
                } else if filteredItems.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .defaultScrollAnchor(.top)
            .onAppear {
                if let currentID { proxy.scrollTo(currentID, anchor: .center) }
            }
        }
        .modifier(OutlineSearch(query: $query, enabled: searchable))
    }
}

fileprivate struct OutlineSearch: ViewModifier {
    @Binding var query: String
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.searchable(text: $query, prompt: "Find a heading") } else { content }
    }
}
