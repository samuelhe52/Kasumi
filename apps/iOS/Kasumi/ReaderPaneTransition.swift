import UIKit

/// Animate UIKit content directly: SwiftUI opacity around the representables
/// did not produce a visible pane transition on the iPhone simulator.
@MainActor
enum ReaderPaneTransition {
    /// Interaction and accessibility are toggled here, not with SwiftUI's
    /// `allowsHitTesting`/`accessibilityHidden`: changing those re-parents the
    /// native view, which briefly loses its safe area and jumps its scroll offset.
    static func update(_ view: UIView, visible: Bool, reduceMotion: Bool) {
        view.isUserInteractionEnabled = visible
        view.accessibilityElementsHidden = !visible
        let alpha: CGFloat = visible ? 1 : 0
        guard view.alpha != alpha else { return }
        if reduceMotion || view.window == nil {
            view.layer.removeAnimation(forKey: "opacity")
            view.alpha = alpha
        } else {
            UIView.animate(
                withDuration: 0.24, delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
            ) {
                view.alpha = alpha
            }
        }
    }
}
