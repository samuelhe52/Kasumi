import AppKit
import Foundation

enum MacFileEvents {
    static func changes(at url: URL) -> AsyncStream<Void> {
        // One pending event covers any number of changes since the last look.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let descriptor = open(url.path, O_EVTONLY | O_CLOEXEC)
            guard descriptor >= 0 else {
                continuation.finish()
                return
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
                queue: .main)
            source.setEventHandler { continuation.yield(()) }
            source.setCancelHandler { close(descriptor) }
            continuation.onTermination = { _ in source.cancel() }
            source.resume()
        }
    }
}

/// AppKit tracks document coordination and conflicts. A file writer that never
/// coordinates can leave the visible document stale, so also watch the
/// file and request a native revert once its on-disk content changes.
@MainActor
final class MacExternalFileMonitor {
    private let url: URL
    private weak var document: MacDocument?
    private var fileTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    init(url: URL, document: MacDocument) {
        self.url = url
        self.document = document
    }

    func watch() async {
        let folder = url.resolvingSymlinksInPath().deletingLastPathComponent()
        let folderChanges = MacFileEvents.changes(at: folder)
        watchFile()
        defer {
            fileTask?.cancel()
            reloadTask?.cancel()
        }
        // The file can change between being read and being watched.
        scheduleReload()
        for await _ in folderChanges {
            guard !Task.isCancelled else { break }
            // An atomic save installs a different inode at the same URL.
            watchFile()
            scheduleReload()
        }
        // A folder that cannot be opened ends its stream at once. In-place
        // writes are still visible through the file itself.
        if !Task.isCancelled, let fileTask {
            await withTaskCancellationHandler {
                await fileTask.value
            } onCancel: {
                fileTask.cancel()
            }
        }
    }

    private func watchFile() {
        fileTask?.cancel()
        let changes = MacFileEvents.changes(at: url)
        fileTask = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { break }
                self?.scheduleReload()
            }
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.document?.refreshEditability()
                guard let snapshot = reloadSnapshot() else { return }
                let url = self.url
                let changed = await Task.detached(priority: .utility) {
                    guard let data = try? Data(contentsOf: url), let expected = try? snapshot.data() else {
                        return false
                    }
                    return data != expected
                }.value
                guard !Task.isCancelled, changed, reloadSnapshot()?.text.utf8.elementsEqual(snapshot.text.utf8) == true,
                    let document, let type = document.fileType
                else { return }
                try document.revert(toContentsOf: url, ofType: type)
            } catch is CancellationError {
                return
            } catch {
                if let self {
                    NSLog("Kasumi could not reload %@: %@", self.url.lastPathComponent, error.localizedDescription)
                }
            }
        }
    }

    private func reloadSnapshot() -> ReaderDocument.WriteSnapshot? {
        guard let document, document.fileURL == url, !document.isDocumentEdited, !document.hasUnautosavedChanges else {
            return nil
        }
        return document.session?.document.writeSnapshot()
    }
}
