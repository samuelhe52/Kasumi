import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Principal class of the "Import into Kasumi" action. It copies the shared
/// file into the App Group inbox and says so; Kasumi imports it the next time
/// it becomes active.
final class ImportViewController: UIViewController {
    private let model = ImportModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(
            rootView: ImportView(model: model) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        Task {
            await model.run(providers)
            // Bring Kasumi forward to import and open the file. If that doesn't
            // work, the confirmation sheet stays and tells the user to open it.
            if model.state == .done, await openKasumi() {
                extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    /// Opens Kasumi through the hosting scene. Action extensions can't use
    /// `UIApplication.open` or `NSExtensionContext.open`, but the scene the
    /// extension is presented in accepts a URL. Reports whether the system
    /// opened it, so the caller can keep its fallback sheet.
    private func openKasumi() async -> Bool {
        guard let scene = view.window?.windowScene else { return false }
        return await withCheckedContinuation { continuation in
            scene.open(ImportInbox.openURL, options: nil) { continuation.resume(returning: $0) }
        }
    }
}

@MainActor @Observable
final class ImportModel {
    enum State: Equatable {
        case importing
        case done
        case failed(String)
    }
    private(set) var state = State.importing

    func run(_ providers: [NSItemProvider]) async {
        guard
            let provider = providers.first(where: { Self.textType(of: $0) != nil }),
            let type = Self.textType(of: provider)
        else {
            state = .failed("There is no text document to import.")
            return
        }
        do {
            try await Self.copy(provider, as: type)
            state = .done
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private nonisolated static func textType(of provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .plainText) == true }
    }

    /// The provider's file is only valid inside the completion handler, so the
    /// copy into the inbox happens there.
    private static func copy(_ provider: NSItemProvider, as type: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { @Sendable url, error in
                do {
                    guard let url else { throw error ?? ImportInbox.Failure(message: "The document can't be read.") }
                    try ImportInbox.deposit(url, named: url.lastPathComponent)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct ImportView: View {
    let model: ImportModel
    let finish: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                switch model.state {
                case .importing:
                    ProgressView()
                    Text("Importing…").foregroundStyle(.secondary)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Added to Kasumi").font(.headline)
                    Text("Open Kasumi to start reading.").foregroundStyle(.secondary)
                case .failed(let message):
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text("Couldn't Import").font(.headline)
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.smooth(duration: 0.2), value: model.state)
            .navigationTitle("Import into Kasumi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finish).disabled(model.state == .importing)
                }
            }
        }
    }
}
