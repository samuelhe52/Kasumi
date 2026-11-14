import AppKit
import Foundation
import Testing
@testable import KasumiMarkdown

private struct EntityReference: Decodable {
    var items: [Item]
    struct Item: Decodable { var name: String; var source: String; var result: Result }
    struct Result: Decodable {
        var status: Int; var bounds: [Double]; var fallback: Fallback
        var measurements: [Measurement]; var commands: [Command]; var paths: [[Double]]
    }
    struct Fallback: Decodable { var reason: Int; var line: Int }
    struct Measurement: Decodable { var text: String }
    struct Command: Decodable {
        var kind: Int; var role: Int; var rect: [Double]; var stroke_width: Double
        var path_range: [Int]; var text_ref: Int
    }
}

private func entityPathRows(_ path: CGPath) -> [[Double]] {
    var rows: [[Double]] = []
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        switch element.type {
        case .moveToPoint: rows.append([0, element.points[0].x, element.points[0].y, 0, 0, 0, 0])
        case .addLineToPoint: rows.append([1, element.points[0].x, element.points[0].y, 0, 0, 0, 0])
        case .addCurveToPoint: rows.append([2, element.points[2].x, element.points[2].y, element.points[0].x, element.points[0].y, element.points[1].x, element.points[1].y])
        case .closeSubpath: rows.append([3, 0, 0, 0, 0, 0, 0])
        default: Issue.record("Unexpected entity path element")
        }
    }
    return rows
}

/// Marker contours can begin at a different vertex or traverse in reverse.
/// Sample their full line/cubic contours, rather than accepting matching boxes.
private func entityContour(_ rows: [[Double]]) -> [CGPoint] {
    var point = CGPoint.zero, start = CGPoint.zero, samples: [CGPoint] = []
    for row in rows {
        let end = row[0] == 3 ? start : CGPoint(x: row[1], y: row[2])
        if row[0] == 0 { point = end; start = end; continue }
        for step in 0...32 {
            let t = Double(step) / 32, u = 1 - t
            if row[0] == 2 {
                samples.append(CGPoint(x: u*u*u*point.x + 3*u*u*t*row[3] + 3*u*t*t*row[5] + t*t*t*end.x,
                                       y: u*u*u*point.y + 3*u*u*t*row[4] + 3*u*t*t*row[6] + t*t*t*end.y))
            } else { samples.append(CGPoint(x: point.x*u + end.x*t, y: point.y*u + end.y*t)) }
        }
        point = end
    }
    return samples
}

@Test func nativeEntityClassAndERGeometry() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for filename in ["MermaidClass.core.json", "MermaidER.core.json"] {
        let reference = try JSONDecoder().decode(EntityReference.self,
            from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/" + filename)))
        for item in reference.items {
            let expected = item.result
            if expected.status != 0 {
                do {
                    _ = try MermaidEntities.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
                    Issue.record("\(item.name) unexpectedly parsed")
                } catch let error as MermaidError {
                    let native: MermaidError = expected.fallback.reason == 2 ? .unsupported(line: expected.fallback.line)
                        : expected.fallback.reason == 6 ? .empty : .syntax(line: expected.fallback.line)
                    #expect(error == native, "\(item.name) diagnostic")
                }
                continue
            }
            let actual = try MermaidEntities.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
            func near(_ a: CGFloat, _ b: Double, _ label: String) { #expect(abs(a-b) < 0.002, "\(item.name) \(label): \(a) != \(b)") }
            func rect(_ a: CGRect, _ b: [Double], _ label: String) {
                for (x, y) in zip([a.minX, a.minY, a.width, a.height], b) { near(x, y, label) }
            }
            rect(actual.bounds, [expected.bounds[0], expected.bounds[1], expected.bounds[2]-expected.bounds[0], expected.bounds[3]-expected.bounds[1]], "bounds")
            #expect(actual.commands.count == expected.commands.count, "\(item.name) command count")
            guard actual.commands.count == expected.commands.count else { continue }
            for (command, native) in zip(actual.commands, expected.commands) {
                switch command {
                case let .text(text, box, _), let .coloredText(text, box, _, _):
                    #expect(native.kind == 3, "\(item.name) text kind")
                    #expect(text == expected.measurements[native.text_ref].text, "\(item.name) text")
                    rect(box, native.rect, "text rect")
                case let .roundRect(box, _, _, _, width, _):
                    #expect(native.kind == 1, "\(item.name) rectangle kind")
                    rect(box, native.rect, "rectangle"); near(width, native.stroke_width, "stroke")
                case let .ellipse(box, _, _, width):
                    #expect(native.kind == 2, "\(item.name) ellipse kind")
                    rect(box, native.rect, "ellipse"); near(width, native.stroke_width, "stroke")
                case let .path(path, _, _, width, _):
                    #expect(native.kind == 0, "\(item.name) path kind"); near(width, native.stroke_width, "stroke")
                    var box = CGRect.null
                    let start = native.path_range[0], count = native.path_range[1]
                    for element in expected.paths[start..<(start+count)] where element[0] != 3 {
                        box = box.union(CGRect(x: element[1], y: element[2], width: 0, height: 0))
                        if element[0] == 2 {
                            box = box.union(CGRect(x: element[3], y: element[4], width: 0, height: 0))
                            box = box.union(CGRect(x: element[5], y: element[6], width: 0, height: 0))
                        }
                    }
                    rect(path.boundingBox, [box.minX, box.minY, box.width, box.height], "path bounds")
                    let elements = entityPathRows(path)
                    let nativeElements = Array(expected.paths[start..<(start+count)])
                    if native.role == 20 || native.role == 28 {
                        #expect(elements.count == nativeElements.count, "\(item.name) path element count")
                        for (a, b) in zip(elements, nativeElements) {
                            for (x, y) in zip(a, b) { near(x, y, "path coordinate") }
                        }
                    } else {
                        let actualPoints = entityContour(elements)
                        var nativePoints = entityContour(nativeElements)
                        #expect(actualPoints.count == nativePoints.count, "\(item.name) marker contour samples")
                        for point in actualPoints {
                            let match = nativePoints.firstIndex { abs($0.x-point.x) < 0.002 && abs($0.y-point.y) < 0.002 }
                            #expect(match != nil, "\(item.name) marker contour at \(point)")
                            if let match { nativePoints.remove(at: match) }
                        }
                    }
                }
            }
        }
    }
}
