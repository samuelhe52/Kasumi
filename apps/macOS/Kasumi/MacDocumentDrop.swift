import AppKit
import UniformTypeIdentifiers

/// Opens files dropped anywhere in a document window as new tabs.
///
/// The reader registers no drag types, so a drag over it reaches the nearest
/// registered ancestor, which is this split view.
final class MacDropSplitView: NSSplitView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:) instead") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Self.documents(in: sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Self.documents(in: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = Self.documents(in: sender)
        guard !urls.isEmpty, let controller = NSDocumentController.shared as? MacDocumentController else {
            return false
        }
        for url in urls { controller.open(url, from: window, fragment: nil) }
        return true
    }

    private static func documents(in sender: any NSDraggingInfo) -> [URL] {
        let urls =
            sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
            let type = UTType(filenameExtension: url.pathExtension)
            return MacFolderListing.supports(url) || type?.conforms(to: .kasumiMarkdown) == true
                || type?.conforms(to: .plainText) == true
        }
    }
}
