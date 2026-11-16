import SwiftUI

/// Offers the recommended CJK faces once, on whichever screen appears first:
/// a launch URL skips the launch scene, so the reader presents it too.
struct FontOnboardingModifier: ViewModifier {
    @AppStorage("onboarding.fonts-offered") private var offered = false
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .task {
                guard !offered, !FontOnboarding.claimed, !FontStore.shared.pendingRecommended.isEmpty else { return }
                FontOnboarding.claimed = true
                presented = true
            }
            .sheet(isPresented: $presented, onDismiss: { offered = true }) {
                FontOnboarding()
            }
    }
}

extension View {
    func fontOnboarding() -> some View { modifier(FontOnboardingModifier()) }
}

struct FontOnboarding: View {
    /// Only one scene presents the sheet per launch.
    @MainActor static var claimed = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarding.fonts-offered") private var offered = false
    @State private var started = false
    private let store = FontStore.shared
    private let packages = FontPackage.apple.filter(\.recommended)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    specimen
                        .frame(maxWidth: .infinity).padding(.top, 8)
                        .accessibilityHidden(true)
                    Text(
                        "Kasumi's typography is set in Apple's Songti, Kaiti, and Fangsong. iOS downloads them from Apple on request and shares them with other apps."
                    )
                    Text(
                        "If a face isn't available, Kasumi downloads an openly licensed one in its place. You can manage fonts later from Appearance."
                    )
                    .foregroundStyle(.secondary)
                    if started {
                        VStack(spacing: 0) {
                            ForEach(packages + fallbacks) { package in
                                VStack(spacing: 0) {
                                    FontPackageRow(package: package, allowsChoosing: false).padding(.vertical, 8)
                                    Divider()
                                }
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .animation(.smooth, value: fallbacks.map(\.id))
                        .transition(.opacity.combined(with: .offset(y: 24)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaInset(edge: .bottom) { buttons }
            .navigationTitle("Chinese Fonts")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(!started)
    }

    /// One character per face. Until a face (or its open fallback) is installed
    /// the character is a dimmed placeholder in the system face: Apple's faces
    /// can't be bundled, so the real glyphs only appear once downloaded.
    private var specimen: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            glyph("宋", "songti-sc")
            glyph("楷", "kaiti-sc")
            glyph("仿", "fangsong")
        }
        .font(.system(size: 44))
        .animation(.smooth(duration: 0.6), value: ["songti-sc", "kaiti-sc", "fangsong"].map(face))
    }

    /// The package whose face shows for an Apple package: itself, or its open
    /// fallback, once installed.
    private func face(_ id: String) -> FontPackage? {
        let package = FontPackage.named(id)!
        return [package, package.fallbackID.flatMap(FontPackage.named)].compactMap { $0 }
            .first { store.state($0) == .installed }
    }

    private func glyph(_ character: String, _ id: String) -> some View {
        let installed = face(id)
        return Group {
            if let face = installed?.postScriptNames.first {
                Text(character).font(.custom(face, size: 44)).foregroundStyle(.primary)
            } else {
                Text(character).foregroundStyle(.quaternary)
            }
        }
        .id(installed?.id ?? "placeholder")
        .transition(.blurReplace)
    }

    /// Open faces that replaced an Apple face that failed.
    private var fallbacks: [FontPackage] {
        FontPackage.open.filter { store.state($0) != .missing }
    }

    private var buttons: some View {
        VStack(spacing: 16) {
            if started {
                Button {
                    dismiss()
                } label: {
                    Text(store.isDownloading ? "Continue in Background" : "Done")
                        .contentTransition(.interpolate)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .animation(.smooth, value: store.isDownloading)
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.smooth) { started = true }
                    offered = true
                    store.installRecommended()
                } label: {
                    Text("Download Fonts").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .accessibilityIdentifier("onboarding-download-fonts")
                .transition(.opacity)
                Button("Not Now") { dismiss() }
                    .controlSize(.large)
                    .accessibilityIdentifier("onboarding-not-now")
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}
