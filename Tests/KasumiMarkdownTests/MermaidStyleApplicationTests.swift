import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

fileprivate struct StyleApplicationReference: Decodable {
    var items: [Item]
    struct Item: Decodable { var name: String, source: String, result: Result }
    struct Result: Decodable {
        var status: Int, bounds: [Double], commands: [Command], paths: [[Double]], measurements: [Measurement],
            fallback: Fallback
    }
    struct Fallback: Decodable { var reason: Int, line: Int }
    struct Measurement: Decodable {
        var text: String
        var role: Int
    }
    struct Command: Decodable {
        var kind: Int, role: Int, fill: Int, stroke: Int, fill_tint: Int, stroke_tint: Int
        var rect: [Double], stroke_width: Double, dash: [Double], path_range: [Int], text_ref: Int
    }
}
fileprivate func styleApplicationFixture() throws -> StyleApplicationReference {
    let root = testRepositoryURL
    return try JSONDecoder().decode(
        StyleApplicationReference.self,
        from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/StyleApplications.core.json")))
}
fileprivate func styleApplicationDifferences(
    _ scene: MermaidScene, _ native: StyleApplicationReference.Result, dark: Bool
) -> [String] {
    var differences: [String] = []
    func close(_ a: [Double], _ b: [Double], _ context: String) {
        if a.count != b.count || zip(a, b).contains(where: { abs($0 - $1) > 0.003 }) {
            differences.append("\(context): \(a) vs \(b)")
        }
    }
    func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
    func expectedColor(_ command: StyleApplicationReference.Command, stroke: Bool) -> CGColor? {
        let slot = stroke ? command.stroke : command.fill
        let tint = stroke ? command.stroke_tint : command.fill_tint
        if slot == 0 { return nil }
        if tint != 0 { return MermaidPalette.color(tint: tint, dark: dark) }
        if slot == 2 || [20, 21, 26].contains(command.role) { return MermaidPalette.text(dark: dark) }
        if stroke { return MermaidPalette.nodeStroke(dark: dark) }
        switch command.role {
        case 22: return MermaidPalette.labelBackground(dark: dark)
        case 8: return MermaidPalette.noteFill(dark: dark)
        case 27: return MermaidPalette.blockFill(dark: dark)
        default: return MermaidPalette.nodeFill(dark: dark)
        }
    }
    func color(_ actual: CGColor?, _ expected: CGColor?, _ context: String) {
        guard let a = actual?.kasumiSRGB, let b = expected?.kasumiSRGB else {
            if (actual == nil) != (expected == nil) { differences.append("\(context): paint presence") }
            return
        }
        close(
            [a.redComponent, a.greenComponent, a.blueComponent, a.alphaComponent],
            [b.redComponent, b.greenComponent, b.blueComponent, b.alphaComponent], context)
    }
    close([scene.bounds.minX, scene.bounds.minY, scene.bounds.maxX, scene.bounds.maxY], native.bounds, "bounds")
    if scene.commands.count != native.commands.count {
        differences.append("commands \(scene.commands.count) vs \(native.commands.count)")
    }
    for (i, pair) in zip(scene.commands, native.commands).enumerated() {
        let (command, ref) = pair
        switch command {
        case .text(let value, let box, let role), .coloredText(let value, let box, let role, _):
            guard ref.kind == 3 else {
                differences.append("text kind \(i)")
                continue
            }
            let measurement = native.measurements[ref.text_ref]
            if value != measurement.text || role != measurement.role {
                differences.append("text/role \(i): \(value)/\(role) vs \(measurement.text)/\(measurement.role)")
            }
            close(rect(box), ref.rect, "text box \(i)")
            if case .coloredText(_, _, _, let ink) = command {
                color(ink, expectedColor(ref, stroke: false), "ink \(i)")
            } else {
                color(MermaidPalette.text(dark: dark), expectedColor(ref, stroke: false), "ink \(i)")
            }
        case .roundRect(let box, _, let fill, let stroke, let width, let dash):
            guard ref.kind == 1 else {
                differences.append("rectangle kind \(i)")
                continue
            }
            close(rect(box), ref.rect, "box \(i)")
            close(
                [Double(width)] + (dash.isEmpty ? [0, 0] : dash.map(Double.init)), [ref.stroke_width] + ref.dash,
                "stroke \(i)")
            color(fill, expectedColor(ref, stroke: false), "fill \(i)")
            color(stroke, expectedColor(ref, stroke: true), "stroke color \(i)")
        case .ellipse(let box, let fill, let stroke, let width):
            close(rect(box), ref.rect, "ellipse \(i)")
            close([width], [ref.stroke_width], "width \(i)")
            color(fill, expectedColor(ref, stroke: false), "fill \(i)")
            color(stroke, expectedColor(ref, stroke: true), "stroke color \(i)")
        case .path(let path, let fill, let stroke, let width, let dash):
            guard ref.kind == 0 else {
                differences.append("path kind \(i)")
                continue
            }
            close(
                [Double(width)] + (dash.isEmpty ? [0, 0] : dash.map(Double.init)), [ref.stroke_width] + ref.dash,
                "stroke \(i)")
            color(fill, expectedColor(ref, stroke: false), "fill \(i)")
            color(stroke, expectedColor(ref, stroke: true), "stroke color \(i)")
            let points = Array(native.paths[ref.path_range[0]..<ref.path_range[0] + ref.path_range[1]]).filter {
                $0[0] != 3
            }
            if !points.isEmpty {
                close(
                    rect(path.boundingBoxOfPath),
                    [
                        points.map { $0[1] }.min()!, points.map { $0[2] }.min()!,
                        points.map { $0[1] }.max()! - points.map { $0[1] }.min()!,
                        points.map { $0[2] }.max()! - points.map { $0[2] }.min()!
                    ], "path bounds \(i)")
            }
        }
    }
    return differences
}

@Test func styleApplicationsMatchNativeCascadeGeometryFontsDashesAndPaint() throws {
    let reference = try styleApplicationFixture()
    var typography = Typography()
    typography.latinFamily = "Helvetica"
    for item in reference.items {
        if item.result.status == 0 {
            for dark in [false, true] {
                let scene = try MermaidTypesetter.layout(
                    item.source, size: 14, fontFamily: "Helvetica", dark: dark, textStyle: .native(typography))
                let differences = styleApplicationDifferences(scene, item.result, dark: dark)
                if !differences.isEmpty {
                    Issue.record("\(item.name) dark=\(dark): \(differences.prefix(6).joined(separator:"; "))")
                }
            }
        } else if item.result.fallback.reason == 2 {
            do {
                _ = try MermaidTypesetter.layout(
                    item.source, size: 14, fontFamily: "Helvetica", dark: false, textStyle: .native(typography))
                Issue.record("\(item.name): expected unsupported")
            } catch let error as MermaidError {
                if error != .unsupported(line: item.result.fallback.line) {
                    Issue.record("\(item.name): \(error) vs unsupported line \(item.result.fallback.line)")
                }
            }
        } else if item.result.fallback.reason == 3 {
            do {
                _ = try MermaidTypesetter.layout(
                    item.source, size: 14, fontFamily: "Helvetica", dark: false, textStyle: .native(typography))
                Issue.record("\(item.name): expected syntax")
            } catch let error as MermaidError {
                if error != .syntax(line: item.result.fallback.line) {
                    Issue.record("\(item.name): \(error) vs syntax line \(item.result.fallback.line)")
                }
            }
        }
    }
}
