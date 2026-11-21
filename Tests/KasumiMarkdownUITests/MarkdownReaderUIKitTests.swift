#if os(iOS)
import KasumiMarkdown
import KasumiMarkdownUI
import SwiftUI
import Testing
import UIKit

@MainActor @Suite(.serialized) struct MarkdownReaderUIKitTests {
    @Test func firstLayoutPreservesFocusedHostField() async throws {
        let host = UIViewController()
        let window = makeWindow(hosting: host)
        defer { window.isHidden = true }
        let field = UITextField(frame: CGRect(x: 16, y: 30, width: 250, height: 44))
        host.view.addSubview(field)
        try #require(field.becomeFirstResponder())
        #expect(field.isFirstResponder)

        let reader = MarkdownReaderView(frame: CGRect(x: 0, y: 80, width: 320, height: 350))
        var installed = false
        reader.onPositionChange = { _, _ in installed = true }
        host.view.addSubview(reader)
        reader.setDocument(MarkdownDocument(markdown: "A document that opens next to a host search field."))
        try #require(await eventually { installed })
        #expect(field.isFirstResponder)
    }

    @Test(arguments: [false, true]) func swiftUIFactoryUpdatesInstalledAction(keyed: Bool) async throws {
        let model = FactoryModel()
        let host = UIHostingController(rootView: FactoryHost(model: model, keyed: keyed))
        let window = makeWindow(hosting: host)
        defer { window.isHidden = true }
        try #require(await eventually { control(in: host.view) != nil })
        let initial = try #require(control(in: host.view))

        model.mode = .second
        try #require(await eventually { control(in: host.view) !== initial })
        let updated = try #require(control(in: host.view))
        updated.sendActions(for: .primaryActionTriggered)
        #expect(model.invoked == .second)

        model.mode = .hidden
        #expect(await eventually { control(in: host.view) == nil })
    }

    @Test func responsiveRemoteStartsWhileTheFirstProviderIsSuspended() async throws {
        let provider = ImageGate()
        let host = UIViewController()
        let window = makeWindow(hosting: host)
        defer {
            window.isHidden = true
            provider.release()
        }
        let reader = MarkdownReaderView(frame: host.view.bounds)
        reader.setRemoteImages(MarkdownRemoteImages { url in await provider.resolve(url) })
        host.view.addSubview(reader)
        reader.setDocument(MarkdownDocument(markdown: """
            <img src="https://example.invalid/slow" alt="Slow" width="40" height="40">

            <img src="https://example.invalid/fast" alt="Fast" width="40" height="40">
            """))
        try #require(await eventually { provider.slow != nil })
        #expect(await eventually { provider.requestedFast })
    }

    @MainActor private final class ImageGate {
        var slow: CheckedContinuation<Void, Never>?
        var requestedFast = false

        func resolve(_ url: URL) async -> MarkdownImageResource? {
            if url.lastPathComponent == "slow" {
                await withCheckedContinuation { slow = $0 }
            } else if url.lastPathComponent == "fast" {
                requestedFast = true
            }
            return nil
        }

        func release() { slow?.resume(); slow = nil }
    }

    private func makeWindow(hosting host: UIViewController) -> UIWindow {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 460)
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first.map {
            UIWindow(windowScene: $0)
        } ?? UIWindow(frame: frame)
        window.frame = frame
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return window
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func control(in view: UIView) -> UIControl? {
        if view.accessibilityIdentifier == "test-reader-control" { return view as? UIControl }
        for child in view.subviews {
            if let result = control(in: child) { return result }
        }
        return nil
    }

    @MainActor private final class FactoryModel: ObservableObject {
        enum Mode: Hashable { case first, second, hidden }
        let document = MarkdownDocument(markdown: "```swift\nlet sample = 42\n```")
        @Published var mode = Mode.first
        var invoked: Mode?
    }

    private struct FactoryHost: View {
        @ObservedObject var model: FactoryModel
        let keyed: Bool

        var body: some View {
            let mode = model.mode
            MarkdownReader(document: model.document)
                .markdownCodeBlockControl(id: keyed ? AnyHashable(mode) : nil) { block in
                    guard mode != .hidden else { return nil }
                    let button = UIButton(frame: block.frame)
                    button.accessibilityIdentifier = "test-reader-control"
                    button.addAction(UIAction { _ in model.invoked = mode }, for: .primaryActionTriggered)
                    return button
                }
        }
    }
}
#endif
