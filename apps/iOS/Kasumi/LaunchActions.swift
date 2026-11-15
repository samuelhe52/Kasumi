import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class LaunchStore {
    var document: ReaderDocument?
    var pasteError: String?

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
    /// Reads the clipboard on tap. Under Paste from Other Apps > Ask, this read
    /// is what makes iOS show its consent prompt; Deny leaves `string` nil.
    func pasteFromClipboard() {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else {
            pasteError = String(localized: "The clipboard contains no text to paste.")
            return
        }
        guard let text = pasteboard.string else {
            pasteError = String(localized: "Kasumi can't read the clipboard. Allow it in Settings > Apps > Kasumi > Paste from Other Apps.")
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pasteError = String(localized: "The clipboard contains no text to paste.")
            return
        }
        let data = Data(text.utf8)
        Task {
            let snapshot = await Task.detached { ReaderSnapshot(data: data, fileExtension: "md", baseURL: nil) }.value
            document = ReaderDocument(snapshot: snapshot, title: "Pasted Text")
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
            .alert("Could Not Paste", isPresented: Binding(
                get: { store.pasteError != nil },
                set: { if !$0 { store.pasteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.pasteError ?? "")
            }
    }
}

struct URLImportView: View {
    let document: ReaderDocument
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
            fail("Enter a complete HTTPS URL."); return
        }
        urlFocused = false
        loading = true; errorMessage = nil
        Task {
            do {
                let (data, finalURL) = try await TextURLLoader.load(url)
                document.snapshot = await Task.detached {
                    ReaderSnapshot(data: data, fileExtension: "md", baseURL: finalURL.deletingLastPathComponent())
                }.value
                let name = finalURL.lastPathComponent
                if !name.isEmpty && name != "/" { document.displayName = name }
                withAnimation(.smooth(duration: 0.35)) { document.needsURL = false }
            } catch {
                loading = false
                fail(error.localizedDescription)
                urlFocused = true
            }
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
