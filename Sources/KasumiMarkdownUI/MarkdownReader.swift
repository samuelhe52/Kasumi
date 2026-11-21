import KasumiMarkdown
import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// A viewport-sized native reader. Do not embed it in another scroll view.
@MainActor public struct MarkdownReader: View {
    let document: MarkdownDocument
    let style: RenderStyle
    let documentURL: URL?
    let initialAnchor: ReadingAnchor?
    let isActive: Bool
    let layoutRevision: Int
    private var remoteImages: MarkdownRemoteImages?
    private var imageRevision = 0
    private var findPresented: Binding<Bool>?
    private var openLink: ((URL) -> Void)?
    private var positionChange: ((ReadingAnchor, String?) -> Void)?
    private var findResultChange: ((FindResult) -> Void)?
    #if os(iOS)
        private var codeControl: ((RenderedCodeBlock) -> UIControl?)?
    #endif
    @Environment(\.markdownReaderConnection) private var connection

    public init(
        document: MarkdownDocument, style: RenderStyle = .init(), documentURL: URL? = nil,
        initialAnchor: ReadingAnchor? = nil, isActive: Bool = true, layoutRevision: Int = 0
    ) {
        self.document = document
        self.style = style
        self.documentURL = documentURL
        self.initialAnchor = initialAnchor
        self.isActive = isActive
        self.layoutRevision = layoutRevision
    }

    public var body: some View { ReaderBridge(reader: self, connection: connection) }

    /// Links within this document are handled by the reader. Other links go here.
    public func onMarkdownLink(_ action: @escaping (URL) -> Void) -> Self {
        var reader = self
        reader.openLink = action
        return reader
    }

    public func onMarkdownPositionChange(_ action: @escaping (ReadingAnchor, String?) -> Void) -> Self {
        var reader = self
        reader.positionChange = action
        return reader
    }

    public func onMarkdownFindResultChange(_ action: @escaping (FindResult) -> Void) -> Self {
        var reader = self
        reader.findResultChange = action
        return reader
    }

    /// Controls the native Find panel. The binding also reflects responder commands and dismissal.
    @available(iOS 16.0, *)
    public func markdownFindNavigator(isPresented: Binding<Bool>) -> Self {
        var reader = self
        reader.findPresented = isPresented
        return reader
    }

    /// Pass the same configuration across updates. Change `revision` to reload the same URLs.
    public func markdownRemoteImages(_ configuration: MarkdownRemoteImages?, revision: Int = 0) -> Self {
        var reader = self
        reader.remoteImages = configuration
        reader.imageRevision = revision
        return reader
    }

    #if os(iOS)
        /// Installs a host control with a frame in document coordinates for each eligible code block.
        public func markdownCodeBlockControl(_ factory: @escaping (RenderedCodeBlock) -> UIControl?) -> Self {
            var reader = self
            reader.codeControl = factory
            return reader
        }
    #endif

    fileprivate func update(_ view: MarkdownReaderView, coordinator: ReaderBridgeCoordinator, animated: Bool) {
        let restores = !coordinator.configuredDocument || coordinator.documentURL != documentURL
        if restores { coordinator.resetPosition() }
        coordinator.configure(self, view: view)
        #if os(iOS)
            view.animatesDocumentChanges = animated
            view.configureCodeBlockControl(codeControl)
        #endif
        view.isActive = isActive
        view.style = style
        view.setRemoteImages(remoteImages, revision: imageRevision)
        view.setDocument(document, url: documentURL, restoring: restores ? initialAnchor : nil)
        coordinator.configuredDocument = true
        coordinator.documentURL = documentURL
        if coordinator.layoutRevision != layoutRevision {
            if coordinator.layoutRevision != nil { view.invalidateLayout() }
            coordinator.layoutRevision = layoutRevision
        }
        coordinator.updateFind(findPresented)
    }

    fileprivate func attachCallbacks(to coordinator: ReaderBridgeCoordinator) {
        coordinator.openLink = openLink
        coordinator.positionChange = positionChange
        coordinator.findResultChange = findResultChange
    }
}

/// Commands for the single reader inside a `MarkdownReaderScope`. A proxy does not retain its native view.
@MainActor public struct MarkdownReaderProxy {
    fileprivate let connection: ReaderConnection

    public func scroll(to anchor: ReadingAnchor, animated: Bool = true) {
        connection.view?.scroll(to: anchor, animated: animated)
    }

    public func scroll(toAnchorID id: String, animated: Bool = true) {
        connection.view?.scroll(toAnchorID: id, animated: animated)
    }

    public func setFindQuery(_ query: String, options: SearchOptions = []) {
        connection.view?.setFindQuery(query, options: options)
    }

    public func moveToFindMatch(_ direction: FindDirection) { connection.view?.moveToFindMatch(direction) }
    public func clearFind() { connection.view?.clearFind() }
}

/// Gives surrounding SwiftUI controls commands for one enclosed `MarkdownReader`.
@MainActor public struct MarkdownReaderScope<Content: View>: View {
    @StateObject private var connection = ReaderConnection()
    private let content: (MarkdownReaderProxy) -> Content

    public init(@ViewBuilder content: @escaping (MarkdownReaderProxy) -> Content) { self.content = content }

    public var body: some View {
        content(MarkdownReaderProxy(connection: connection))
            .environment(\.markdownReaderConnection, connection)
    }
}

@MainActor fileprivate final class ReaderConnection: ObservableObject {
    weak var view: MarkdownReaderView?
}

private enum ReaderConnectionKey: EnvironmentKey {
    static let defaultValue: ReaderConnection? = nil
}

extension EnvironmentValues {
    fileprivate var markdownReaderConnection: ReaderConnection? {
        get { self[ReaderConnectionKey.self] }
        set { self[ReaderConnectionKey.self] = newValue }
    }
}

@MainActor fileprivate final class ReaderBridgeCoordinator {
    weak var view: MarkdownReaderView?
    weak var connection: ReaderConnection?
    var configuredDocument = false
    var documentURL: URL?
    var layoutRevision: Int?
    var openLink: ((URL) -> Void)?
    var positionChange: ((ReadingAnchor, String?) -> Void)?
    var findResultChange: ((FindResult) -> Void)?
    private var findBinding: Binding<Bool>?
    private var findRequest: Bool?
    private var findApplied = false
    private var findEpoch = 0
    private var position: (ReadingAnchor, String?)?
    private var result: FindResult?
    private var callbackTask: Task<Void, Never>?

    func configure(_ reader: MarkdownReader, view: MarkdownReaderView) {
        reader.attachCallbacks(to: self)
        guard self.view !== view else { return }
        self.view = view
        view.onOpenLink = { [weak self] url in self?.openLink?(url) }
        view.onPositionChange = { [weak self] anchor, heading in
            guard let self, self.positionChange != nil else { return }
            self.position = (anchor, heading)
            self.flushCallbacks()
        }
        view.onFindResultChange = { [weak self] result in
            guard let self, self.findResultChange != nil else { return }
            self.result = result
            self.flushCallbacks()
        }
        view.onFindPresentationChange = { [weak self] in self?.findVisibilityChanged($0) }
    }

    func connect(_ next: ReaderConnection?) {
        if connection !== next, connection?.view === view { connection?.view = nil }
        connection = next
        if let view { next?.view = view }
    }

    func updateFind(_ binding: Binding<Bool>?) {
        findBinding = binding
        let requested = binding?.wrappedValue
        if requested != findRequest {
            findEpoch &+= 1
            findRequest = requested
            findApplied = false
        }
        guard let requested, let view else { return }
        if requested {
            if !findApplied { findApplied = view.presentFind() }
        } else if !findApplied {
            findApplied = true
            view.dismissFind()
        }
    }

    private func findVisibilityChanged(_ shown: Bool) {
        guard findBinding != nil else { return }
        findEpoch &+= 1
        let epoch = findEpoch
        let previous = findBinding?.wrappedValue
        Task { @MainActor [weak self] in
            guard let self, let view, let binding = findBinding, findEpoch == epoch,
                binding.wrappedValue == previous, view.isFindPresented == shown
            else { return }
            findRequest = shown
            findApplied = true
            if binding.wrappedValue != shown { binding.wrappedValue = shown }
        }
    }

    func resetPosition() { position = nil }

    private func flushCallbacks() {
        guard callbackTask == nil else { return }
        callbackTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            callbackTask = nil
            let pendingPosition = position
            let pendingResult = result
            position = nil
            result = nil
            if let (anchor, heading) = pendingPosition { positionChange?(anchor, heading) }
            if let pendingResult { findResultChange?(pendingResult) }
        }
    }

    func finish() {
        callbackTask?.cancel()
        findEpoch &+= 1
        findBinding = nil
        connect(nil)
        view = nil
    }
}

@MainActor fileprivate struct ReaderBridge {
    let reader: MarkdownReader
    let connection: ReaderConnection?

    func makeCoordinator() -> ReaderBridgeCoordinator { ReaderBridgeCoordinator() }

    private func update(_ view: MarkdownReaderView, coordinator: ReaderBridgeCoordinator, animated: Bool) {
        reader.update(view, coordinator: coordinator, animated: animated)
        coordinator.connect(connection)
    }
}

#if os(iOS)
    extension ReaderBridge: UIViewRepresentable {
        func makeUIView(context: Context) -> MarkdownReaderView { MarkdownReaderView(frame: .zero) }
        func updateUIView(_ view: MarkdownReaderView, context: Context) {
            update(view, coordinator: context.coordinator, animated: context.transaction.animation != nil)
        }
        static func dismantleUIView(_ view: MarkdownReaderView, coordinator: ReaderBridgeCoordinator) {
            coordinator.finish()
            view.finish()
        }
    }
#elseif os(macOS)
    extension ReaderBridge: NSViewRepresentable {
        func makeNSView(context: Context) -> MarkdownReaderView { MarkdownReaderView(frame: .zero) }
        func updateNSView(_ view: MarkdownReaderView, context: Context) {
            update(view, coordinator: context.coordinator, animated: false)
        }
        static func dismantleNSView(_ view: MarkdownReaderView, coordinator: ReaderBridgeCoordinator) {
            coordinator.finish()
            view.finish()
        }
    }
#endif
