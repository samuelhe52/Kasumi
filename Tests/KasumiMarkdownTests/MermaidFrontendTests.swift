import CryptoKit
import Testing

@testable import KasumiMarkdown

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

fileprivate struct FrontendReference: Decodable {
    var items: [Item]
    struct Item: Decodable {
        var name: String, source: String, source_sha256: String, result: Result
    }
    struct Result: Decodable {
        var status: Int, bounds: [Double], measurements: [Measurement], commands: [Command], paths: [[Double]]
        var fallback: Fallback
    }
    struct Fallback: Decodable { var reason: Int, line: Int }
    struct Measurement: Decodable {
        var text: String
        var role: Int
    }
    struct Command: Decodable {
        var kind: Int, role: Int, rect: [Double], stroke_width: Double, dash: [Double], path_range: [Int], text_ref: Int
    }
}
fileprivate func frontendFixture() throws -> FrontendReference {
    let root = testRepositoryURL
    return try JSONDecoder().decode(
        FrontendReference.self,
        from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/MermaidFrontend.core.json")))
}
fileprivate func frontendPathElements(_ path: CGPath) -> [[Double]] {
    var rows: [[Double]] = []
    path.applyWithBlock { pointer in
        let e = pointer.pointee
        switch e.type {
        case .moveToPoint: rows.append([0, e.points[0].x, e.points[0].y, 0, 0, 0, 0])
        case .addLineToPoint: rows.append([1, e.points[0].x, e.points[0].y, 0, 0, 0, 0])
        case .addCurveToPoint:
            rows.append([2, e.points[2].x, e.points[2].y, e.points[0].x, e.points[0].y, e.points[1].x, e.points[1].y])
        case .closeSubpath: rows.append([3, 0, 0, 0, 0, 0, 0])
        default: Issue.record("Unexpected quadratic flow edge")
        }
    }
    return rows
}

@Test func nativeDiagramFrontendFontGeometry() throws {
    let fixture = try frontendFixture()
    var typography = Typography()
    typography.latinFamily = "Helvetica"
    for item in fixture.items {
        #expect(
            SHA256.hash(data: Data(item.source.utf8)).map { String(format: "%02x", $0) }.joined() == item.source_sha256)
        let expected = item.result
        #expect(expected.status == 0, "\(item.name) must have completed native layout")
        guard expected.status == 0 else { continue }
        var differences: [String] = []
        func close(_ x: Double, _ y: Double, _ name: String) {
            if abs(x - y) > 0.003 { differences.append("\(name): \(x) vs \(y)") }
        }
        let scene = try MermaidTypesetter.layout(
            item.source, size: 14, fontFamily: "Helvetica", dark: false, textStyle: .native(typography))
        for (a, b) in zip([scene.bounds.minX, scene.bounds.minY, scene.bounds.maxX, scene.bounds.maxY], expected.bounds)
        { close(a, b, "bounds") }
        if scene.commands.count != expected.commands.count {
            differences.append("commands: \(scene.commands.count) vs \(expected.commands.count)")
        }
        for (index, pair) in zip(scene.commands, expected.commands).enumerated() {
            let (command, native) = pair
            switch command {
            case .text(let text, let box, let role), .coloredText(let text, let box, let role, _):
                let label = expected.measurements[native.text_ref]
                if text != label.text || role != label.role {
                    differences.append("text \(index): \(text) role\(role) vs \(label.text) role\(label.role)")
                }
                for (a, b) in zip([box.minX, box.minY, box.width, box.height], native.rect) {
                    close(a, b, "text rectangle \(index)")
                }
            case .roundRect(let box, _, _, _, let width, _), .ellipse(let box, _, _, let width):
                for (a, b) in zip([box.minX, box.minY, box.width, box.height], native.rect) {
                    close(a, b, "shape rectangle \(index)")
                }
                close(width, native.stroke_width, "stroke")
            case .path(let path, _, _, let width, _):
                close(width, native.stroke_width, "stroke")
                let rows = frontendPathElements(path)
                let ref = Array(expected.paths[native.path_range[0]..<native.path_range[0] + native.path_range[1]])
                if native.role == 24 {  // Equivalent native shape outlines may have different command ordering.
                    let referencePath = CGMutablePath()
                    for row in ref {
                        let point = CGPoint(x: row[1], y: row[2])
                        switch Int(row[0]) {
                        case 0: referencePath.move(to: point)
                        case 1: referencePath.addLine(to: point)
                        case 2:
                            referencePath.addCurve(
                                to: point, control1: CGPoint(x: row[3], y: row[4]),
                                control2: CGPoint(x: row[5], y: row[6]))
                        default: referencePath.closeSubpath()
                        }
                    }
                    let box = path.boundingBoxOfPath
                    let other = referencePath.boundingBoxOfPath
                    close(box.minX, other.minX, "node left")
                    close(box.maxX, other.maxX, "node right")
                    close(box.minY, other.minY, "node top")
                    close(box.maxY, other.maxY, "node bottom")
                } else {
                    if rows.count != ref.count { differences.append("path \(index) count") }
                    for (row, other) in zip(rows, ref) {
                        for (a, b) in zip(row, other) { close(a, b, "path \(index)") }
                    }
                }
            }
        }
        #expect(differences.isEmpty, "\(item.name): \(differences.prefix(12).joined(separator: "; "))")
    }
}
