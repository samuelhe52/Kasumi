import Foundation
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

fileprivate struct SequenceReferenceFile: Decodable { var items: [SequenceReferenceCase] }
fileprivate struct SequenceReferenceCase: Decodable {
    var name: String
    var source: String
    var result: SequenceReferenceResult
}
fileprivate struct SequenceReferenceResult: Decodable {
    struct Measurement: Decodable {
        var text: String
        var role: Int
    }
    struct Fallback: Decodable {
        var reason: Int
        var line: Int
    }
    struct Command: Decodable {
        var kind: Int
        var role: Int
        var rect: [Double]
        var radii: [Double]
        var stroke_width: Double
        var dash: [Double]
        var path_range: [Int]
        var text_ref: Int
    }
    var kind: Int
    var status: Int
    var bounds: [Double]
    var commands: [Command]
    var measurements: [Measurement]
    var paths: [[Double]]
    var fallback: Fallback
}
fileprivate func sequenceReference(_ name: String) throws -> SequenceReferenceFile {
    let root = testRepositoryURL
    return try JSONDecoder().decode(
        SequenceReferenceFile.self,
        from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/\(name).core.json")))
}
fileprivate func sequencePath(_ path: CGPath) -> [[Double]] {
    var result: [[Double]] = []
    path.applyWithBlock { pointer in
        let e = pointer.pointee
        switch e.type {
        case .moveToPoint: result.append([0, e.points[0].x, e.points[0].y, 0, 0, 0, 0])
        case .addLineToPoint: result.append([1, e.points[0].x, e.points[0].y, 0, 0, 0, 0])
        case .addCurveToPoint:
            result.append([2, e.points[2].x, e.points[2].y, e.points[0].x, e.points[0].y, e.points[1].x, e.points[1].y])
        case .closeSubpath: result.append([3, 0, 0, 0, 0, 0, 0])
        case .addQuadCurveToPoint: result.append([4])
        @unknown default: result.append([-1])
        }
    }
    return result
}
fileprivate func sequenceDifferences(_ scene: MermaidScene, _ reference: SequenceReferenceResult) -> [String] {
    var differences: [String] = []
    func compare(_ a: [Double], _ b: [Double], _ context: String) {
        if a.count != b.count || zip(a, b).contains(where: { abs($0 - $1) > 0.001 }) {
            differences.append("\(context): \(a) vs \(b)")
        }
    }
    func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
    compare([scene.bounds.minX, scene.bounds.minY, scene.bounds.maxX, scene.bounds.maxY], reference.bounds, "bounds")
    if scene.commands.count != reference.commands.count {
        differences.append("command count \(scene.commands.count) vs \(reference.commands.count)")
    }
    for (index, pair) in zip(scene.commands, reference.commands).enumerated() {
        let (actual, expected) = pair
        switch actual {
        case .text(let value, let r, let role), .coloredText(let value, let r, let role, _):
            if expected.kind != 3 {
                differences.append("command \(index) text vs kind \(expected.kind)")
                continue
            }
            if value != reference.measurements[expected.text_ref].text
                || role != reference.measurements[expected.text_ref].role
            {
                differences.append("command \(index) text/role \(value)/\(role)")
            }
            compare(rect(r), expected.rect, "command \(index) text \(value)")
        case .roundRect(let r, let radius, _, _, let width, _):
            if expected.kind != 1 {
                differences.append("command \(index) rectangle vs kind \(expected.kind)")
                continue
            }
            compare(
                rect(r) + [radius, width], expected.rect + [expected.radii[0], expected.stroke_width],
                "command \(index) rectangle")
        case .ellipse(let r, _, _, let width):
            if expected.kind != 2 {
                differences.append("command \(index) ellipse vs kind \(expected.kind)")
                continue
            }
            compare(rect(r) + [width], expected.rect + [expected.stroke_width], "command \(index) ellipse")
        case .path(let path, _, _, let width, let dash):
            if expected.kind != 0 {
                differences.append("command \(index) path vs kind \(expected.kind)")
                continue
            }
            compare(
                [Double(width)] + (dash.isEmpty ? [0, 0] : dash.map(Double.init)),
                [expected.stroke_width] + expected.dash, "command \(index) stroke")
            let points = sequencePath(path)
            let native = Array(
                reference.paths[expected.path_range[0]..<(expected.path_range[0] + expected.path_range[1])])
            if points.count != native.count {
                differences.append("command \(index) path count \(points.count) vs \(native.count)")
            }
            for (i, point) in zip(points, native).enumerated() {
                compare(point.0, point.1, "command \(index) point \(i)")
            }
        }
    }
    return differences
}

@Test func sequenceFrozenReferenceGeometryMatchesEveryVectorAndTextCommand() throws {
    let reference = try sequenceReference("Diagrams")
    let cases = reference.items.filter { $0.result.kind == 2 && $0.result.status == 0 }
    #expect(cases.count == 4)
    for item in cases {
        let scene = try MermaidSequence.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
        let differences = sequenceDifferences(scene, item.result)
        #expect(differences.isEmpty, "\(item.name): \(differences.prefix(8).joined(separator: "; "))")
    }
}

@Test func sequenceExtendedNativeSyntaxGeometryAndFallbacks() throws {
    let reference = try sequenceReference("MermaidSequence")
    for item in reference.items {
        if item.result.status == 0 {
            let scene = try MermaidSequence.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
            let differences = sequenceDifferences(scene, item.result)
            #expect(differences.isEmpty, "\(item.name): \(differences.prefix(8).joined(separator: "; "))")
        } else if item.result.fallback.reason == 2 {
            #expect(throws: MermaidError.unsupported(line: item.result.fallback.line)) {
                try MermaidSequence.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
            }
        } else if item.result.fallback.reason == 3 {
            #expect(throws: MermaidError.syntax(line: item.result.fallback.line)) {
                try MermaidSequence.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
            }
        }
    }
}

@Test func sequenceNativeFrontendRolesPreserveGeometryAcrossLabelsAndBadgeSizes() throws {
    let reference = try sequenceReference("MermaidSequenceFrontend")
    let shared = try sequenceReference("MermaidFrontend")
    var typography = Typography()
    typography.latinFamily = "Helvetica"
    // The multiline fragment completes after a second measurement round.
    #expect(reference.items.allSatisfy { $0.result.status != 5 })
    for item in reference.items + shared.items.filter({ $0.result.kind == 2 && $0.source.hasPrefix("sequenceDiagram") })
    where item.result.status == 0 {
        let scene = try MermaidSequence.layout(
            source: item.source, size: 14, fontFamily: "Helvetica", dark: false, textStyle: .native(typography))
        let differences = sequenceDifferences(scene, item.result)
        if !differences.isEmpty { Issue.record("\(item.name): \(differences.prefix(8).joined(separator:"; "))") }
    }
}
