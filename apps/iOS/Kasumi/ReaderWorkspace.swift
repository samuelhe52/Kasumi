import SwiftUI
import UIKit

/// Keeps both panes for the document session and only the active one in the window.
struct ReaderWorkspace<Reader: View>: UIViewControllerRepresentable {
    let reader: Reader
    let source: SourceEditor
    let showsSource: Bool
    let animated: Bool
    let paneDidAppear: () -> Void

    func makeUIViewController(context: Context) -> ReaderWorkspaceController<Reader> {
        ReaderWorkspaceController(reader: reader)
    }

    func updateUIViewController(_ controller: ReaderWorkspaceController<Reader>, context: Context) {
        controller.paneDidAppear = paneDidAppear
        controller.update(reader: reader, source: source, showsSource: showsSource, animated: animated)
    }
}

final class ReaderWorkspaceController<Reader: View>: UIViewController {
    var paneDidAppear: () -> Void = {}
    private let reader: UIHostingController<Reader>
    private var source: UIHostingController<SourceEditor>?
    private var activePane: UIViewController?
    private var pendingSwitch: Task<Void, Never>?

    init(reader: Reader) {
        self.reader = Self.host(reader)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(reader:) instead") }

    override func viewDidLoad() {
        super.viewDidLoad()
        attach(reader)
    }

    func update(reader: Reader, source: SourceEditor, showsSource: Bool, animated: Bool) {
        self.reader.rootView = reader
        self.source?.rootView = source
        if showsSource, self.source == nil { self.source = Self.host(source) }
        let pane: UIViewController? = showsSource ? self.source : self.reader
        pendingSwitch?.cancel()
        guard let pane, isViewLoaded, activePane !== pane else { return }
        // Swapping panes can change first responder and Find, which must not
        // happen while SwiftUI is updating.
        pendingSwitch = Task { [weak self] in
            guard !Task.isCancelled else { return }
            self?.show(pane, animated: animated)
        }
    }

    private func show(_ pane: UIViewController, animated: Bool) {
        let swap = {
            // Only the crossfade animates; layout and scrolling are in place before it.
            UIView.performWithoutAnimation {
                self.attach(pane)
                // The pane takes its document and insets before it is positioned.
                self.view.layoutIfNeeded()
                self.paneDidAppear()
            }
        }
        if animated, view.window != nil {
            UIView.transition(
                with: view, duration: 0.24,
                options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction], animations: swap)
        } else {
            swap()
        }
    }

    private func attach(_ pane: UIViewController) {
        activePane?.willMove(toParent: nil)
        activePane?.view.removeFromSuperview()
        activePane?.removeFromParent()

        addChild(pane)
        pane.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pane.view)
        NSLayoutConstraint.activate([
            pane.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pane.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pane.view.topAnchor.constraint(equalTo: view.topAnchor),
            pane.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pane.didMove(toParent: self)
        activePane = pane
    }

    private static func host<Content: View>(_ content: Content) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content)
        // The workspace sizes each pane. Its UIKit scroll view handles insets
        // and the editor uses a keyboard layout guide inside the pane.
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        return host
    }
}
