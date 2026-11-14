#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Foundation
import Testing
@testable import KasumiMarkdown

private struct ThemeDiagramReference: Decodable {
    var items: [Item]
    struct Item: Decodable { var name: String, source: String; var result: Result }
    struct Result: Decodable { var status: Int; var commands: [Command]; var fallback: Fallback }
    struct Fallback: Decodable { var reason: Int }
    struct Command: Decodable { var role: Int, fill: Int, stroke: Int, fill_tint: Int, stroke_tint: Int }
}

// Reference diagram paint slots. These are role
// identities, independent of coincidentally equal RGBA values in any theme.
private let themeNativeSlots: [[String?]] = [
    ["diagram_node_fill", "diagram_node_stroke", nil], // actor box
    ["diagram_node_fill", "diagram_node_stroke", nil], // actor figure
    [nil, nil, "text"], [nil, "diagram_node_stroke", nil],
    [nil, nil, "text"], [nil, nil, "text"], [nil, nil, "text"],
    ["diagram_node_fill", "diagram_node_stroke", nil],
    ["diagram_note_fill", "diagram_node_stroke", nil], [nil, nil, "text"],
    [nil, "diagram_node_stroke", nil], ["diagram_node_fill", "diagram_node_stroke", nil],
    [nil, nil, "text"], [nil, nil, "text"], ["diagram_block_fill", nil, nil],
    [nil, nil, "text"], [nil, nil, "diagram_badge_text"], [nil, nil, "text"],
    ["diagram_node_fill", "diagram_node_stroke", nil], [nil, nil, "text"],
    [nil, "text", nil], ["text", "text", nil],
    ["diagram_edge_label_background", nil, nil], [nil, nil, "text"],
    ["diagram_node_fill", "diagram_node_stroke", nil], [nil, nil, "text"],
    [nil, nil, "text"], ["diagram_block_fill", nil, nil],
    [nil, "diagram_node_stroke", nil], ["diagram_edge_label_background", nil, nil]
]

private func themeTintKey(_ tint: Int) -> String {
    if tint <= 24 {
        let accents = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"]
        return "diagram_accent_\(accents[(tint - 1) / 3])_\(["tint", "mid", "deep"][(tint - 1) % 3])"
    }
    switch tint {
    case 25: return "diagram_accent_neutral_mid"
    case 26: return "diagram_accent_neutral_deep"
    case 27: return "diagram_accent_ink"
    case 28...35: return "diagram_series_\(tint - 27)_fill"
    case 36...43: return "diagram_series_\(tint - 35)_edge"
    default: return "diagram_series_ink"
    }
}

private func themeRGBA(_ color: CGColor?) -> [Double]? {
    guard let color = color?.kasumiSRGB else { return nil }
    return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
}

@Test func themeDiagramsUseNativePaintSlotsAcrossAllEightThemes() throws {
    let root = testRepositoryURL
    let fixtureNames = ["MermaidFrontend", "MermaidSequenceFrontend", "MermaidFlow", "MermaidState", "MermaidClass", "MermaidER", "MermaidPie", "MermaidTree"]
    let cases = try fixtureNames.flatMap { name -> [(ThemeDiagramReference.Item, String)] in
        let reference = try JSONDecoder().decode(ThemeDiagramReference.self,
            from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/\(name).core.json")))
        return reference.items.filter { $0.result.status == 0 && $0.result.fallback.reason == 0 }.map { ($0, name) }
    }
    var typography = Typography(); typography.latinFamily = "Helvetica"
    for catalogTheme in DocumentThemeCatalog.themes {
        let theme = DocumentThemeCatalog.resolved(id: catalogTheme.id, dark: catalogTheme.dark)
        for (item, fixture) in cases {
            let scene: MermaidScene
            // Core fixtures exercise their engine directly. In particular,
            // state core accepts init comments which the native frontend rejects.
            do {
                switch fixture {
                case "MermaidFlow": scene = try MermaidFlow.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: theme.dark, theme: theme)
                case "MermaidState": scene = try MermaidState.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: theme.dark, theme: theme)
                case "MermaidClass", "MermaidER": scene = try MermaidEntities.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: theme.dark, theme: theme)
                case "MermaidPie": scene = try MermaidPie.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: theme.dark, theme: theme)
                case "MermaidTree": scene = try MermaidTree.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: theme.dark, theme: theme)
                default: scene = try MermaidTypesetter.layout(item.source, size: 14, fontFamily: "Helvetica", dark: theme.dark, textStyle: .native(typography), theme: theme)
                }
            }
            catch { Issue.record("\(theme.id) \(item.name): \(error); source=\(item.source)"); continue }
            #expect(scene.theme == theme)
            #expect(scene.commands.count == item.result.commands.count)
            for (index, pair) in zip(scene.commands, item.result.commands).enumerated() {
                let (command, native) = pair
                func expected(_ slot: Int, tint: Int, stroke: Bool) -> CGColor? {
                    guard slot != 0 else { return nil }
                    if tint != 0 { return theme.color(themeTintKey(tint))?.cgColor }
                    let channel = slot == 2 ? 2 : stroke ? 1 : 0
                    return themeNativeSlots[native.role][channel].flatMap { theme.color($0)?.cgColor }
                }
                let fill: CGColor?, stroke: CGColor?
                switch command {
                case let .path(_, a, b, _, _), let .roundRect(_, _, a, b, _, _), let .ellipse(_, a, b, _): fill = a; stroke = b
                case .text: fill = theme.color("text")?.cgColor; stroke = nil
                case let .coloredText(_, _, _, color): fill = color; stroke = nil
                }
                #expect(themeRGBA(fill) == themeRGBA(expected(native.fill, tint: native.fill_tint, stroke: false)), "\(theme.id) \(item.name) command\(index) role\(native.role) fill")
                #expect(themeRGBA(stroke) == themeRGBA(expected(native.stroke, tint: native.stroke_tint, stroke: true)), "\(theme.id) \(item.name) command\(index) role\(native.role) stroke")
            }
        }
    }
}

private func themeGeometry(_ scene: MermaidScene) -> [String] {
    var result = [String(describing: scene.bounds)]
    for command in scene.commands {
        switch command {
        case let .path(path, _, _, width, dash):
            var points: [String] = []
            path.applyWithBlock { pointer in
                let element = pointer.pointee
                let count = element.type == .addCurveToPoint ? 3 : element.type == .addQuadCurveToPoint ? 2 : element.type == .closeSubpath ? 0 : 1
                points.append("\(element.type.rawValue):" + (0..<count).map { String(describing: element.points[$0]) }.joined(separator: ","))
            }
            result.append("path \(width) \(dash) \(points)")
        case let .roundRect(rect, radius, _, _, width, dash): result.append("rect \(rect) \(radius) \(width) \(dash)")
        case let .ellipse(rect, _, _, width): result.append("ellipse \(rect) \(width)")
        case let .text(text, rect, role), let .coloredText(text, rect, role, _): result.append("text \(text) \(rect) \(role)")
        }
    }
    return result
}

@Test func themeDiagramsPreserveGeometryAndResolveAuthoredAccentChannels() throws {
    let sources = [
        "graph LR\nA[Start] -->|edge| B[End]\nstyle A fill:#ffdddd,stroke:#0000ff,color:#ff0000",
        "stateDiagram-v2\nA --> B: next\nclassDef hot fill:#ffdddd,stroke:#0000ff,color:#ff0000\nclass A hot",
        "sequenceDiagram\nautonumber\nA->>B: Hello\nnote over A: Note",
        "classDiagram\nA --> B\nA: +field", "erDiagram\nA ||--o{ B : owns",
        "pie\n\"A\": 2\n\"B\": 1", "mindmap\n Root\n  Branch", "treeView-beta\n root\n  child"
    ]
    for source in sources {
        let original = try MermaidTypesetter.layout(source, size: 16, fontFamily: "Helvetica", dark: false)
        for catalogTheme in DocumentThemeCatalog.themes {
            let theme = DocumentThemeCatalog.resolved(id: catalogTheme.id, dark: catalogTheme.dark)
            let scene = try MermaidTypesetter.layout(source, size: 16, fontFamily: "Helvetica", dark: theme.dark, theme: theme)
            #expect(themeGeometry(scene) == themeGeometry(original), "\(theme.id): \(source)")
            let palette = MermaidPalette(dark: theme.dark, theme: theme)
            for tint in 1...44 { #expect(themeRGBA(palette.color(tint: tint)) == themeRGBA(theme.color(themeTintKey(tint))?.cgColor)) }
            if source.hasPrefix("graph") || source.hasPrefix("state") {
                #expect(scene.commands.contains { command in
                    if case let .coloredText(text, _, _, color) = command, text == (source.hasPrefix("graph") ? "Start" : "A") {
                        return themeRGBA(color) == themeRGBA(theme.color("diagram_accent_red_deep")?.cgColor)
                    }
                    return false
                })
            }
        }
    }
    let solarized = DocumentThemeCatalog.resolved(id: "solarized-light", dark: false)
    #expect(solarized.document["diagram_series_ink"] == DocumentColor(hex: "#073642"))
}

@Test func themeDiagramPlainTextDrawingRetainsItsOwnPalette() throws {
    func scene(_ id: String, _ color: DocumentColor) -> MermaidScene {
        MermaidScene(bounds: CGRect(x: 0, y: 0, width: 40, height: 30), commands: [
            .text("A", CGRect(x: 5, y: 5, width: 25, height: 20), role: 6)
        ], theme: DocumentTheme(id: id, name: id, appearance: .light, document: ["text": color]))
    }
    let red = scene("red", DocumentColor(red: 1, green: 0, blue: 0))
    let blue = scene("blue", DocumentColor(red: 0, green: 0, blue: 1))
    // Construct both before drawing: a shared mutable current palette would
    // incorrectly paint the first scene with the second scene's text color.
    for (scene, channel) in [(red, 0), (blue, 2), (red, 0)] {
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8,
            bytesPerRow: 160, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo))
        context.translateBy(x: 0, y: 30); context.scaleBy(x: 1, y: -1)
        scene.draw(in: context, size: 16, fontFamily: "Helvetica", dark: false)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var painted = 0
        for pixel in 0..<(40 * 30) where bytes[pixel * 4 + 3] > 0 {
            painted += 1
            #expect(bytes[pixel * 4 + channel] > 0)
            for other in 0...2 where other != channel { #expect(bytes[pixel * 4 + other] == 0) }
        }
        #expect(painted > 20)
    }
}
