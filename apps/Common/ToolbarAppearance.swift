import SwiftUI

extension View {
    @ViewBuilder
    func softTopScrollEdge() -> some View {
        #if os(iOS)
            if #available(iOS 26.0, *) {
                scrollEdgeEffectStyle(.soft, for: .top)
            } else {
                self
            }
        #else
            // The Mac app keeps the system's default edge effect.
            self
        #endif
    }
}
