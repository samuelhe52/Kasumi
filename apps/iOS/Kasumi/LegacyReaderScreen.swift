import SwiftUI

struct LegacyReaderScreen: View {
    let configuration: ReferenceFileDocumentConfiguration<ReferenceReaderDocument>

    var body: some View {
        let model = configuration.document.model(
            fileURL: configuration.fileURL, isEditable: configuration.isEditable)
        ReaderScreen(document: model)
            .id(model.id)
            // The document host restores its bar on foregrounding unless the
            // scene's reader root requests that it stay hidden.
            .toolbarVisibility(usesLegacyToolbar ? .hidden : .automatic, for: .navigationBar)
            .onChange(of: configuration.fileURL) { _, url in model.setFileURL(url) }
            .onChange(of: configuration.isEditable) { _, isEditable in model.isEditable = isEditable }
    }

    private var usesLegacyToolbar: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }
}
