import CryptoKit
import Foundation
import KasumiMarkdown
import Observation

@MainActor @Observable
final class ReaderViewport {
    var headingID: String?
    @ObservationIgnored private var path: String?
    @ObservationIgnored private var identity: String?
    @ObservationIgnored private var latestAnchor: ReadingAnchor?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    func prepare(fileURL: URL?) -> ReadingAnchor? {
        let nextPath = fileURL?.standardizedFileURL.path
        guard nextPath != path else { return latestAnchor }
        flush()
        path = nextPath
        identity = nextPath.map {
            // A path identity follows the in-place URL supplied by DocumentGroup.
            let hash = SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined()
            return "reading-position." + hash
        }
        latestAnchor = nil
        if let identity, let data = UserDefaults.standard.data(forKey: identity) {
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

    /// Drops the saved position, for a document that is being deleted.
    func forget() {
        saveTask?.cancel()
        saveTask = nil
        if let identity { UserDefaults.standard.removeObject(forKey: identity) }
        identity = nil
        path = nil
        latestAnchor = nil
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let identity, let latestAnchor, let data = try? JSONEncoder().encode(latestAnchor) else { return }
        UserDefaults.standard.set(data, forKey: identity)
    }
}
