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
    private let page = FixturePageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(page)
        backgroundColor = page.style.paperColor
        alwaysBounceVertical = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        page.layout(width: bounds.width)
        contentSize = page.bounds.size
    }
}

private final class FixturePageView: UIView {
    let style = Typography().applying(BuiltinProfiles.all.first { $0.id == "serif" }?.effective ?? BuiltinProfiles.all[0].effective)
    private let document: ParsedDocument
    private var documentLayout: DocumentLayout?

    override init(frame: CGRect) {
        let url = Bundle.main.url(forResource: "Sample", withExtension: "md")!
        let source = try! String(contentsOf: url, encoding: .utf8)
        document = DocumentParser.parse(source)
        super.init(frame: frame)
        backgroundColor = style.paperColor
        isOpaque = true
        isAccessibilityElement = true
        accessibilityLabel = source
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func layout(width: CGFloat) {
        guard documentLayout?.width != width else { return }
        let layout = DocumentTypesetter.layout(document, width: width, style: style)
        documentLayout = layout
        frame = CGRect(x: 0, y: 0, width: width, height: ceil(layout.height))
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let documentLayout, let context = UIGraphicsGetCurrentContext() else { return }
        DocumentTypesetter.draw(documentLayout, in: context)
    }
}

#Preview { ContentView() }
