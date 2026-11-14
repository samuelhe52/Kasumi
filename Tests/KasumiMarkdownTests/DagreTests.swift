import CoreGraphics
import Testing
@testable import KasumiMarkdown

@Test func dagreNativeGeometryAndDirectionCrossTheCABI() throws {
    let nodes = [DagreNode(id: "a", width: 40, height: 20), DagreNode(id: "b", width: 40, height: 20)]
    let edges = [DagreEdge(id: "ab", source: "a", target: "b")]
    let horizontal = try DagreLayout.layout(nodes: nodes, edges: edges, options: .init(direction: .leftToRight))
    #expect(horizontal.size == CGSize(width: 130, height: 20))
    #expect(horizontal.nodes["a"]?.center == CGPoint(x: 20, y: 10))
    #expect(horizontal.nodes["b"]?.center == CGPoint(x: 110, y: 10))
    let path = try #require(horizontal.edges["ab"]?.points)
    #expect(path.first == CGPoint(x: 40, y: 10))
    #expect(path.last == CGPoint(x: 90, y: 10))
    let reversed = try DagreLayout.layout(nodes: nodes, edges: edges, options: .init(direction: .rightToLeft))
    #expect(reversed.nodes["a"]?.center.x == horizontal.nodes["b"]?.center.x)
    #expect(reversed.nodes["b"]?.center.x == horizontal.nodes["a"]?.center.x)
    let vertical = try DagreLayout.layout(nodes: nodes, edges: edges)
    #expect(vertical.size == CGSize(width: 40, height: 90))
    #expect(vertical.nodes["a"]?.center == CGPoint(x: 20, y: 10))
    #expect(vertical.nodes["b"]?.center == CGPoint(x: 20, y: 80))
}

@Test func dagreCompoundParallelAndSelfEdgesPreserveTheirIdentity() throws {
    let nodes = [DagreNode(id: "cluster", width: 0, height: 0),
                 DagreNode(id: "a", width: 60, height: 30, parentID: "cluster"),
                 DagreNode(id: "b", width: 60, height: 30, parentID: "cluster")]
    let edges = [DagreEdge(id: "first", source: "a", target: "b", labelWidth: 24, labelHeight: 12),
                 DagreEdge(id: "second", source: "a", target: "b"),
                 DagreEdge(id: "self", source: "b", target: "b")]
    let layout = try DagreLayout.layout(nodes: nodes, edges: edges)
    let cluster = try #require(layout.nodes["cluster"]?.rect)
    #expect(cluster.contains(try #require(layout.nodes["a"]?.rect)))
    #expect(cluster.contains(try #require(layout.nodes["b"]?.rect)))
    #expect(layout.edges.count == 3)
    #expect(try #require(layout.edges["first"]?.labelCenter).x.isFinite)
    #expect(layout.edges["first"]?.points != layout.edges["second"]?.points)
    #expect(try #require(layout.edges["self"]?.points.count) >= 4)
    #expect(layout.width.isFinite && layout.height.isFinite)
}

@Test func dagreRejectsMalformedInputWithoutTrappingOrLeakingAResult() throws {
    func rejects(_ nodes: [DagreNode], _ edges: [DagreEdge] = [], _ options: DagreOptions = .init()) {
        #expect(throws: DagreLayoutError.self) { try DagreLayout.layout(nodes: nodes, edges: edges, options: options) }
    }
    rejects([.init(id: "a", width: .nan, height: 20)])
    rejects([.init(id: "a", width: 20, height: -1)])
    rejects([.init(id: "a", width: 20, height: 20, parentID: "b"),
             .init(id: "b", width: 20, height: 20, parentID: "a")])
    rejects([.init(id: "a", width: 20, height: 20, parentID: "missing")])
    rejects([.init(id: "a", width: 20, height: 20), .init(id: "a", width: 20, height: 20)])
    rejects([.init(id: "a", width: 20, height: 20)], [.init(id: "ab", source: "a", target: "missing")])
    rejects([.init(id: "a", width: 20, height: 20)], [], .init(rankSeparation: .infinity))
    let empty = try DagreLayout.layout(nodes: [], edges: [])
    #expect(empty.nodes.isEmpty && empty.edges.isEmpty && empty.size == .zero)
}
