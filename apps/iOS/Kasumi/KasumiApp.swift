import SwiftUI

@main
@MainActor
struct KasumiMain {
    static func main() {
        if #available(iOS 27.0, *) {
            KasumiApp.main()
        } else {
            LegacyKasumiApp.main()
        }
    }
}

@available(iOS 27.0, *)
struct KasumiApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: KasumiAppDelegate
    @State private var launchStore = LaunchStore()

    init() { prepareLaunch() }

    var body: some Scene {
        launchScene(store: launchStore)
        DocumentGroup(allowCreating: false) { document in
            ReaderScreen(document: document.model).id(document.model.id)
        } makeDocument: { configuration, _ in
            ModernReaderDocument(configuration: configuration)
        }
    }
}

private struct LegacyKasumiApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: KasumiAppDelegate
    @State private var launchStore = LaunchStore()

    init() { prepareLaunch() }

    var body: some Scene {
        launchScene(store: launchStore)
        DocumentGroup(newDocument: { LegacyReaderDocument() }) { configuration in
            LegacyReaderScreen(configuration: configuration)
        }
    }
}

@MainActor
private func prepareLaunch() {
    LaunchStore.installWelcomeIfNeeded()
    // Registers downloaded open fonts and re-requests Apple's before the first document renders.
    _ = FontStore.shared
}

@MainActor
private func launchScene(store: LaunchStore) -> some Scene {
    let title: Text
    if #available(iOS 26.0, *) {
        title = Text(verbatim: " ")
    } else {
        // The iOS 18 launcher places an opaque title card over the background accessory.
        title = Text(verbatim: "Kasumi").font(.system(.largeTitle, design: .serif, weight: .light))
    }
    return DocumentGroupLaunchScene(title) {
        Button("Paste Markdown") { store.pasteFromClipboard() }
        Button("Open URL") { store.remote() }
        Button("Open Source Licenses") { store.showLicenses = true }
    } background: {
        LaunchBackground()
            .ignoresSafeArea()
    } backgroundAccessoryView: { geometry in
        if #available(iOS 26.0, *) {
            LaunchLogotype(titleFrame: geometry.titleViewFrame)
        }
    } overlayAccessoryView: { _ in
        LaunchPresenter(store: store)
    }
}

/// Mist at dawn in light mode; the app icon's dusk in dark mode.
fileprivate struct LaunchBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.13, green: 0.15, blue: 0.31), Color(red: 0.33, green: 0.28, blue: 0.44),
                    Color(red: 0.62, green: 0.47, blue: 0.52)
                ]
                : [
                    Color(red: 0.89, green: 0.88, blue: 0.95), Color(red: 0.95, green: 0.91, blue: 0.93),
                    Color(red: 0.98, green: 0.88, blue: 0.83)
                ],
            startPoint: .top, endPoint: .bottom)
    }
}
