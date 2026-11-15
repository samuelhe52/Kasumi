import Foundation

/// Hand-off folder between the "Import into Kasumi" action extension and the
/// app. The extension can't write to the app's Documents, so it drops files in
/// the shared App Group container, and the app moves them out when it becomes
/// active. Both targets compile this file.
enum ImportInbox {
    static let groupIdentifier = "group.com.samuelhe.Kasumi"
    /// Opening this URL brings Kasumi forward; the app imports on activation.
    static let openURL = URL(string: "kasumi://import")!
    /// Same ceiling as Open URL.
    static let sizeLimit = 5 * 1024 * 1024

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// `nil` when the App Group isn't provisioned for this build.
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appending(path: "Inbox", directoryHint: .isDirectory)
    }

    /// Copies `file` into its own inbox folder, so two imports with the same
    /// name can't collide before the app gives them user-visible names.
    static func deposit(_ file: URL, named name: String) throws {
        guard let inbox = directory else {
            throw Failure(message: "Kasumi's shared storage isn't available.")
        }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= sizeLimit else { throw Failure(message: "The document exceeds the 5 MB limit.") }
        let folder = inbox.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: file, to: folder.appending(path: name))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Takes every pending file, oldest first, and removes it from the inbox.
    /// `body` runs once per file; a file stays in the inbox if it throws.
    static func drain(_ body: (_ data: Data, _ name: String) throws -> Void) {
        guard let inbox = directory,
            let folders = try? FileManager.default.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: [.creationDateKey])
        else { return }
        let ordered = folders.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        for folder in ordered {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            if let file = files.first, let data = try? Data(contentsOf: file) {
                do { try body(data, file.lastPathComponent) } catch { continue }
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
