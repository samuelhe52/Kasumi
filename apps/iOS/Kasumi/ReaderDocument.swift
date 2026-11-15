import Foundation
import KasumiMarkdown
import Observation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let kasumiMarkdown = UTType("net.daringfireball.markdown")
        ?? UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// Source bytes stay in the snapshot so a future writer can preserve the original
/// encoding. This milestone implements only ReadableDocument: no document edits,
/// writer, or undo registrations are performed.
struct ReaderSnapshot: Sendable {
    let revision = UUID()
    let data: Data
    let parsed: MarkdownDocument?
    let error: String?

    init(data: Data, fileExtension: String, baseURL: URL?) {
        self.data = data
        do {
            parsed = try MarkdownDocument(data: data, fileExtension: fileExtension, baseURL: baseURL)
            error = nil
        } catch {
            parsed = nil
            self.error = error.localizedDescription
        }
    }
}

@MainActor @Observable
final class ReaderDocument: ReadableDocument, Identifiable {
    let id = UUID()
    nonisolated static let readableContentTypes: [UTType] = [.kasumiMarkdown, .plainText]
    let configuration: URLDocumentConfiguration?
    let initialURL: URL?
    let displayName: String?
    var snapshot: ReaderSnapshot?
    var needsURL = false

    var fileURL: URL? { configuration?.fileURL ?? initialURL }
    var title: String { displayName ?? fileURL?.lastPathComponent ?? "Untitled" }

    init(configuration: URLDocumentConfiguration) {
        self.configuration = configuration
        initialURL = nil; displayName = nil
    }

    init(snapshot: ReaderSnapshot, title: String, fileURL: URL? = nil) {
        self.snapshot = snapshot; displayName = title
        configuration = nil; initialURL = fileURL
    }

    struct Reader: DocumentReader {
        @concurrent
        func read(from source: sending URL, progress: consuming Subprogress) async throws -> sending ReaderSnapshot {
            let data = try Data(contentsOf: source)
            return ReaderSnapshot(data: data, fileExtension: source.pathExtension, baseURL: source.deletingLastPathComponent())
        }
    }

    nonisolated func reader(configuration: sending ReadConfiguration) -> sending Reader { Reader() }

    func apply(snapshot: sending ReaderSnapshot, previous: sending ReaderSnapshot?) async throws {
        self.snapshot = snapshot
    }
}
