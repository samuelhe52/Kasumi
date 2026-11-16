import SwiftUI

@main
struct KasumiApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: KasumiAppDelegate
    @State private var launchStore = LaunchStore()
    init() {
        LaunchStore.installWelcomeIfNeeded()
        // Registers downloaded open fonts and re-requests Apple's before the
        // first document renders.
        _ = FontStore.shared
    }
    var body: some Scene {
        DocumentGroupLaunchScene(Text(verbatim: " ")) {
            Button("Paste Markdown") { launchStore.pasteFromClipboard() }
            Button("Open URL") { launchStore.remote() }
        } background: {
            LaunchBackground()
                .ignoresSafeArea()
        } backgroundAccessoryView: { geometry in
            LaunchLogotype(titleFrame: geometry.titleViewFrame)
        } overlayAccessoryView: { _ in
            LaunchPresenter(store: launchStore)
        }
        DocumentGroup { document in
            ReaderScreen(document: document).id(document.id)
        } makeReadableDocument: { configuration, _ in
            ReaderDocument(configuration: configuration)
        }
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
