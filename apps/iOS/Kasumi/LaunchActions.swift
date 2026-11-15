import Foundation
import Observation
import SwiftUI
import UIKit

/// Pasted, fetched, and shared documents are saved as ordinary files, one folder
/// per kind, and open through the system document browser like any other file.
enum ImportFolder: String, CaseIterable {
    case pasted = "Pasted"
    case downloaded = "Downloaded"
    case imported = "Imported"

    var url: URL { URL.documentsDirectory.appending(path: rawValue, directoryHint: .isDirectory) }

    /// Whether `file` sits directly in one of the import folders.
    static func contains(_ file: URL) -> Bool {
        let parent = file.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return ImportFolder.allCases.contains {
            $0.url.resolvingSymlinksInPath().standardizedFileURL.pathComponents == parent
        }
    }

    /// Writes `data` under `name`, adding " 2", " 3", … rather than replacing a file.
    func save(_ data: Data, as name: String) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var target = url.appending(path: name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            target = url.appending(path: "\(stem) \(suffix).\(ext)")
            suffix += 1
        }
        try data.write(to: target, options: .withoutOverwriting)
        return target
    }

    static func pastedName(at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Pasted Text \(formatter.string(from: date)).md"
    }

    static func downloadName(for url: URL) -> String {
        var name = url.lastPathComponent
        if name.isEmpty || name == "/" { name = url.host() ?? "Download" }
        return markdownName(name)
    }

    /// Adds `.md` unless `name` already ends in a Markdown or text extension.
    static func markdownName(_ name: String) -> String {
        ["md", "markdown", "txt"].contains((name as NSString).pathExtension.lowercased()) ? name : name + ".md"
    }
}

struct LaunchAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor @Observable
final class LaunchStore {
    var showURLImport = false
    var alert: LaunchAlert?
    @ObservationIgnored weak var window: UIWindow?
    @ObservationIgnored private var pendingOpen: URL?

    /// Copies Welcome.md into the app's Documents folder once, so the browser
    /// opens on a real document. Deleting it later is respected.
    static func installWelcomeIfNeeded() {
        let key = "launch.welcome-installed"
        guard !UserDefaults.standard.bool(forKey: key),
            let source = Bundle.main.url(forResource: "Welcome", withExtension: "md")
        else { return }
        let target = URL.documentsDirectory.appending(path: "Welcome.md")
        if !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            guard (try? FileManager.default.copyItem(at: source, to: target)) != nil else { return }
        }
        UserDefaults.standard.set(true, forKey: key)
    }
    /// Reads the clipboard on tap. Under Paste from Other Apps > Ask, this read
    /// is what makes iOS show its consent prompt; Deny leaves `string` nil.
    func pasteFromClipboard() {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else {
            return pasteFailed(String(localized: "The clipboard contains no text to paste."))
        }
        guard let text = pasteboard.string else {
            return pasteFailed(
                String(
                    localized:
                        "Kasumi can't read the clipboard. Allow it in Settings > Apps > Kasumi > Paste from Other Apps."
                ))
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return pasteFailed(String(localized: "The clipboard contains no text to paste."))
        }
        do {
            let url = try ImportFolder.pasted.save(Data(text.utf8), as: ImportFolder.pastedName())
            open(url)
        } catch {
            pasteFailed(error.localizedDescription)
        }
    }
    func remote() { showURLImport = true }

    /// Saves a fetched document and opens it once the URL sheet has gone.
    func saveDownload(_ data: Data, from url: URL) throws {
        pendingOpen = try ImportFolder.downloaded.save(data, as: ImportFolder.downloadName(for: url))
        showURLImport = false
    }
    func urlImportDismissed() {
        guard let url = pendingOpen else { return }
        pendingOpen = nil
        open(url)
    }

    private func pasteFailed(_ message: String) {
        alert = LaunchAlert(title: String(localized: "Could Not Paste"), message: message)
    }

    /// Moves files shared through the "Import into Kasumi" action out of the
    /// App Group inbox into Documents/Imported and opens the newest one. Runs
    /// whenever the app becomes active, since the extension can't launch it.
    func importSharedFiles() async {
        var saved: [URL] = []
        ImportInbox.drain { data, name in
            saved.append(try ImportFolder.imported.save(data, as: ImportFolder.markdownName(name)))
        }
        guard let newest = saved.last else { return }
        await waitForBrowser()
        open(newest)
    }

    /// The browser installs itself after the launch overlay appears.
    private func waitForBrowser() async {
        for _ in 0..<50 where window.flatMap(Self.browser(in:)) == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Hands a file to this window's document browser, so `DocumentGroup` opens
    /// it with the same file session and presentation as a file the user picked.
    private func open(_ url: URL) {
        guard let browser = window.flatMap(Self.browser(in:)) else {
            alert = LaunchAlert(title: String(localized: "Could Not Open Document"), message: url.lastPathComponent)
            return
        }
        // Saved files are already in the browser's Documents location. Reveal
        // would import a copy, and fails (DocumentManager error 1) without import.
        browser.delegate?.documentBrowser?(browser, didPickDocumentsAt: [url])
    }

    private static func browser(in window: UIWindow) -> UIDocumentBrowserViewController? {
        for candidate in window.windowScene?.windows ?? [window] {
            if let root = candidate.rootViewController, let browser = browser(in: root) { return browser }
        }
        return nil
    }
    private static func browser(in controller: UIViewController) -> UIDocumentBrowserViewController? {
        if let browser = controller as? UIDocumentBrowserViewController { return browser }
        if let presented = controller.presentedViewController, let browser = browser(in: presented) { return browser }
        for child in controller.children {
            if let browser = browser(in: child) { return browser }
        }
        return nil
    }

    #if DEBUG
        /// Debug convenience: `-KasumiOpen <path>` copies that file into
        /// Documents/Debug and opens it on launch. Works from `simctl launch` and
        /// Xcode scheme arguments, since launch arguments land in UserDefaults.
        func openDebugDocumentIfRequested() async {
            guard let path = UserDefaults.standard.string(forKey: "KasumiOpen"), !path.isEmpty else { return }
            let source = URL(fileURLWithPath: path)
            let folder = URL.documentsDirectory.appending(path: "Debug", directoryHint: .isDirectory)
            let target = folder.appending(path: source.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: source, to: target)
            } catch {
                NSLog("KasumiOpen: cannot read %@", path)
                return
            }
            await waitForBrowser()
            open(target)
        }
    #endif
}

/// Reports the window hosting the launch overlay.
fileprivate struct WindowReader: UIViewRepresentable {
    let found: (UIWindow) -> Void
    func makeUIView(context: Context) -> Probe { Probe(found: found) }
    func updateUIView(_ view: Probe, context: Context) {}
    final class Probe: UIView {
        let found: (UIWindow) -> Void
        init(found: @escaping (UIWindow) -> Void) {
            self.found = found
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { found(window) }
        }
    }
}

struct LaunchPresenter: View {
    @Bindable var store: LaunchStore
    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .background(WindowReader { store.window = $0 })
            #if DEBUG
                .task { await store.openDebugDocumentIfRequested() }
            #endif
            .sheet(isPresented: $store.showURLImport, onDismiss: store.urlImportDismissed) {
                NavigationStack {
                    URLImportView(save: store.saveDownload)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel", systemImage: "xmark") { store.showURLImport = false }
                            }
                        }
                }
            }
            .alert(item: $store.alert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message))
            }
    }
}

struct URLImportView: View {
    let save: (Data, URL) throws -> Void
    @State private var urlText = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var failures = 0
    @FocusState private var urlFocused: Bool

    private var trimmedURL: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canOpen: Bool { !loading && !trimmedURL.isEmpty }
    private var fieldBorder: Color {
        if errorMessage != nil { return .red }
        return urlFocused ? .accentColor : Color.primary.opacity(0.12)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("https://example.com/document.md", text: $urlText)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($urlFocused)
                        .onSubmit { if canOpen { fetch() } }
                        .accessibilityLabel("Document URL")
                        .accessibilityIdentifier("document-url")
                    if !urlText.isEmpty && !loading {
                        Button {
                            urlText = ""
                            urlFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .frame(minWidth: 28, minHeight: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear URL")
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(fieldBorder, lineWidth: urlFocused || errorMessage != nil ? 1.5 : 1)
                }
                .opacity(loading ? 0.6 : 1)
                .disabled(loading)
                .keyframeAnimator(initialValue: 0.0, trigger: failures) { content, x in
                    content.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(8, duration: 0.07)
                        SpringKeyframe(-7, duration: 0.07)
                        SpringKeyframe(5, duration: 0.07)
                        SpringKeyframe(-3, duration: 0.07)
                        SpringKeyframe(0, duration: 0.07)
                    }
                }

                ZStack(alignment: .topLeading) {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    } else {
                        Text("A direct HTTPS link to Markdown or plain text, up to 5 MB.")
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

                Button(action: fetch) {
                    ZStack {
                        Text("Open").opacity(loading ? 0 : 1)
                        ProgressView().tint(.white).opacity(loading ? 1 : 0)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .disabled(trimmedURL.isEmpty)
                .allowsHitTesting(!loading)
                .accessibilityLabel(loading ? "Opening" : "Open")
                .accessibilityIdentifier("open-url")
                .padding(.top, 8)
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .animation(.snappy(duration: 0.2), value: urlText.isEmpty)
            .animation(.smooth(duration: 0.2), value: urlFocused)
            .animation(.smooth(duration: 0.25), value: errorMessage)
            .animation(.smooth(duration: 0.25), value: loading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Open URL")
        .navigationBarTitleDisplayMode(.large)
        .sensoryFeedback(.error, trigger: failures)
        .onChange(of: urlText) { _, _ in errorMessage = nil }
        .task { urlFocused = true }
    }
    private func fail(_ message: String) {
        errorMessage = message
        failures += 1
    }
    private func fetch() {
        guard !loading else { return }
        guard let url = URL(string: trimmedURL), url.scheme?.lowercased() == "https", url.host != nil else {
            fail("Enter a complete HTTPS URL.")
            return
        }
        urlFocused = false
        loading = true
        errorMessage = nil
        Task {
            do {
                let (data, finalURL) = try await TextURLLoader.load(url)
                try save(data, finalURL)
            } catch {
                loading = false
                fail(error.localizedDescription)
                urlFocused = true
            }
        }
    }
}

fileprivate enum TextURLLoader {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    final class HTTPSRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
        }
    }
    @concurrent static func load(_ url: URL) async throws -> (Data, URL) {
        let limit = 5 * 1024 * 1024
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        let session = URLSession(configuration: configuration, delegate: HTTPSRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let finalURL = response.url, finalURL.scheme?.lowercased() == "https"
        else { throw Failure(message: "The server did not return an HTTPS document.") }
        let mime = (response.mimeType ?? "").lowercased()
        guard mime.hasPrefix("text/") || ["application/markdown", "application/x-markdown"].contains(mime) else {
            throw Failure(
                message: "The URL must return text or Markdown, not \(mime.isEmpty ? "an unknown content type" : mime)."
            )
        }
        guard response.expectedContentLength <= limit else {
            throw Failure(message: "The document exceeds the 5 MB limit.")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw Failure(message: "The document exceeds the 5 MB limit.") }
            data.append(byte)
        }
        return (data, finalURL)
    }
}
