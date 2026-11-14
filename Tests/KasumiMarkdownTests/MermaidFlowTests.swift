import AppKit
import CryptoKit
import Testing
@testable import KasumiMarkdown

private struct FlowReference: Decodable {
    var items: [Item]
    struct Item: Decodable {
        var name: String, source: String, source_sha256: String, result: Result
    }
    struct Result: Decodable {
        var status: Int, bounds: [Double], measurements: [Measurement], commands: [Command], paths: [[Double]]
        var fallback: Fallback
    }
    struct Fallback: Decodable { var reason: Int, line: Int }
    struct Measurement: Decodable { var text: String }
    struct Command: Decodable {
        var kind: Int, role: Int, rect: [Double], stroke_width: Double, dash: [Double], path_range: [Int], text_ref: Int
    }
}
private func flowFixture() throws -> FlowReference {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    var reference = try JSONDecoder().decode(FlowReference.self,from:Data(contentsOf:root.appendingPathComponent("fixtures/reference/Diagrams.core.json")))
    reference.items += try JSONDecoder().decode(FlowReference.self,from:Data(contentsOf:root.appendingPathComponent("fixtures/reference/MermaidFlow.core.json"))).items
    return reference
}
private func flowPathElements(_ path: CGPath) -> [[Double]] {
    var rows:[[Double]]=[]
    path.applyWithBlock { pointer in
        let e=pointer.pointee
        switch e.type {
        case .moveToPoint:rows.append([0,e.points[0].x,e.points[0].y,0,0,0,0])
        case .addLineToPoint:rows.append([1,e.points[0].x,e.points[0].y,0,0,0,0])
        case .addCurveToPoint:rows.append([2,e.points[2].x,e.points[2].y,e.points[0].x,e.points[0].y,e.points[1].x,e.points[1].y])
        case .closeSubpath:rows.append([3,0,0,0,0,0,0])
        default:Issue.record("Unexpected quadratic flow edge")
        }
    }
    return rows
}
@Test(arguments:["flow-lr","flow-tb","flow-shapes","flow-circle","flow-branch","flow-cycle","flow-subgraph","flow-label","flow-rl","flow-bt","flow-lr-short","flow-tb-short","flow-unconnected","flow-dashed","flow-unicode","flow-comment","flow-style","flow-classdef", "shape-rect","shape-rounded","shape-stadium","shape-circle","shape-doublecircle","shape-diamond","shape-hexagon","shape-cylinder","shape-parallelogram","shape-reverseparallelogram","shape-trapezoid","shape-inversetrapezoid","shape-subroutine","shape-asymmetric", "self","parallel","semicolon","compound","ampersand","longarrow","edgetext","quotedescape","subgraphtitle","click","nested","emptylabel","styles"])
func nativeFlowGeometry(_ name:String)throws {
    let fixture=try flowFixture()
    let item=try #require(fixture.items.first { $0.name==name })
    #expect(SHA256.hash(data:Data(item.source.utf8)).map { String(format:"%02x",$0) }.joined()==item.source_sha256)
    let expected=item.result
    if expected.status != 0 {
        do { _ = try MermaidTypesetter.layout(item.source,size:16,fontFamily:"Helvetica",dark:false); Issue.record("\(name) unexpectedly parsed") }
        catch let error as MermaidError {
            #expect(error == (expected.fallback.reason == 2 ? .unsupported(line: expected.fallback.line) : .syntax(line: expected.fallback.line)))
        }
        return
    }
    let actual=try MermaidTypesetter.layout(item.source,size:16,fontFamily:"Helvetica",dark:false)
    func close(_ x:CGFloat,_ y:Double,_ detail:String) { #expect(abs(x-y)<0.002,"\(name) \(detail): \(x) vs \(y)") }
    close(actual.bounds.minX,expected.bounds[0],"bounds left");close(actual.bounds.minY,expected.bounds[1],"bounds top")
    close(actual.bounds.maxX,expected.bounds[2],"bounds right");close(actual.bounds.maxY,expected.bounds[3],"bounds bottom")
    #expect(actual.commands.count==expected.commands.count,"\(name) command count")
    guard actual.commands.count==expected.commands.count else { return }
    var pathIndex=0
    for (command,native) in zip(actual.commands,expected.commands) {
        switch command {
        case let .text(text,rect,_),let .coloredText(text,rect,_,_):
            #expect(native.kind==3)
            #expect(text==expected.measurements[native.text_ref].text,"\(name) label")
            for (x,y) in zip([rect.minX,rect.minY,rect.width,rect.height],native.rect) { close(x,y,"text rectangle") }
        case let .roundRect(rect,_,_,_,width, _),let .ellipse(rect,_,_,width):
            for (x,y) in zip([rect.minX,rect.minY,rect.width,rect.height],native.rect) { close(x,y,"shape rectangle") };close(width,native.stroke_width,"stroke width")
        case let .path(path,_,_,width,dash):
            #expect(native.kind==0);close(width,native.stroke_width,"stroke width")
            let rows=flowPathElements(path)
            let ref=Array(expected.paths[native.path_range[0]..<native.path_range[0]+native.path_range[1]])
            // CoreGraphics rectangle emission may include an explicit final
            // segment in addition to close. Edges/arrowheads compare all points.
            if native.role==24 {
                let points=ref.filter { $0[0] != 3 }.map { CGPoint(x:$0[1],y:$0[2]) }
                let xs=points.map(\.x),ys=points.map(\.y)
                let box=path.boundingBoxOfPath
                close(box.minX,xs.min() ?? 0,"node left");close(box.maxX,xs.max() ?? 0,"node right")
                close(box.minY,ys.min() ?? 0,"node top");close(box.maxY,ys.max() ?? 0,"node bottom")
            } else {
                #expect(rows.count==ref.count,"\(name) path \(pathIndex) elements")
                for (row,other) in zip(rows,ref) { for (x,y) in zip(row,other) { close(x,y,"path \(pathIndex)") } }
            }
            #expect(dash.map(Double.init)==native.dash.filter { $0>0 },"\(name) dash")
            pathIndex+=1
        }
    }
}

@Test func mermaidDiagnosticsAndRenderingModePreserveSource()throws {
    #expect(throws:MermaidError.syntax(line:2)) { try MermaidTypesetter.layout("graph LR\nA[",size:16,fontFamily:"Helvetica",dark:false) }
    #expect(throws:MermaidError.unsupported(line:1)) { try MermaidTypesetter.layout("%%{init: {}}%%\ngraph LR\nA-->B",size:16,fontFamily:"Helvetica",dark:false) }
    #expect(throws:MermaidError.tooLarge) { try MermaidTypesetter.layout(String(repeating:"A",count:65_537),size:16,fontFamily:"Helvetica",dark:false) }
    let source="graph LR\nA[Find this] --> B[Finish]"
    let doc=DocumentParser.parse("```mermaid\n\(source)\n```")
    var style=Typography()
    let layout=DocumentTypesetter.layout(doc,width:400,style:style)
    #expect(layout.text.string.contains("\u{FFFC}"))
    #expect(layout.textMap.string.contains(source))
    #expect(layout.textMap.matches("Find this").count==1)
    #expect(layout.paginationGroups.count==1)
    style.mermaidEnabled=false
    let literal=DocumentTypesetter.layout(doc,width:400,style:style)
    #expect(!literal.text.string.contains("\u{FFFC}"))
    #expect(literal.textMap.string.contains(source))
    let fallback=DocumentTypesetter.layout(DocumentParser.parse("```mermaid\ngantt\nTask\n```"),width:400,style:Typography())
    #expect(fallback.textMap.string.contains("Mermaid · not rendered:"))
    #expect(fallback.textMap.string.contains("gantt\nTask"))
    let old=Data("{\"size\":21,\"latinFamily\":\"Charter\",\"dark\":true}".utf8)
    var migrated=try JSONDecoder().decode(Typography.self,from:old)
    #expect(migrated.size==21 && migrated.latinFamily=="Charter" && migrated.dark && migrated.mermaidEnabled)
    migrated.mermaidEnabled=false
    #expect(try JSONDecoder().decode(Typography.self,from:JSONEncoder().encode(migrated))==migrated)
}
