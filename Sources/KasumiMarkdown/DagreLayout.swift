import CDagre
import CoreGraphics

struct DagreNode: Sendable, Equatable {
    var id: String
    var width: Double
    var height: Double
    var parentID: String?
    init(id: String, width: Double, height: Double, parentID: String? = nil) {
        self.id = id
        self.width = width
        self.height = height
        self.parentID = parentID
    }
}

struct DagreEdge: Sendable, Equatable {
    enum LabelPosition: UInt32, Sendable { case center, left, right }
    var id: String
    var source: String
    var target: String
    var labelWidth: Double
    var labelHeight: Double
    var minLength: Int
    var weight: Int
    var labelPosition: LabelPosition
    var labelOffset: Double
    init(
        id: String, source: String, target: String, labelWidth: Double = 0,
        labelHeight: Double = 0, minLength: Int = 1, weight: Int = 1,
        labelPosition: LabelPosition = .center, labelOffset: Double = 10
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.labelWidth = labelWidth
        self.labelHeight = labelHeight
        self.minLength = minLength
        self.weight = weight
        self.labelPosition = labelPosition
        self.labelOffset = labelOffset
    }
}

struct DagreOptions: Sendable, Equatable {
    enum Direction: UInt32, Sendable { case topToBottom, bottomToTop, leftToRight, rightToLeft }
    enum Ranker: UInt32, Sendable { case networkSimplex, tightTree, longestPath }
    enum Alignment: UInt32, Sendable { case automatic, upperLeft, upperRight, lowerLeft, lowerRight }
    enum RankAlignment: UInt32, Sendable { case center, top, bottom }
    var direction: Direction
    var nodeSeparation: Double
    var rankSeparation: Double
    var edgeSeparation: Double
    var marginX: Double
    var marginY: Double
    var tieKeepFirst: Bool
    var ranker: Ranker
    var alignment: Alignment
    var rankAlignment: RankAlignment
    var greedyAcyclicer: Bool
    init(
        direction: Direction = .topToBottom, nodeSeparation: Double = 50,
        rankSeparation: Double = 50, edgeSeparation: Double = 20,
        marginX: Double = 0, marginY: Double = 0, tieKeepFirst: Bool = false,
        ranker: Ranker = .networkSimplex, alignment: Alignment = .automatic,
        rankAlignment: RankAlignment = .center, greedyAcyclicer: Bool = false
    ) {
        self.direction = direction
        self.nodeSeparation = nodeSeparation
        self.rankSeparation = rankSeparation
        self.edgeSeparation = edgeSeparation
        self.marginX = marginX
        self.marginY = marginY
        self.tieKeepFirst = tieKeepFirst
        self.ranker = ranker
        self.alignment = alignment
        self.rankAlignment = rankAlignment
        self.greedyAcyclicer = greedyAcyclicer
    }
}

struct DagreNodeLayout: Sendable, Equatable {
    let center: CGPoint
    let width: Double
    let height: Double
    var rect: CGRect { CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height) }
}

struct DagreEdgeLayout: Sendable, Equatable {
    let points: [CGPoint]
    let labelCenter: CGPoint?
}

struct DagreResult: Sendable, Equatable {
    let nodes: [String: DagreNodeLayout]
    let edges: [String: DagreEdgeLayout]
    let width: Double
    let height: Double
    var size: CGSize { CGSize(width: width, height: height) }
}

enum DagreLayoutError: Error, Sendable, Equatable {
    case invalidInput(String)
    case nativeFailure(Int32)
}

/// Native Sugiyama layout using the pinned Apache-2.0 Dagre Rust port.
/// Coordinates have a top-left origin and node coordinates describe centers.
/// Input order is preserved because it affects deterministic tie breaking.
enum DagreLayout {
    static func layout(nodes: [DagreNode], edges: [DagreEdge], options: DagreOptions = .init()) throws -> DagreResult {
        guard nodes.count <= 4096, edges.count <= 16384 else {
            throw DagreLayoutError.invalidInput("Graph exceeds 4096 nodes or 16384 edges")
        }
        var indices: [String: Int] = [:]
        for (i, node) in nodes.enumerated() {
            guard indices.updateValue(i, forKey: node.id) == nil else {
                throw DagreLayoutError.invalidInput("Duplicate node ID: \(node.id)")
            }
        }
        let nativeNodes = try nodes.map { node -> TDNodeInput in
            let parent: Int32
            if let parentID = node.parentID {
                guard let i = indices[parentID] else {
                    throw DagreLayoutError.invalidInput("Missing parent: \(parentID)")
                }
                parent = Int32(i)
            } else {
                parent = -1
            }
            return TDNodeInput(width: node.width, height: node.height, parent_index: parent)
        }
        var edgeIDs = Set<String>()
        let nativeEdges = try edges.map { edge -> TDEdgeInput in
            guard edgeIDs.insert(edge.id).inserted else {
                throw DagreLayoutError.invalidInput("Duplicate edge ID: \(edge.id)")
            }
            guard let source = indices[edge.source], let target = indices[edge.target],
                let minLength = Int32(exactly: edge.minLength), let weight = Int32(exactly: edge.weight)
            else {
                throw DagreLayoutError.invalidInput("Invalid edge endpoints or integer options: \(edge.id)")
            }
            return TDEdgeInput(
                source: UInt32(source), target: UInt32(target), label_width: edge.labelWidth,
                label_height: edge.labelHeight, label_offset: edge.labelOffset,
                min_length: minLength, weight: weight, label_position: edge.labelPosition.rawValue)
        }
        var nativeOptions = TDOptions(
            node_separation: options.nodeSeparation, edge_separation: options.edgeSeparation,
            rank_separation: options.rankSeparation, margin_x: options.marginX, margin_y: options.marginY,
            direction: options.direction.rawValue, tie_keep_first: options.tieKeepFirst ? 1 : 0,
            ranker: options.ranker.rawValue, alignment: options.alignment.rawValue,
            rank_alignment: options.rankAlignment.rawValue, greedy_acyclicer: options.greedyAcyclicer ? 1 : 0)
        var result: OpaquePointer?
        let status = nativeNodes.withUnsafeBufferPointer { n in
            nativeEdges.withUnsafeBufferPointer { e in
                td_dagre_layout(n.baseAddress, n.count, e.baseAddress, e.count, &nativeOptions, &result)
            }
        }
        guard status == 0, let result else {
            if status == 1 {
                throw DagreLayoutError.invalidInput("Invalid dimensions, options, or parent relationships")
            }
            throw DagreLayoutError.nativeFailure(status)
        }
        defer { td_dagre_result_free(result) }
        var outputNodes: [String: DagreNodeLayout] = [:]
        for (i, node) in nodes.enumerated() {
            var n = TDNodeOutput()
            guard td_dagre_result_node(result, i, &n) == 1 else { throw DagreLayoutError.nativeFailure(3) }
            outputNodes[node.id] = DagreNodeLayout(center: CGPoint(x: n.x, y: n.y), width: n.width, height: n.height)
        }
        var outputEdges: [String: DagreEdgeLayout] = [:]
        for (i, edge) in edges.enumerated() {
            var e = TDEdgeOutput()
            guard td_dagre_result_edge(result, i, &e) == 1 else { throw DagreLayoutError.nativeFailure(3) }
            var points: [CGPoint] = []
            points.reserveCapacity(e.point_count)
            for j in 0..<e.point_count {
                var p = TDPoint()
                guard td_dagre_result_point(result, i, j, &p) == 1 else { throw DagreLayoutError.nativeFailure(3) }
                points.append(CGPoint(x: p.x, y: p.y))
            }
            outputEdges[edge.id] = DagreEdgeLayout(
                points: points, labelCenter: e.has_label_center != 0 ? CGPoint(x: e.label_x, y: e.label_y) : nil)
        }
        var size = TDPoint()
        guard td_dagre_result_size(result, &size) == 1 else { throw DagreLayoutError.nativeFailure(3) }
        return DagreResult(nodes: outputNodes, edges: outputEdges, width: size.x, height: size.y)
    }
}
