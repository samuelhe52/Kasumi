import AppKit
import SwiftUI

struct MacNavigator: View {
    private enum Tab: String {
        case recent
        case folder
    }

    let documentURL: URL?
    let open: (URL) -> Void
    @AppStorage("mac.navigator-tab") private var tab: Tab = .recent
    @State private var recent: [URL] = []
    @State private var files: [URL] = []

    var body: some View {
        let currentURL = documentURL?.standardizedFileURL
        let folder = currentURL?.deletingLastPathComponent()

        VStack(spacing: 4) {
            Picker("Navigator", selection: $tab) {
                Text("Recent").tag(Tab.recent)
                Text("Workspace").tag(Tab.folder)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.top, 6)

            List {
                switch tab {
                case .recent:
                    if recent.isEmpty { emptyRow("No recent files") }
                    ForEach(recent, id: \.self) { row($0, currentURL: currentURL) }
                case .folder:
                    if let folder {
                        Section {
                            if files.isEmpty { emptyRow("No Markdown or text files") }
                            ForEach(files, id: \.self) { row($0, currentURL: currentURL) }
                        } header: {
                            Text(folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent)
                                .lineLimit(1)
                                .help(folder.path)
                        }
                    } else {
                        emptyRow("Save this document to browse its folder.")
                    }
                }
            }
            .id(tab)
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 22)
            .softTopScrollEdge()
        }
        .accessibilityIdentifier("mac-navigator")
        .navigationSplitViewColumnWidth(min: 165, ideal: 200, max: 330)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshRecents()
        }
        .task(id: folder) {
            refreshRecents()
            files = []
            guard let folder else { return }
            let changes = MacFileEvents.changes(at: folder)
            await scan(folder)
            for await _ in changes {
                guard !Task.isCancelled else { break }
                await scan(folder)
            }
        }
    }

    private func scan(_ folder: URL) async {
        let files = await Task.detached(priority: .userInitiated) { MacFolderListing.files(in: folder) }.value
        if !Task.isCancelled { self.files = files }
    }

    private func row(_ url: URL, currentURL: URL?) -> some View {
        let current = currentURL == url.standardizedFileURL
        return Button {
            open(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        .listRowBackground(current ? Color.accentColor.opacity(0.12) : Color.clear)
        .accessibilityAddTraits(current ? .isSelected : [])
        .help(url.path)
    }

    private func emptyRow(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func refreshRecents() {
        recent = Array(NSDocumentController.shared.recentDocumentURLs.prefix(8))
    }
}
