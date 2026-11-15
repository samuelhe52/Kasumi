import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class LaunchStore {
    var document: ReaderDocument?
    var errorMessage: String?

    /// Copies Welcome.md into the app's Documents folder once, so the browser
    /// opens on a real document. Deleting it later is respected.
    static func installWelcomeIfNeeded() {
        let key = "launch.welcome-installed"
        guard !UserDefaults.standard.bool(forKey: key),
              let source = Bundle.main.url(forResource: "Welcome", withExtension: "md"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let target = documents.appending(path: "Welcome.md")
        if !FileManager.default.fileExists(atPath: target.path) {
            guard (try? FileManager.default.copyItem(at: source, to: target)) != nil else { return }
        }
        UserDefaults.standard.set(true, forKey: key)
    }
    func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            errorMessage = "The pasteboard does not contain text."; return
        }
        let data = Data(text.utf8)
        Task {
            let snapshot = await Task.detached { ReaderSnapshot(data: data, fileExtension: "md", baseURL: nil) }.value
            document = ReaderDocument(snapshot: snapshot, title: "Untitled")
        }
    }
    func remote() {
        let snapshot = ReaderSnapshot(data: Data(), fileExtension: "md", baseURL: nil)
        let next = ReaderDocument(snapshot: snapshot, title: "Untitled")
        next.needsURL = true
        document = next
    }
}

struct LaunchPresenter: View {
    @Bindable var store: LaunchStore
    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .fullScreenCover(item: $store.document) { document in
                ReaderScreen(document: document, canClose: true)
            }
            .alert("Could Not Open Document", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }
}

struct URLImportView: View {
    let document: ReaderDocument
    @State private var urlText = ""
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("https://example.com/document.md", text: $urlText)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("document-url")
            Text("HTTPS text or Markdown, up to 5 MB.").font(.footnote).foregroundStyle(.secondary)
            Button("Open") { fetch() }.disabled(loading || urlText.isEmpty)
            if loading { ProgressView("Opening…") }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Open URL")
    }
    private func fetch() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.lowercased() == "https", url.host != nil else {
            errorMessage = "Enter a complete HTTPS URL."; return
        }
        loading = true; errorMessage = nil
        Task {
            do {
                let (data, finalURL) = try await TextURLLoader.load(url)
                document.snapshot = await Task.detached {
                    ReaderSnapshot(data: data, fileExtension: "md", baseURL: finalURL.deletingLastPathComponent())
                }.value
                document.needsURL = false
            } catch { errorMessage = error.localizedDescription }
            loading = false
        }
    }
}

private enum TextURLLoader {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    final class HTTPSRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
        }
    }
    @concurrent static func load(_ url: URL) async throws -> (Data, URL) {
        let limit = 5 * 1024 * 1024
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 45
        let session = URLSession(configuration: configuration, delegate: HTTPSRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let finalURL = response.url, finalURL.scheme?.lowercased() == "https" else { throw Failure(message: "The server did not return an HTTPS document.") }
        let mime = (response.mimeType ?? "").lowercased()
        guard mime.hasPrefix("text/") || ["application/markdown", "application/x-markdown"].contains(mime) else {
            throw Failure(message: "The URL must return text or Markdown, not \(mime.isEmpty ? "an unknown content type" : mime).")
        }
        guard response.expectedContentLength <= limit else { throw Failure(message: "The document exceeds the 5 MB limit.") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw Failure(message: "The document exceeds the 5 MB limit.") }
            data.append(byte)
        }
        return (data, finalURL)
    }
}
