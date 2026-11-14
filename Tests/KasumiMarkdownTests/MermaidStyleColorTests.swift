import Foundation
import Testing
@testable import KasumiMarkdown

private struct StyleColorReference: Decodable {
    var items: [Item]
    struct Item: Decodable {
        var color: String
        var channel: String
        var paint: Paint
    }
    struct Paint: Decodable {
        var fill: Int
        var stroke: Int
        var fill_tint: Int
        var stroke_tint: Int
    }
}

@Test func styleColorsMatchNativeKeywordHueShadeAlphaAndChannelObservations() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let reference = try JSONDecoder().decode(StyleColorReference.self,
        from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/MermaidStyleColor.core.json")))
    #expect(reference.items.count > 700)
    for item in reference.items {
        let channel = try #require(MermaidStyleColor.Channel(rawValue: item.channel))
        let paint = channel == .stroke ? item.paint.stroke : item.paint.fill
        let tint = channel == .stroke ? item.paint.stroke_tint : item.paint.fill_tint
        let expected: MermaidStyleColor.Selection = paint == 0 ? .transparent : tint == 0 ? .themeDefault : .tint(tint)
        #expect(MermaidStyleColor.parse(item.color, channel: channel) == expected, "\(item.channel): \(item.color)")
    }
}

@Test func styleColorUnknownValuesPreserveThemeSelection() {
    for value in ["", "not a color", "#12gg34", "#12345", "ＦＦ００００", "rgb(255,0,0)"] {
        for channel in MermaidStyleColor.Channel.allCases {
            #expect(MermaidStyleColor.parse(value, channel: channel) == .themeDefault)
        }
    }
}
