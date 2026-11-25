import AppKit
import SwiftUI

struct MacNavigator: View {
    private enum Tab: String {
        case recent
        case folder
    }

    private struct FileItem: Identifiable {
        let url: URL
        let modified: Date?
        var id: URL { url }

        init(url: URL) {
            self.url = url
            modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
    }

    let documentURL: URL?
    let open: (URL) -> Void
    @AppStorage("mac.navigator-tab") private var tab: Tab = .recent
    @State private var recent: [FileItem] = []
    @State private var files: [FileItem] = []

    var body: some View {
        let currentURL = documentURL?.standardizedFileURL
        let folder = currentURL?.deletingLastPathComponent()

        VStack(spacing: 8) {
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
                    ForEach(recent) { row($0, currentURL: currentURL, showFolder: true) }
                case .folder:
                    if let folder {
                        Text(folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(folder.path)
                            .accessibilityAddTraits(.isHeader)
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .listRowSeparator(.hidden)
                        if files.isEmpty { emptyRow("No Markdown or text files") }
                        ForEach(files) { row($0, currentURL: currentURL, showFolder: false) }
                    } else {
                        emptyRow("Save this document to browse its folder.")
                    }
                }
            }
            .id(tab)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 24)
        }
        .accessibilityIdentifier("mac-navigator")
        .task(id: folder) {
            let keyChanges = NotificationCenter.default.notifications(named: NSWindow.didBecomeKeyNotification)
                .map { _ in () }
            await refreshRecents()
            for await _ in keyChanges {
                guard !Task.isCancelled else { break }
                await refreshRecents()
            }
        }
        .task(id: folder) {
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
        let files = await Task.detached(priority: .userInitiated) {
            MacFolderListing.files(in: folder).map(FileItem.init(url:))
        }.value
        if !Task.isCancelled { self.files = files }
    }

    private func row(_ item: FileItem, currentURL: URL?, showFolder: Bool) -> some View {
        let url = item.url
        let current = currentURL == url.standardizedFileURL
        return Button {
            open(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13))
                        .truncationMode(.middle)
                    if showFolder || item.modified != nil {
                        metadata(for: item, showFolder: showFolder)
                    }
                }
                .lineLimit(1)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
        .listRowSeparator(.hidden)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(current ? Color.accentColor.opacity(0.20) : .clear)
                .padding(.horizontal, 7)
        )
        .accessibilityAddTraits(current ? .isSelected : [])
        .help(url.path)
    }

    private func metadata(for item: FileItem, showFolder: Bool) -> some View {
        HStack(spacing: 3) {
            if showFolder {
                Text(item.url.deletingLastPathComponent().lastPathComponent)
            }
            if let modified = item.modified {
                if showFolder {
                    Text("·").accessibilityHidden(true)
                }
                Text(.currentDate, format: .reference(to: modified, maxFieldCount: 1))
                    .layoutPriority(1)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func emptyRow(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func refreshRecents() async {
        let urls = Array(NSDocumentController.shared.recentDocumentURLs.prefix(8))
        let items = await Task.detached(priority: .userInitiated) { urls.map(FileItem.init(url:)) }.value
        if !Task.isCancelled { recent = items }
    }
}
