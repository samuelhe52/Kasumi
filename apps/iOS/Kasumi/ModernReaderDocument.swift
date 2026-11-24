import Foundation
import KasumiMarkdown
import SwiftUI
import UniformTypeIdentifiers

@available(iOS 27.0, *)
@MainActor @Observable
final class ModernReaderDocument: Document {
    nonisolated static let readableContentTypes = ReaderDocument.readableContentTypes
    let model: ReaderDocument

    init(configuration: URLDocumentConfiguration) {
        model = ReaderDocument(fileURLProvider: { configuration.fileURL })
    }

    struct Reader: DocumentReader {
        @concurrent
        func read(from url: sending URL, progress: consuming Subprogress) async throws -> sending ReaderSnapshot {
            let source = try DocumentSource(data: Data(contentsOf: url))
            return ReaderSnapshot(
                source: source, text: source.text, fileExtension: url.pathExtension,
                baseURL: url.deletingLastPathComponent())
        }
    }

    struct Writer: DocumentWriter {
        @concurrent
        func write(
            snapshot: sending ReaderDocument.WriteSnapshot, to destination: sending URL,
            previous: sending ReaderDocument.WriteSnapshot?, progress: consuming Subprogress
        ) async throws {
            try snapshot.data().write(to: destination, options: .atomic)
        }
    }

    nonisolated func reader(configuration: sending ReadConfiguration) -> sending Reader { Reader() }
    nonisolated func writer(configuration: sending WriteConfiguration) -> sending Writer { Writer() }

    func snapshot(contentType: UTType) async throws -> sending ReaderDocument.WriteSnapshot {
        model.writeSnapshot()
    }

    func apply(snapshot: sending ReaderSnapshot, previous: sending ReaderSnapshot?) async throws {
        model.apply(snapshot)
    }
}
