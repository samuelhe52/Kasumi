import Foundation
import KasumiMarkdown
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

@MainActor
final class LegacyReaderDocument: ReferenceFileDocument {
    nonisolated static let readableContentTypes = ReaderDocument.readableContentTypes

    // The synchronous save callbacks can run independently of the reader UI.
    private let latest: Mutex<ReaderDocument.WriteSnapshot>
    private let defaultExtension: String
    @Published private var changeCount = 0

    private var readerModel: ReaderDocument?

    func model(fileURL: URL?, isEditable: Bool) -> ReaderDocument {
        if let readerModel { return readerModel }
        let source = latest.withLock { $0.source }
        let model = ReaderDocument(
            source: source, defaultExtension: defaultExtension, isEditable: isEditable,
            didEdit: { [weak self] snapshot in
                guard let self else { return }
                latest.withLock { $0 = snapshot }
                changeCount &+= 1
            })
        readerModel = model
        model.setLegacyFileURL(fileURL)
        return model
    }

    nonisolated init(source: DocumentSource = DocumentSource(text: ""), defaultExtension: String = "md") {
        self.latest = Mutex(.init(source: source, text: source.text))
        self.defaultExtension = defaultExtension
    }

    nonisolated convenience init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(
            source: DocumentSource(data: bytes),
            defaultExtension: configuration.contentType == .plainText ? "txt" : "md")
    }

    nonisolated func snapshot(contentType: UTType) throws -> ReaderDocument.WriteSnapshot {
        latest.withLock { $0 }
    }

    nonisolated func fileWrapper(
        snapshot: ReaderDocument.WriteSnapshot, configuration: WriteConfiguration
    ) throws -> FileWrapper {
        try FileWrapper(regularFileWithContents: snapshot.data())
    }
}

struct LegacyReaderScreen: View {
    let configuration: ReferenceFileDocumentConfiguration<LegacyReaderDocument>

    var body: some View {
        let model = configuration.document.model(
            fileURL: configuration.fileURL, isEditable: configuration.isEditable)
        ReaderScreen(document: model)
            .id(model.id)
            // The document host restores its bar on foregrounding unless the
            // scene's reader root requests that it stay hidden.
            .toolbarVisibility(usesLegacyToolbar ? .hidden : .automatic, for: .navigationBar)
            .onChange(of: configuration.fileURL) { _, url in model.setLegacyFileURL(url) }
            .onChange(of: configuration.isEditable) { _, isEditable in model.isEditable = isEditable }
    }

    private var usesLegacyToolbar: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }
}
