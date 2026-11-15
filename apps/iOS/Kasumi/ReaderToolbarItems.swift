import SwiftUI

/// Deletes the open document after a confirmation. The dialog's state stays
/// here, so the reader screen doesn't track it.
struct ReaderDeleteButton: View {
    let title: String
    let onConfirm: () -> Void
    @State private var confirming = false

    var body: some View {
        Button("Delete", systemImage: "trash") { confirming = true }
            .accessibilityIdentifier("reader-delete")
            .confirmationDialog(
                "Delete \(title)?", isPresented: $confirming, titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onConfirm)
            } message: {
                Text("This can't be undone.")
            }
    }
}

/// Opens the appearance panel: a popover on iPad, where `regular` is true, and
/// a sheet on iPhone, which the reader screen presents itself.
struct ReaderAppearanceButton: View {
    @Binding var isPresented: Bool
    let regular: Bool
    @Binding var presetID: String
    @Binding var pairID: String
    @Binding var fontSize: Double

    var body: some View {
        Button("Appearance", systemImage: "textformat.size") { isPresented = true }
            .accessibilityIdentifier("reader-appearance")
            .popover(
                isPresented: Binding(get: { isPresented && regular }, set: { isPresented = $0 })
            ) {
                AppearanceSettings(presetID: $presetID, pairID: $pairID, fontSize: $fontSize)
                    .frame(width: 360)
            }
    }
}
