#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Foundation
import Testing
@testable import KasumiMarkdown

private struct StateReferenceFile: Decodable { var items: [StateReferenceCase] }
private struct StateReferenceCase: Decodable {
    var name: String; var source: String; var result: StateReferenceResult
}
private struct StateReferenceResult: Decodable {
    struct Measurement: Decodable { var text: String; var role: Int }
    struct Fallback: Decodable { var reason: Int; var line: Int }
    struct Command: Decodable {
        var kind: Int; var role: Int; var rect: [Double]; var radii: [Double]
        var stroke_width: Double; var dash: [Double]; var path_range: [Int]; var text_ref: Int
    }
    var kind: Int; var status: Int; var bounds: [Double]; var commands: [Command]
    var measurements: [Measurement]; var paths: [[Double]]; var fallback: Fallback
}
private func stateReference(_ name: String) throws -> StateReferenceFile {
    let root = testRepositoryURL
    return try JSONDecoder().decode(StateReferenceFile.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/\(name).core.json")))
}
private func statePath(_ path: CGPath) -> [[Double]] {
    var result: [[Double]] = []
    path.applyWithBlock { pointer in
        let e = pointer.pointee
        switch e.type {
        case .moveToPoint: result.append([0, e.points[0].x, e.points[0].y, 0, 0, 0, 0])
        case .addLineToPoint: result.append([1, e.points[0].x, e.points[0].y, 0, 0, 0, 0])
        case .addCurveToPoint: result.append([2, e.points[2].x, e.points[2].y, e.points[0].x, e.points[0].y, e.points[1].x, e.points[1].y])
        case .closeSubpath: result.append([3, 0, 0, 0, 0, 0, 0])
        case .addQuadCurveToPoint: result.append([4])
        @unknown default: result.append([-1])
        }
    }
    return result
}
private func stateDifferences(_ scene: MermaidScene, _ reference: StateReferenceResult) -> [String] {
    var differences: [String] = []
    func compare(_ a: [Double], _ b: [Double], _ context: String) {
        if a.count != b.count || zip(a, b).contains(where: { abs($0 - $1) > 0.001 }) { differences.append("\(context): \(a) vs \(b)") }
    }
    func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
    compare([scene.bounds.minX, scene.bounds.minY, scene.bounds.maxX, scene.bounds.maxY], reference.bounds, "bounds")
    if scene.commands.count != reference.commands.count { differences.append("command count \(scene.commands.count) vs \(reference.commands.count)") }
    for (index, pair) in zip(scene.commands, reference.commands).enumerated() {
        let (actual, expected) = pair
        switch actual {
        case let .text(value, r, role), let .coloredText(value, r, role, _):
            if expected.kind != 3 { differences.append("command \(index) text vs kind \(expected.kind)"); continue }
            if value != reference.measurements[expected.text_ref].text || role != reference.measurements[expected.text_ref].role { differences.append("command \(index) text/role \(value)/\(role)") }
            compare(rect(r), expected.rect, "command \(index) text \(value)")
        case let .roundRect(r, radius, _, _, width, _):
            if expected.kind != 1 { differences.append("command \(index) rectangle vs kind \(expected.kind)"); continue }
            compare(rect(r) + [radius, width], expected.rect + [expected.radii[0], expected.stroke_width], "command \(index) rectangle")
        case let .ellipse(r, _, _, width):
            if expected.kind != 2 { differences.append("command \(index) ellipse vs kind \(expected.kind)"); continue }
            compare(rect(r) + [width], expected.rect + [expected.stroke_width], "command \(index) ellipse")
        case let .path(path, _, _, width, dash):
            if expected.kind != 0 { differences.append("command \(index) path vs kind \(expected.kind)"); continue }
            compare([Double(width)] + (dash.isEmpty ? [0, 0] : dash.map(Double.init)), [expected.stroke_width] + expected.dash, "command \(index) stroke")
            let points = statePath(path)
            let native = Array(reference.paths[expected.path_range[0]..<(expected.path_range[0] + expected.path_range[1])])
            if points.count != native.count { differences.append("command \(index) path count \(points.count) vs \(native.count)") }
            for (i, point) in zip(points, native).enumerated() { compare(point.0, point.1, "command \(index) point \(i)") }
        }
    }
    return differences
}

@Test func stateFrozenReferenceGeometryMatchesEveryVectorAndTextCommand() throws {
    let reference = try stateReference("Diagrams")
    let cases = reference.items.filter { $0.result.kind == 3 && $0.result.status == 0 }
    #expect(cases.count == 1)
    for item in cases {
        let scene = try MermaidState.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
        let differences = stateDifferences(scene, item.result)
        if !differences.isEmpty { Issue.record("\(item.name): \(differences.prefix(8).joined(separator: "; "))") }
    }
}

@Test func stateExtendedNativeSyntaxGeometryAndFallbacks() throws {
    let reference = try stateReference("MermaidState")
    for item in reference.items {
        if item.result.status == 0 {
            let scene = try MermaidState.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
            let differences = stateDifferences(scene, item.result)
            if !differences.isEmpty { Issue.record("\(item.name): \(differences.prefix(8).joined(separator: "; "))") }
        } else if item.result.fallback.reason == 2 {
            #expect(throws: MermaidError.unsupported(line: item.result.fallback.line)) {
                try MermaidState.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
            }
        } else if item.result.fallback.reason == 6 {
            #expect(throws: MermaidError.empty) {
                try MermaidState.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
            }
        } else if item.result.fallback.reason == 3 {
            #expect(throws: MermaidError.syntax(line: item.result.fallback.line)) {
                try MermaidState.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
            }
        }
    }
}
