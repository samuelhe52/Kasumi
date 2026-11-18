import SwiftUI
import UIKit

/// Routes files handed to a running scene. `DocumentGroup` opens a file that
/// arrives while its scene connects, but on iOS 27.2 a file handed to a scene
/// that is already running brings the app forward without opening it.
/// SwiftUI forwards `scene(_:openURLContexts:)` to this delegate.
final class KasumiAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowApplication { configuration.delegateClass = HandoffSceneDelegate.self }
        return configuration
    }
}

final class HandoffSceneDelegate: NSObject, UIWindowSceneDelegate {
    private var pending: [UIOpenURLContext] = []

    /// A cold share hands its file to the connecting scene. SwiftUI opens that
    /// copy from Documents/Inbox itself; queuing it here moves it into
    /// Imported like a warm share, and the reader is replaced once active.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        pending += options.urlContexts.filter { $0.url.isFileURL && !$0.options.openInPlace }
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        pending += contexts.filter(\.url.isFileURL)
        if scene.activationState == .foregroundActive { flush(scene) }
    }

    /// A share arrives while the scene is still inactive; opening waits for it
    /// to become active.
    func sceneDidBecomeActive(_ scene: UIScene) { flush(scene) }

    /// Also drains files deposited by the "Import into Kasumi" action, which
    /// brings the app forward with `kasumi://import`. A launch with any URL makes
    /// SwiftUI skip the launch scene, so this can't wait for its overlay.
    private func flush(_ scene: UIScene) {
        guard let scene = scene as? UIWindowScene else { return }
        let contexts = pending
        pending = []
        Task { @MainActor in
            // One reader per window: everything is kept, the last file opens.
            var opened: URL?
            var received: [URL] = []
            for context in contexts {
                guard let url = DocumentBrowser.receive(context) else { continue }
                opened = url
                if url != context.url { received.append(context.url) }
            }
            ImportInbox.drain { data, name in
                opened = try ImportFolder.imported.save(data, as: ImportFolder.markdownName(name))
            }
            if let opened { await DocumentBrowser.show(opened, in: scene) }
            // After a cold share, SwiftUI's reader holds the incoming copy until
            // `show` closes it.
            for url in received { try? FileManager.default.removeItem(at: url) }
        }
    }
}

/// Opens files through the system document browser that `DocumentGroup`
/// installs in each window, so every reader gets the same file session and
/// presentation as a file the user picked. iOS has no public API for this
/// (`openDocument` is unavailable), so it relies on SwiftUI's view-controller
/// tree: if that changes, files still land in the browser for the user to tap.
@MainActor enum DocumentBrowser {
    /// Share-sheet copies move into Documents/Imported, like files from the
    /// "Import into Kasumi" action. Files opened in place stay where they are.
    /// The caller removes the incoming copy once its reader has closed.
    static func receive(_ context: UIOpenURLContext) -> URL? {
        let url = context.url
        guard !context.options.openInPlace else { return url }
        do {
            return try ImportFolder.imported.save(
                Data(contentsOf: url), as: ImportFolder.markdownName(url.lastPathComponent))
        } catch {
            NSLog("Handoff failed %@: %@", url.lastPathComponent, error.localizedDescription)
            return nil
        }
    }

    /// Closes the window's reader, if one is open, then opens `url`.
    @discardableResult
    static func show(_ url: URL, in scene: UIWindowScene) async -> Bool {
        // At launch the browser is still being presented. A document opened
        // before that finishes is closed again when it does, leaving an empty
        // window. A reader the user opens during the wait is closed too.
        for _ in 0..<150 {
            if let reader = readers[ObjectIdentifier(scene)] {
                // The browser leaves the window while a reader is shown, and
                // comes back as the reader's close finishes (onDisappear).
                await withCheckedContinuation { continuation in
                    readers[ObjectIdentifier(scene)]?.closed.append(continuation)
                    reader.close()
                }
            }
            if let browser = readyBrowser(in: scene) {
                // Files in Documents are already in the browser's location. Reveal
                // would import a copy, and fails (DocumentManager error 1) without import.
                browser.delegate?.documentBrowser?(browser, didPickDocumentsAt: [url])
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        NSLog("Handoff failed %@: no document browser", url.lastPathComponent)
        return false
    }

    // MARK: Readers

    private struct Reader {
        let id: UUID
        let close: () -> Void
        var closed: [CheckedContinuation<Void, Never>] = []
    }
    private static var readers: [ObjectIdentifier: Reader] = [:]

    static func readerAppeared(_ id: UUID, in scene: UIWindowScene, close: @escaping () -> Void) {
        readers[ObjectIdentifier(scene)] = Reader(id: id, close: close)
    }

    static func readerDisappeared(_ id: UUID, in scene: UIWindowScene) {
        guard readers[ObjectIdentifier(scene)]?.id == id,
            let reader = readers.removeValue(forKey: ObjectIdentifier(scene))
        else { return }
        reader.closed.forEach { $0.resume() }
    }

    // MARK: Browser lookup

    private static func readyBrowser(in scene: UIWindowScene) -> UIDocumentBrowserViewController? {
        guard scene.activationState == .foregroundActive else { return nil }
        for window in scene.windows {
            if let root = window.rootViewController, let browser = browser(in: root) {
                return browser.isBeingPresented ? nil : browser
            }
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
}

/// Reports the window hosting a view.
struct WindowReader: UIViewRepresentable {
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
