import KasumiMarkdown
import SwiftUI

/// Every third-party component Kasumi distributes, with the notices it requires.
struct OpenSourceLicensesView: View {
    private let components = ThirdPartyNotices.components()

    var body: some View {
        List {
            Section {
                Text("Kasumi is released under the MIT License. It is built with the open-source components below.")
            }
            Section {
                ForEach(components) { component in
                    NavigationLink {
                        ComponentNoticesView(component: component)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(component.name)
                            Text(component.license)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("license-\(component.id)")
                }
            }
        }
        .navigationTitle("Open Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
        .softTopScrollEdge()
    }
}

private struct ComponentNoticesView: View {
    let component: ThirdPartyNotices.Component

    var body: some View {
        List {
            Section {
                if let version = component.version {
                    LabeledContent("Version", value: version)
                }
                LabeledContent("License", value: component.license)
                Text(component.role)
                if let source = component.source, let url = URL(string: source) {
                    Link(source, destination: url)
                }
            }
            Section("Notices") {
                ForEach(component.documents) { document in
                    NavigationLink(document.title) {
                        NoticeTextView(document: document)
                    }
                }
            }
        }
        .navigationTitle(component.name)
        .navigationBarTitleDisplayMode(.inline)
        .softTopScrollEdge()
    }
}

private struct NoticeTextView: View {
    let document: ThirdPartyNotices.Document

    var body: some View {
        ScrollView {
            Text(ThirdPartyNotices.text(of: document) ?? "This notice could not be loaded.")
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .softTopScrollEdge()
    }
}
