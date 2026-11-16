import CoreText
import CryptoKit
import Foundation

/// Downloads and activates the faces in `FontPackage.catalog`.
///
/// Core Text registrations last only for the process. Open fonts are kept in
/// Application Support and registered again at launch. iOS keeps Apple's
/// downloaded faces itself, but each launch must ask for them again before the
/// process can use them, so the packages requested once are remembered and
/// re-requested at launch, which completes without network once they're cached.
@MainActor @Observable
final class FontStore {
    static let shared = FontStore()

    enum State: Equatable {
        case missing
        case downloading(Double)
        case installed
        case failed(String)
    }

    private(set) var states: [String: State] = [:]
    /// Increases whenever a face becomes available or goes away, so readers re-render.
    private(set) var revision = 0
    /// Open families the user chose over the Apple faces they replace.
    private(set) var preferredOpen: Set<String>
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let requestedKey = "fonts.apple-requested"
    private static let preferredKey = "fonts.preferred-open"

    private init() {
        preferredOpen = Set(UserDefaults.standard.stringArray(forKey: Self.preferredKey) ?? [])
        for package in FontPackage.open {
            if case .open(let files, _, _) = package.source {
                for file in files where FileManager.default.fileExists(atPath: OpenFontFiles.url(for: file).path) {
                    OpenFontFiles.register(OpenFontFiles.url(for: file))
                }
            }
        }
        let requested = Set(defaults.stringArray(forKey: Self.requestedKey) ?? [])
        for package in FontPackage.catalog {
            states[package.id] = Self.isAvailable(package) ? .installed : .missing
            if package.isApple, requested.contains(package.id), states[package.id] != .installed {
                install(package, quietly: true)
            }
        }
    }

    func state(_ package: FontPackage) -> State { states[package.id] ?? .missing }

    /// The package the renderer uses for a choice: the open one when the user
    /// chose it or Apple's isn't available, otherwise Apple's. Nil when neither
    /// is installed and text falls back to PingFang.
    func active(_ choice: FontChoice) -> FontPackage? {
        let apple = state(choice.apple) == .installed
        let open = state(choice.open) == .installed
        if open, preferredOpen.contains(choice.openFamily) || !apple { return choice.open }
        return apple ? choice.apple : nil
    }

    /// Makes `package` the face used for its choice.
    func use(_ package: FontPackage) {
        guard state(package) == .installed, let choice = FontChoice.containing(package),
            active(choice)?.id != package.id
        else { return }
        if package.id == choice.open.id {
            preferredOpen.insert(choice.openFamily)
        } else {
            preferredOpen.remove(choice.openFamily)
        }
        defaults.set(preferredOpen.sorted(), forKey: Self.preferredKey)
        revision += 1
    }


    func install(_ package: FontPackage) {
        install(package, quietly: false)
    }

    private func install(_ package: FontPackage, quietly: Bool) {
        guard tasks[package.id] == nil, state(package) != .installed else { return }
        states[package.id] = .downloading(0)
        if package.isApple {
            var requested = Set(defaults.stringArray(forKey: Self.requestedKey) ?? [])
            requested.insert(package.id)
            defaults.set(requested.sorted(), forKey: Self.requestedKey)
        }
        let id = package.id
        let progress: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor in
                guard let self, case .downloading = self.states[id] else { return }
                self.states[id] = .downloading(min(1, max(0, value)))
            }
        }
        tasks[id] = Task {
            defer { tasks[id] = nil }
            do {
                switch package.source {
                case .apple(let names):
                    if Self.failsAppleFonts { throw FontStoreError.notStarted }
                    try await AppleFontDownload.run(names, progress: progress)
                case .open(let files, _, _): try await OpenFontFiles.install(files, progress: progress)
                }
                guard Self.isAvailable(package) else { throw FontStoreError.unavailable(package.name) }
                states[id] = .installed
                revision += 1
            } catch is CancellationError {
                states[id] = .missing
            } catch {
                NSLog("Font download failed %@: %@", id, String(describing: error))
                states[id] = .failed(Self.message(for: error, quietly: quietly))
            }
        }
    }

    func cancel(_ package: FontPackage) { tasks[package.id]?.cancel() }

    /// Removes an open package's files. Apple's faces are managed by iOS.
    func remove(_ package: FontPackage) {
        guard case .open(let files, _, _) = package.source else { return }
        cancel(package)
        for file in files { OpenFontFiles.remove(OpenFontFiles.url(for: file)) }
        states[package.id] = .missing
        revision += 1
    }

    #if DEBUG
        /// `-KasumiFailAppleFonts YES` treats Apple's faces as missing and fails
        /// their download, to exercise the open fallbacks once iOS has cached them.
        static let failsAppleFonts = UserDefaults.standard.bool(forKey: "KasumiFailAppleFonts")
    #else
        static let failsAppleFonts = false
    #endif

    private static func isAvailable(_ package: FontPackage) -> Bool {
        if failsAppleFonts, package.isApple { return false }
        return package.postScriptNames.allSatisfy { name in
            CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 16, nil)) as String == name
        }
    }

    private static func message(for error: Error, quietly: Bool) -> String {
        if quietly { return "Couldn't restore this font. Download it again." }
        if let error = error as? FontStoreError { return error.description }
        if let error = error as? URLError, error.code == .notConnectedToInternet { return "You're offline." }
        return "The download didn't finish."
    }
}

enum FontStoreError: Error, CustomStringConvertible {
    case notStarted
    case unavailable(String)
    case badResponse(Int)
    case mismatch(String)

    var description: String {
        switch self {
        case .notStarted: "iOS didn't start the download."
        case .unavailable(let name): "iOS didn't make \(name) available."
        case .badResponse(let status): "The server answered \(status)."
        case .mismatch(let file): "\(file) didn't match the expected file."
        }
    }
}

/// Core Text's on-demand system font download.
fileprivate enum AppleFontDownload {
    /// Collects the matcher's callbacks, which arrive on a Core Text queue.
    private final class Matching: @unchecked Sendable {
        private let lock = NSLock()
        private var error: Error?
        private var continuation: CheckedContinuation<Void, Error>?
        private var cancelled = false

        init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }

        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
        func fail(_ error: Error) { lock.withLock { self.error = self.error ?? error } }
        func finish() {
            let (continuation, error, cancelled) = lock.withLock {
                defer { self.continuation = nil }
                return (self.continuation, self.error, self.cancelled)
            }
            if cancelled {
                continuation?.resume(throwing: CancellationError())
            } else if let error {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume()
            }
        }
    }

    static func run(_ postScriptNames: [String], progress: @escaping @Sendable (Double) -> Void) async throws {
        let descriptors =
            postScriptNames.map {
                CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: $0] as CFDictionary)
            } as CFArray
        let box = LockedBox<Matching>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let matching = Matching(continuation)
                box.value = matching
                let started = CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descriptors, nil) {
                    state, parameters in
                    let parameters = parameters as NSDictionary
                    switch state {
                    case .downloading:
                        if let percent = parameters[kCTFontDescriptorMatchingPercentage] as? Double {
                            progress(percent / 100)
                        }
                    case .didFailWithError:
                        matching.fail(
                            parameters[kCTFontDescriptorMatchingError] as? NSError ?? FontStoreError.notStarted)
                    case .didFinish:
                        matching.finish()
                    default: break
                    }
                    return !matching.isCancelled
                }
                if !started {
                    matching.fail(FontStoreError.notStarted)
                    matching.finish()
                }
            }
        } onCancel: {
            box.value?.cancel()
        }
    }
}

fileprivate final class LockedBox<Value: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?
    var value: Value? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Openly licensed font files in Application Support, registered for the process.
enum OpenFontFiles {
    static let directory: URL = {
        var url = URL.applicationSupportDirectory.appending(path: "Fonts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // The files can be downloaded again, so they stay out of backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    static func url(for file: FontPackage.OpenFile) -> URL { directory.appending(path: file.fileName) }

    static func register(_ url: URL) {
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error), let error = error?.takeRetainedValue(),
            CFErrorGetCode(error) != CTFontManagerError.alreadyRegistered.rawValue
        {
            NSLog("Font registration failed %@: %@", url.lastPathComponent, String(describing: error))
        }
    }

    static func remove(_ url: URL) {
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: url)
    }

    /// Downloads every missing file, then registers them. Progress is by bytes
    /// across the whole package.
    static func install(_ files: [FontPackage.OpenFile], progress: @escaping @Sendable (Double) -> Void)
        async throws
    {
        let total = Double(files.reduce(0) { $0 + $1.byteCount })
        var done = 0.0
        for file in files {
            let destination = url(for: file)
            if !FileManager.default.fileExists(atPath: destination.path) {
                let base = done
                try await download(file, to: destination) { fraction in
                    progress((base + fraction * Double(file.byteCount)) / total)
                }
            }
            done += Double(file.byteCount)
            register(destination)
        }
    }

    private final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Result<Void, Error>?
        var result: Result<Void, Error>? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private static func download(
        _ file: FontPackage.OpenFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let completion = Completion()
        let task = URLSession.shared.downloadTask(with: file.url) { temporary, response, error in
            // The temporary file is deleted when this handler returns.
            completion.result = Result {
                if let error { throw error }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, let temporary else { throw FontStoreError.badResponse(status) }
                try verify(temporary, as: file)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        }
        task.resume()
        try await withTaskCancellationHandler {
            while true {
                if let result = completion.result {
                    if Task.isCancelled { throw CancellationError() }
                    return try result.get()
                }
                progress(task.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(150))
            }
        } onCancel: {
            task.cancel()
        }
    }

    private static func verify(_ url: URL, as file: FontPackage.OpenFile) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard Int64(data.count) == file.byteCount, digest == file.sha256,
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            descriptors.contains(where: {
                CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == file.postScriptName
            })
        else { throw FontStoreError.mismatch(file.fileName) }
    }
}
