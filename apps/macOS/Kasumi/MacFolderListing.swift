import Foundation

enum MacFolderListing {
    private static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt", "text"]

    static func supports(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func files(in folder: URL) -> [URL] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
        return urls.filter { url in
            supports(url) && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        .sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
