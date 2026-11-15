import CryptoKit
import Foundation
import KasumiMarkdown
import Observation

@MainActor @Observable
final class ReaderViewport {
    var rendered: RenderedDocument?
    var headingID: String?
    var jumpID: String?
    var jumpRevision = UUID()
    @ObservationIgnored private var identity: String?
    @ObservationIgnored private var latestAnchor: ReadingAnchor?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    func prepare(fileURL: URL?) -> ReadingAnchor? {
        let key = fileURL.map { url in
            // A path identity follows the in-place URL supplied by DocumentGroup.
            let path = url.standardizedFileURL.path
            let hash = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
            return "reading-position." + hash
        }
        guard key != identity else { return latestAnchor }
        flush()
        identity = key; latestAnchor = nil
        if let key, let data = UserDefaults.standard.data(forKey: key) {
            latestAnchor = try? JSONDecoder().decode(ReadingAnchor.self, from: data)
        }
        return latestAnchor
    }

    func moved(anchor: ReadingAnchor, heading: String?) {
        latestAnchor = anchor
        if headingID != heading { headingID = heading }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.flush()
        }
    }

    func jump(to id: String) {
        jumpID = id; jumpRevision = UUID()
    }

    /// Drops the saved position, for a document that is being deleted.
    func forget() {
        saveTask?.cancel(); saveTask = nil
        if let identity { UserDefaults.standard.removeObject(forKey: identity) }
        identity = nil; latestAnchor = nil
    }

    func flush() {
        saveTask?.cancel(); saveTask = nil
        guard let identity, let latestAnchor, let data = try? JSONEncoder().encode(latestAnchor) else { return }
        UserDefaults.standard.set(data, forKey: identity)
    }
}
