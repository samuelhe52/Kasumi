import SwiftUI

/// Offers the recommended CJK faces once, on whichever screen appears first:
/// a launch URL skips the launch scene, so the reader presents it too.
struct FontOnboardingModifier: ViewModifier {
    @AppStorage("onboarding.fonts-offered") private var offered = false
    @State private var presented = false
    @State private var showFonts = false
    @MainActor private static var claimed = false

    func body(content: Content) -> some View {
        content
            .task {
                guard !offered, !Self.claimed else { return }
                #if DEBUG
                    // An explicit reset also previews the offer when all faces are cached.
                    let preview = ProcessInfo.processInfo.arguments.contains("-onboarding.fonts-offered")
                #else
                    let preview = false
                #endif
                guard preview || FontPackage.apple.contains(where: {
                    $0.recommended && FontStore.shared.state($0) != .installed
                }) else { return }
                Self.claimed = true
                presented = true
            }
            .alert("Chinese Fonts", isPresented: $presented) {
                Button("Not Now", role: .cancel) { offered = true }
                Button("Download Fonts") {
                    offered = true
                    showFonts = true
                }
            } message: {
                Text("Some Chinese fonts are unavailable. Would you like to download them?")
            }
            .sheet(isPresented: $showFonts) { FontStoreView() }
    }
}

extension View {
    func fontOnboarding() -> some View { modifier(FontOnboardingModifier()) }
}

