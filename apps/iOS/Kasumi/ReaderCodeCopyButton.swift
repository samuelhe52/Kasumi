import KasumiMarkdown
import UIKit

/// The renderer supplies block metadata; the reader owns this control's
/// placement, appearance, pasteboard action, and transient feedback.
final class ReaderCodeCopyButton: UIButton {
    private let block: RenderedCodeBlock
    private var resetTask: Task<Void, Never>?

    init(block: RenderedCodeBlock, frame: CGRect, color: UIColor) {
        self.block = block
        super.init(frame: frame)
        tintColor = color
        accessibilityIdentifier = "reader-code-copy-\(block.id)"
        accessibilityHint = String(localized: "Copies the entire code block without Markdown fences.")
        isEnabled = !block.source.isEmpty
        showCopied(false)
        addAction(UIAction { [weak self] _ in self?.copyCode() }, for: .primaryActionTriggered)
        if isEnabled {
            accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: String(localized: "Copy code block")) { [weak self] _ in
                    self?.copyCode() ?? false
                }
            ]
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { resetTask?.cancel() }

    @discardableResult func copyCode() -> Bool {
        guard isEnabled else { return false }
        UIPasteboard.general.string = block.source
        resetTask?.cancel()
        showCopied(true)
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Code copied"))
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.75))
            guard !Task.isCancelled else { return }
            self?.showCopied(false)
        }
        return true
    }

    private func showCopied(_ copied: Bool) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: copied ? "checkmark" : "doc.on.doc",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .regular))
        config.contentInsets = .zero
        config.baseForegroundColor = tintColor

        UIView.transition(with: self, duration: 0.2, options: [.transitionCrossDissolve, .allowAnimatedContent]) {
            self.configuration = config
            self.layoutIfNeeded()
        }

        accessibilityLabel =
            copied
            ? String(localized: "Copied code") : String(localized: "Copy code")
        accessibilityValue = block.language
    }
}
