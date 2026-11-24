import AppKit

final class MacDocumentController: NSDocumentController {
    private final class OpenRequest {
        weak var source: NSWindow?

        init(source: NSWindow?) { self.source = source }
    }

    private var requests: [URL: [OpenRequest]] = [:]

    override var hasEditedDocuments: Bool {
        documents.contains(where: \.isDocumentEdited) || super.hasEditedDocuments
    }

    override func openDocument(
        withContentsOf url: URL, display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        // AppKit otherwise tries to open a symlink as a distinct document type.
        let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        super.openDocument(withContentsOf: resolvedURL, display: displayDocument, completionHandler: completionHandler)
    }

    @objc func pasteAsNewDocument(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        do {
            guard let document = try openUntitledDocumentAndDisplay(false) as? MacDocument else { return }
            document.setInitialText(text)
            document.updateChangeCount(.changeDone)
            document.makeWindowControllers()
            document.showWindows()
        } catch {
            NSApp.presentError(error)
        }
    }

    func open(_ url: URL, from source: NSWindow?, fragment: String?) {
        let key = url.standardizedFileURL.resolvingSymlinksInPath()
        let request = OpenRequest(source: source)
        requests[key, default: []].append(request)
        openDocument(withContentsOf: url, display: true) { [weak self] document, _, error in
            if let self {
                requests[key]?.removeAll { $0 === request }
                if requests[key]?.isEmpty == true { requests.removeValue(forKey: key) }
            }
            if let error {
                NSApp.presentError(error)
            } else if let fragment {
                (document as? MacDocument)?.session?.follow(fragment: fragment)
            }
        }
    }

    func destination(for window: NSWindow, url: URL?) -> NSWindow? {
        if let key = url?.standardizedFileURL.resolvingSymlinksInPath(),
            let source = requests[key]?.first?.source,
            source !== window, source.windowController?.document is MacDocument, !source.isMiniaturized
        {
            // The source may now be a background tab. Its selected sibling
            // represents the same group and tells us whether it is still shown.
            let selected = source.tabGroup?.selectedWindow ?? source
            if selected.isVisible && !selected.isMiniaturized { return selected }
        }

        let candidates = NSApp.orderedWindows.filter {
            $0 !== window && $0.isVisible && !$0.isMiniaturized
                && ($0.windowController?.document as? MacDocument)?.isInViewingMode == false
        }
        return candidates.first(where: \.isOnActiveSpace) ?? candidates.first
    }
}
