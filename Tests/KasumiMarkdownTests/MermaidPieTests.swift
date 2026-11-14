#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Foundation
import Testing
@testable import KasumiMarkdown

private struct PieReference: Decodable {
    var items: [Item]
    struct Item: Decodable {
        var name: String
        var source: String
        var result: Result
    }
    struct Result: Decodable {
        var status: Int
        var bounds: [Double]
        var fallback: Fallback
        var measurements: [Measurement]
        var commands: [Command]
        var paths: [[Double]]
    }
    struct Fallback: Decodable { var reason: Int; var line: Int }
    struct Measurement: Decodable { var text: String }
    struct Command: Decodable {
        var kind: Int
        var rect: [Double]
        var radii: [Double]
        var stroke_width: Double
        var path_range: [Int]
        var text_ref: Int
    }
}

@Test func nativePieGeometryAndParserDiagnostics() throws {
    let root = testRepositoryURL
    let reference = try JSONDecoder().decode(PieReference.self,
        from: Data(contentsOf: root.appendingPathComponent("fixtures/reference/MermaidPie.core.json")))
    func close(_ actual: CGFloat, _ expected: Double, _ message: String) {
        #expect(abs(actual - expected) < 0.001, "\(message): \(actual) != \(expected)")
    }
    func rect(_ actual: CGRect, _ expected: [Double], _ message: String) {
        close(actual.minX, expected[0], message); close(actual.minY, expected[1], message)
        close(actual.width, expected[2], message); close(actual.height, expected[3], message)
    }
    for item in reference.items {
        let expected = item.result
        if expected.status != 0 {
            do {
                _ = try MermaidPie.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
                Issue.record("\(item.name) unexpectedly parsed")
            } catch let error as MermaidError {
                let native: MermaidError = expected.fallback.reason == 2
                    ? .unsupported(line: expected.fallback.line) : .syntax(line: expected.fallback.line)
                #expect(error == native, "\(item.name) diagnostic")
            }
            continue
        }
        let actual = try MermaidPie.layout(source: item.source, size: 16, fontFamily: "Helvetica", dark: false)
        rect(actual.bounds, [expected.bounds[0], expected.bounds[1], expected.bounds[2] - expected.bounds[0], expected.bounds[3] - expected.bounds[1]], item.name + " bounds")
        #expect(actual.commands.count == expected.commands.count, "\(item.name) command count")
        guard actual.commands.count == expected.commands.count else { continue }
        for (command, native) in zip(actual.commands, expected.commands) {
            switch command {
            case let .ellipse(box, _, _, width):
                #expect(native.kind == 2, "\(item.name) ellipse")
                rect(box, native.rect, item.name); close(width, native.stroke_width, item.name)
            case let .roundRect(box, radius, _, _, width, _):
                #expect(native.kind == 1, "\(item.name) rectangle")
                rect(box, native.rect, item.name); close(radius, native.radii[0], item.name)
                close(width, native.stroke_width, item.name)
            case let .text(text, box, _), let .coloredText(text, box, _, _):
                #expect(native.kind == 3, "\(item.name) text")
                #expect(text == expected.measurements[native.text_ref].text, "\(item.name) label")
                rect(box, native.rect, item.name)
            case let .path(path, _, _, width, _):
                #expect(native.kind == 0, "\(item.name) path")
                close(width, native.stroke_width, item.name)
                var elements: [[Double]] = []
                path.applyWithBlock { element in
                    let value = element.pointee
                    switch value.type {
                    case .moveToPoint: elements.append([0, value.points[0].x, value.points[0].y, 0, 0, 0, 0])
                    case .addLineToPoint: elements.append([1, value.points[0].x, value.points[0].y, 0, 0, 0, 0])
                    case .addCurveToPoint: elements.append([2, value.points[2].x, value.points[2].y, value.points[0].x, value.points[0].y, value.points[1].x, value.points[1].y])
                    case .closeSubpath: elements.append([3, 0, 0, 0, 0, 0, 0])
                    case .addQuadCurveToPoint: Issue.record("Unexpected quadratic pie arc")
                    @unknown default: Issue.record("Unexpected path element")
                    }
                }
                let start = native.path_range[0], count = native.path_range[1]
                let nativeElements = Array(expected.paths[start..<(start + count)])
                #expect(elements.count == nativeElements.count, "\(item.name) path element count")
                for (element, expectedElement) in zip(elements, nativeElements) {
                    for (coordinate, nativeCoordinate) in zip(element, expectedElement) {
                        close(coordinate, nativeCoordinate, item.name + " path")
                    }
                }
            }
        }
    }
}

@Test func pieLayoutRemainsMeasuredAndThemeAware() throws {
    let source = "pie showData title Values\n\"One\":1\n\"Two\":2"
    let small = try MermaidPie.layout(source: source, size: 12, fontFamily: "Helvetica", dark: false)
    let large = try MermaidPie.layout(source: source, size: 24, fontFamily: "Helvetica", dark: true)
    #expect(large.bounds.width > small.bounds.width)
    let firstFill: (MermaidScene) -> CGColor? = { scene in
        for command in scene.commands {
            if case let .path(_, fill, _, _, _) = command { return fill }
        }
        return nil
    }
    #expect(firstFill(small) != firstFill(large))
    #expect(throws: MermaidError.tooLarge) {
        _ = try MermaidPie.layout(source: String(repeating: "a", count: 65_537), size: 16, fontFamily: "Helvetica", dark: false)
    }
}
