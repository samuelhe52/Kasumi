import AppKit
import KasumiMarkdown
import SwiftUI

final class MacLicensesWindowController: NSWindowController {
    init() {
        let host = NSHostingController(rootView: MacLicenses())
        // The window owns its size; don't let SwiftUI's ideal size drive it.
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = "Open Source Licenses"
        window.tabbingMode = .disallowed
        window.isRestorable = false
        window.contentMinSize = NSSize(width: 560, height: 360)
        window.setContentSize(NSSize(width: 760, height: 540))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init() instead") }
}

private struct MacLicenses: View {
    private static let components = ThirdPartyNotices.components()
    @State private var selection = components.first?.id

    var body: some View {
        HSplitView {
            List(Self.components, selection: $selection) { component in
                Text(component.name)
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 300, maxHeight: .infinity)
            Group {
                if let component = Self.components.first(where: { $0.id == selection }) {
                    MacComponentNotices(component: component)
                        .id(component.id)
                } else {
                    ContentUnavailableView("No Component Selected", systemImage: "doc.text")
                }
            }
            .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
    }
}

private struct MacComponentNotices: View {
    let component: ThirdPartyNotices.Component
    @State private var documentID: String?

    var body: some View {
        let document = component.documents.first { $0.id == documentID } ?? component.documents.first
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(component.name).font(.headline)
                    if let version = component.version {
                        Text(version).foregroundStyle(.secondary)
                    }
                }
                Text(component.role)
                Text(component.license).foregroundStyle(.secondary)
                if let source = component.source, let url = URL(string: source) {
                    Link(source, destination: url)
                }
                if component.documents.count > 1 {
                    Picker("Notice", selection: Binding(get: { document?.id }, set: { documentID = $0 })) {
                        ForEach(component.documents) { Text($0.title).tag(Optional($0.id)) }
                    }
                    .fixedSize()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            Divider()
            if let document {
                MacNoticeText(document: document)
                    .id(document.id)
            }
        }
    }
}

/// An AppKit text view, because the largest notices are too long for a SwiftUI `Text`.
///
/// Give each document its own identity: the text loads once, when the view is made.
private struct MacNoticeText: NSViewRepresentable {
    let document: ThirdPartyNotices.Document

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isRichText = false
            textView.textContainerInset = NSSize(width: 11, height: 12)
            textView.string = ThirdPartyNotices.text(of: document) ?? "This notice could not be loaded."
            textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            textView.textColor = .textColor
            textView.setAccessibilityLabel(document.title)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}
}
