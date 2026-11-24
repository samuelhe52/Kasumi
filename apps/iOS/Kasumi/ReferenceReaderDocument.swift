import Foundation
import KasumiMarkdown
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

@MainActor
final class ReferenceReaderDocument: ReferenceFileDocument {
    nonisolated static let readableContentTypes = ReaderDocument.readableContentTypes

    // The synchronous save callbacks can run independently of the reader UI.
    private let latest: Mutex<ReaderDocument.WriteSnapshot>
    private let defaultExtension: String
    @Published private var changeCount = 0

    private var readerModel: ReaderDocument?

    func model(fileURL: URL?, isEditable: Bool) -> ReaderDocument {
        if let readerModel { return readerModel }
        let source = latest.withLock { $0.source }
        let model = ReaderDocument(source: source, defaultExtension: defaultExtension, isEditable: isEditable)
        model.onEdit = { [weak self] snapshot in
            guard let self else { return }
            latest.withLock { $0 = snapshot }
            changeCount &+= 1
        }
        readerModel = model
        model.setFileURL(fileURL)
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
