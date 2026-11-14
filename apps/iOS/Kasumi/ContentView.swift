import KasumiMarkdown
import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        FixturePreview()
            .accessibilityLabel("Kasumi Markdown fixture")
    }
}

private struct FixturePreview: UIViewRepresentable {
    func makeUIView(context: Context) -> FixtureScrollView { FixtureScrollView() }
    func updateUIView(_ uiView: FixtureScrollView, context: Context) {}
}

private final class FixtureScrollView: UIScrollView {
    private var page: UIView?
    private var requestedWidth: CGFloat = 0
    private var layoutTask: Task<Void, Never>?
    private let loading = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        alwaysBounceVertical = true
        addSubview(loading)
        loading.startAnimating()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { layoutTask?.cancel() }

    override func layoutSubviews() {
        super.layoutSubviews()
        loading.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let width = bounds.width
        guard width > 0, width != requestedWidth else { return }
        requestedWidth = width
        layoutTask?.cancel()
        guard let url = Bundle.main.url(forResource: "Sample", withExtension: "md") else { return }
        // File I/O, parsing, font resolution and layout all run outside the UI
        // actor. Only publishing the completed immutable snapshot hops back.
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try Data(contentsOf: url)
            let document = try MarkdownDocument(data: data, fileExtension: "md", baseURL: url.deletingLastPathComponent())
            try Task.checkCancellation()
            return RenderedDocument(document, width: width, style: RenderStyle())
        }
        layoutTask = Task { [weak self] in
            do {
                let rendered = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                guard !Task.isCancelled, let self, self.requestedWidth == width else { return }
                let page = FixturePageView(rendered: rendered, scale: max(1, self.traitCollection.displayScale))
                self.page?.removeFromSuperview()
                self.page = page
                self.addSubview(page)
                self.contentSize = page.bounds.size
                self.backgroundColor = UIColor(cgColor: rendered.backgroundColor)
                self.loading.stopAnimating()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.loading.stopAnimating()
                self.accessibilityValue = "Unable to load the sample."
            }
        }
    }
}

private final class FixturePageView: UIView {
    init(rendered: RenderedDocument, scale: CGFloat) {
        super.init(frame: CGRect(origin: .zero, size: rendered.size))
        backgroundColor = UIColor(cgColor: rendered.backgroundColor)
        let tiles = FixtureTileLayer(rendered: rendered)
        tiles.frame = bounds
        tiles.contentsScale = scale
        tiles.tileSize = CGSize(width: 512, height: 512)
        layer.addSublayer(tiles)
        isAccessibilityElement = true
        accessibilityLabel = rendered.text(in: rendered.documentRange)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// CATiledLayer calls draw(in:) on background threads. This layer retains only
/// an immutable Sendable snapshot; the callback never reads a UIView or UI state.
private final class FixtureTileLayer: CATiledLayer {
    private let rendered: RenderedDocument?

    init(rendered: RenderedDocument) {
        self.rendered = rendered
        super.init()
    }

    override init(layer: Any) {
        rendered = (layer as? FixtureTileLayer)?.rendered
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override class func fadeDuration() -> CFTimeInterval { 0 }

    override func draw(in context: CGContext) {
        rendered?.draw(in: context, rect: context.boundingBoxOfClipPath)
    }
}

#Preview { ContentView() }
