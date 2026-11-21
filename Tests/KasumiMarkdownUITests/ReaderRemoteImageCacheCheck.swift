import KasumiMarkdown
import KasumiMarkdownUI
import Foundation
import Testing

@MainActor func checkSameFileRemoteImageCache(
    _ reader: MarkdownReaderView, contentHeight: @escaping () -> CGFloat
) async throws {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="80" height="160"><rect width="80" height="160" fill="red"/></svg>"#
    let resource = try MarkdownImageResource(encodedData: Data(svg.utf8))
    let provider = RemoteImageCounter()
    let images = MarkdownRemoteImages { _ in
        await provider.countRequest()
        return resource
    }
    let source = "![Figure](https://example.invalid/figure.svg)"
    let url = URL(fileURLWithPath: "/tmp/reader-image-cache.md")
    var heights: [CGFloat] = []
    reader.onPositionChange = { _, _ in heights.append(contentHeight()) }
    defer { reader.onPositionChange = nil }
    reader.setRemoteImages(images)
    reader.setDocument(MarkdownDocument(markdown: "Before edit.\n\n" + source), url: url)
    for _ in 0..<300 {
        if let first = heights.first, contentHeight() > first + 80 { break }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    let placeholderHeight = try #require(heights.first)
    let resolvedHeight = contentHeight()
    try #require(resolvedHeight > placeholderHeight + 80)
    #expect(provider.requests == 1)

    heights.removeAll()
    reader.setDocument(MarkdownDocument(markdown: "After edit.\n\n" + source), url: url)
    for _ in 0..<300 where heights.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
    #expect(heights.first == resolvedHeight)
    #expect(provider.requests == 1)

    reader.setRemoteImages(images, revision: 1)
    for _ in 0..<300 where provider.requests < 2 { try await Task.sleep(nanoseconds: 10_000_000) }
    #expect(provider.requests == 2)
}

@MainActor private final class RemoteImageCounter {
    private(set) var requests = 0
    func countRequest() { requests += 1 }
}
