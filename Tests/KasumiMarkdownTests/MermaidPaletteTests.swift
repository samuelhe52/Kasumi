#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import KasumiMarkdown

private struct NativeSeriesPalette: Decodable {
    var series: [Series]
    struct Series: Decodable {
        var name: String
        var light: Color
        var dark: Color
    }
    struct Color: Decodable { var rgba: [Double] }
}
@Test func diagramSeriesColorsMatchNativeInitializers() throws {
    let root = testRepositoryURL
    let snapshot = try JSONDecoder().decode(NativeSeriesPalette.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/MermaidPalette.json")))
    #expect(snapshot.series.count == 16)
    for (i, series) in snapshot.series.enumerated() {
        for dark in [false, true] {
            let color = try #require(MermaidPalette.color(tint: 28 + i, dark: dark).kasumiSRGB)
            let expected = dark ? series.dark.rgba : series.light.rgba
            for (a, b) in zip([color.redComponent,color.greenComponent,color.blueComponent,color.alphaComponent], expected) {
                #expect(abs(a-b) < 0.000001, "\(series.name) appearance \(dark)")
            }
        }
    }
}
