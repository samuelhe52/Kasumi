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
    private var baseLevel: Int { items.lazy.map(\.level).min() ?? 1 }

    #if os(macOS)
        private let rowSpacing: CGFloat = 2
        private let margin: CGFloat = 10
        private let verticalMargin: CGFloat = 6
    #else
        private let rowSpacing: CGFloat = 4
        private let verticalMargin: CGFloat = 12
        private let rowHeight: CGFloat = 44
        private let rowPadding: CGFloat = 12
        private let accentHeight: CGFloat = 20
        private let rowRadius: CGFloat = 12
        private let margin: CGFloat = 16
    #endif

    var body: some View {
        let visibleItems = filteredItems
        let baseLevel = self.baseLevel
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: rowSpacing) {
                    ForEach(visibleItems) { item in
                        let current = currentID == item.id
                        let depth = min(3, max(0, item.level - baseLevel))
                        Button {
                            select(item)
                        } label: {
                            #if os(macOS)
                                Text(item.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, CGFloat(depth) * 10)
                                    .frame(minHeight: 22)
                                    .contentShape(Rectangle())
                            #else
                                HStack(spacing: 10) {
                                    Capsule()
                                        .fill(current ? Color.accentColor : .clear)
                                        .frame(width: 3, height: accentHeight)
                                    Text(item.title)
                                        .font(depth == 0 ? .body.weight(.semibold) : .subheadline)
                                        .fontWeight(current ? .semibold : nil)
                                        .foregroundStyle(current ? Color.accentColor : Color.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.leading, 12 + CGFloat(depth) * 12)
                                .padding(.trailing, 12)
                                .padding(.vertical, rowPadding)
                                .frame(minHeight: rowHeight)
                                .background(
                                    current ? Color.accentColor.opacity(0.1) : .clear,
                                    in: RoundedRectangle(cornerRadius: rowRadius)
                                )
                                .contentShape(Rectangle())
                            #endif
                        }
                        .buttonStyle(.plain)
                        #if os(macOS)
                            .help(item.title)
                        #else
                            .padding(.top, depth == 0 && item.id != visibleItems.first?.id ? 8 : 0)
                        #endif
                        .id(item.id)
                        .accessibilityAddTraits(current ? .isSelected : [])
                        .accessibilityValue("Heading level \(item.level)")
                        .accessibilityIdentifier("outline-" + item.id)
                    }
                }
                .padding(.horizontal, margin)
                .padding(.vertical, verticalMargin)
            }
            .softTopScrollEdge()
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
            #if os(macOS)
                .onChange(of: currentID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            #endif
        }
        #if os(macOS)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("Outline")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, margin)
                    .padding(.vertical, 8)
                    .accessibilityAddTraits(.isHeader)
            }
        #endif
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
