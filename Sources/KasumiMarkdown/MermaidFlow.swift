import CoreGraphics
import Foundation

/// Mermaid's graph syntax is parsed here; Dagre only orders and positions the
/// resulting native graph. Labels never pass through HTML or a web renderer.
enum MermaidFlow {
    enum Shape {
        case rectangle, rounded, stadium, circle, doubleCircle, diamond, hexagon, cylinder, parallelogram,
            reverseParallelogram, trapezoid, inverseTrapezoid, subroutine, asymmetric
    }
    struct Node {
        var id: String, label: String
        var shape: Shape = .rectangle
        var parent: String?
        var group = false
        var appearance = MermaidStyle()
    }
    struct Edge {
        var source: String, target: String, label = ""
        var arrow = true, reverseArrow = false, dashed = false, thick = false
        var length = 1
        var appearance = MermaidStyle()
    }
    struct Graph {
        var nodes: [Node] = [], edges: [Edge] = []
        var direction: DagreOptions.Direction = .topToBottom
        var links: [String: String] = [:]
    }

    static func layout(
        source: String, size: CGFloat, fontFamily: String, dark: Bool, textStyle: MermaidTextStyle? = nil,
        theme: DocumentTheme? = nil
    ) throws -> MermaidScene {
        let palette = MermaidPalette(dark: dark, theme: theme)
        let textMetrics = textStyle ?? .uniform(size: size, fontFamily: fontFamily)
        let graph = try parse(source, dark: dark)
        let lines = graph.nodes.map { labelLines($0.label) }
        let measured = lines.enumerated().map { i, rows in
            rows.map { textMetrics.measure($0, role: graph.nodes[i].appearance.role(group: graph.nodes[i].group)) }
        }
        let labelSizes = measured.map {
            CGSize(width: $0.map(\.width).max() ?? 0, height: $0.reduce(0) { $0 + $1.height })
        }
        let dimensions = graph.nodes.enumerated().map { i, node in
            node.group ? CGSize.zero : nodeSize(labelSizes[i], shape: node.shape)
        }
        let edgeLines = graph.edges.map { labelLines($0.label) }
        let edgeMeasures = edgeLines.enumerated().map { i, rows in
            rows.map { textMetrics.measure($0, role: graph.edges[i].appearance.role()) }
        }
        let edgeSizes = edgeMeasures.map {
            CGSize(width: $0.map(\.width).max() ?? 0, height: $0.reduce(0) { $0 + $1.height })
        }
        let nodes = graph.nodes.enumerated().map { i, n in
            DagreNode(id: n.id, width: dimensions[i].width, height: dimensions[i].height, parentID: n.parent)
        }
        let edges = graph.edges.enumerated().filter { $0.element.source != $0.element.target }.map { i, e in
            DagreEdge(
                id: String(i), source: e.source, target: e.target,
                labelWidth: e.label.isEmpty ? 0 : edgeSizes[i].width,
                labelHeight: e.label.isEmpty ? 0 : edgeSizes[i].height,
                minLength: e.length, labelPosition: .center)
        }
        let nodeByID = Dictionary(uniqueKeysWithValues: graph.nodes.enumerated().map { ($0.element.id, $0.offset) })
        func rootGroup(_ id: String) -> String? {
            var parent = graph.nodes[nodeByID[id]!].parent
            var root = parent
            while let value = parent {
                root = value
                parent = graph.nodes[nodeByID[value]!].parent
            }
            return root
        }
        let independentClusters =
            graph.nodes.contains(where: \.group)
            && !graph.edges.contains { rootGroup($0.source) != rootGroup($0.target) }
        // Self-contained clusters use the core's separate direction/spacing
        // selection. An external edge brings them into the enclosing graph.
        let direction: DagreOptions.Direction =
            independentClusters ? (graph.direction == .topToBottom ? .leftToRight : .topToBottom) : graph.direction
        let horizontal = direction == .leftToRight || direction == .rightToLeft
        let outerHorizontal = graph.direction == .leftToRight || graph.direction == .rightToLeft
        let layout = try DagreLayout.layout(
            nodes: nodes, edges: edges,
            options: .init(
                direction: direction,
                rankSeparation: independentClusters ? (outerHorizontal ? 75 : 65) : horizontal ? 50 : 40, marginX: 8,
                marginY: 8, tieKeepFirst: true))
        var commands: [MermaidCommand] = []
        var links: [MermaidNodeLink] = []
        var bounds = CGRect.null
        func include(_ rect: CGRect) { bounds = bounds.union(rect) }
        // Clusters paint behind edges and nodes, in source nesting order.
        for (i, node) in graph.nodes.enumerated() where node.group {
            guard let rect = layout.nodes[node.id]?.rect else { continue }
            commands.append(
                .roundRect(
                    rect, radius: 0, fill: node.appearance.fill(dark: dark, fallback: nil, palette: palette),
                    stroke: node.appearance.stroke(dark: dark, fallback: palette.nodeStroke, palette: palette),
                    width: node.appearance.nodeWidth, dash: node.appearance.dash()))
            let label = labelSizes[i]
            let textRect = CGRect(
                x: rect.midX - label.width / 2, y: rect.minY, width: label.width, height: label.height)
            let role = node.appearance.role(group: true)
            if let color = node.appearance.text(dark: dark, palette: palette) {
                commands.append(.coloredText(node.label, textRect, role: role, color: color))
            } else {
                commands.append(.text(node.label, textRect, role: role))
            }
            if let target = graph.links[node.id] {
                links.append(
                    .init(
                        path: CGPath(rect: textRect, transform: nil), target: target,
                        labelCommands: (commands.count - 1)..<commands.count))
            }
            include(rect)
        }
        var labelCenters: [Int: CGPoint] = [:]
        for (i, edge) in graph.edges.enumerated() {
            guard let source = layout.nodes[edge.source], let target = layout.nodes[edge.target] else { continue }
            let sourceShape = graph.nodes[nodeByID[edge.source]!].shape
            let targetShape = graph.nodes[nodeByID[edge.target]!].shape
            var points: [CGPoint]
            if edge.source == edge.target {
                let major =
                    horizontal
                    ? CGPoint(x: direction == .rightToLeft ? -1 : 1, y: 0)
                    : CGPoint(x: 0, y: direction == .bottomToTop ? -1 : 1)
                let cross = horizontal ? CGPoint(x: 0, y: 1) : CGPoint(x: 1, y: 0)
                let extent = horizontal ? source.width / 2 : source.height / 2
                let spread = max(18, (horizontal ? edgeSizes[i].height : edgeSizes[i].width) / 2)
                let center = CGPoint(
                    x: source.center.x + major.x * (extent + 24), y: source.center.y + major.y * (extent + 24))
                let a = CGPoint(x: center.x - cross.x * spread, y: center.y - cross.y * spread)
                let b = CGPoint(x: center.x + cross.x * spread, y: center.y + cross.y * spread)
                points = [
                    intersection(source.rect, shape: sourceShape, toward: a), a, b,
                    intersection(source.rect, shape: sourceShape, toward: b)
                ]
                let gap = 4 + (horizontal ? edgeSizes[i].width : edgeSizes[i].height) / 2
                labelCenters[i] = CGPoint(x: center.x + major.x * gap, y: center.y + major.y * gap)
            } else {
                guard let routed = layout.edges[String(i)]?.points, routed.count >= 2 else { continue }
                points = routed
                points[0] = intersection(source.rect, shape: sourceShape, toward: points[1])
                points[points.count - 1] = intersection(
                    target.rect, shape: targetShape, toward: points[points.count - 2])
                labelCenters[i] = layout.edges[String(i)]?.labelCenter
            }
            for point in points { include(CGRect(origin: point, size: .zero)) }
            let end = points[points.count - 1]
            let start = points[0]
            if edge.arrow { points[points.count - 1] = offset(end, toward: points[points.count - 2], by: 4) }
            if edge.reverseArrow { points[0] = offset(start, toward: points[1], by: 4) }
            let path = basis(points)
            let edgeColor = edge.appearance.stroke(dark: dark, fallback: palette.edge, palette: palette)
            commands.append(
                .path(
                    path, fill: nil, stroke: edgeColor, width: edge.appearance.edgeWidth(default: edge.thick ? 3.5 : 1),
                    dash: edge.appearance.dash(default: edge.dashed ? [2, 2] : [])))
            if edge.arrow {
                commands.append(
                    .path(
                        arrow(tip: end, previous: points[points.count - 2]), fill: edgeColor, stroke: nil, width: 0,
                        dash: []))
            }
            if edge.reverseArrow {
                commands.append(
                    .path(arrow(tip: start, previous: points[1]), fill: edgeColor, stroke: nil, width: 0, dash: []))
            }
        }
        for (i, edge) in graph.edges.enumerated() where !edge.label.isEmpty {
            guard let center = labelCenters[i] else { continue }
            let dimensions = edgeSizes[i]
            let rect = CGRect(
                x: center.x - dimensions.width / 2, y: center.y - dimensions.height / 2, width: dimensions.width,
                height: dimensions.height)
            commands.append(.roundRect(rect, radius: 0, fill: palette.labelBackground, stroke: nil, width: 0))
            include(rect)
            var y = rect.minY
            for (j, text) in edgeLines[i].enumerated() {
                let m = edgeMeasures[i][j]
                let rect = CGRect(x: center.x - m.width / 2, y: y, width: m.width, height: m.height)
                let role = edge.appearance.role()
                if let color = edge.appearance.text(dark: dark, node: false, palette: palette) {
                    commands.append(.coloredText(text, rect, role: role, color: color))
                } else {
                    commands.append(.text(text, rect, role: role))
                }
                y += m.height
            }
        }
        for (i, node) in graph.nodes.enumerated() where !node.group {
            guard let rect = layout.nodes[node.id]?.rect else { continue }
            let path = nodePath(rect, shape: node.shape)
            commands.append(
                .path(
                    path, fill: node.appearance.fill(dark: dark, fallback: palette.nodeFill, palette: palette),
                    stroke: node.appearance.stroke(dark: dark, fallback: palette.nodeStroke, palette: palette),
                    width: node.appearance.nodeWidth, dash: node.appearance.dash()))
            include(rect)
            include(path.boundingBoxOfPath)
            let firstLabel = commands.count
            var y = rect.midY - labelSizes[i].height / 2 + (node.shape == .cylinder ? 10 : 0)
            for (j, text) in lines[i].enumerated() {
                let m = measured[i][j]
                let rect = CGRect(
                    x: rect.midX - m.width / 2 + (node.shape == .asymmetric ? rect.height / 8 : 0), y: y,
                    width: m.width, height: m.height)
                let role = node.appearance.role()
                if let color = node.appearance.text(dark: dark, palette: palette) {
                    commands.append(.coloredText(text, rect, role: role, color: color))
                } else {
                    commands.append(.text(text, rect, role: role))
                }
                y += m.height
            }
            if let target = graph.links[node.id] {
                links.append(.init(path: path, target: target, labelCommands: firstLabel..<commands.count))
            }
        }
        guard !bounds.isNull else { throw MermaidError.empty }
        return MermaidScene(bounds: bounds, commands: commands, theme: theme, links: links)
    }

    static func labelLines(_ source: String) -> [String] {
        guard !source.isEmpty else { return [] }
        return source.replacingOccurrences(
            of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive]
        ).components(separatedBy: "\n")
    }
    static func nodeSize(_ label: CGSize, shape: Shape) -> CGSize {
        let w = label.width
        let h = label.height
        switch shape {
        case .rectangle: return CGSize(width: w + 60, height: h + 30)
        case .rounded: return CGSize(width: w + 30, height: h + 30)
        case .circle: return CGSize(width: w + 15, height: max(w + 15, h))
        case .doubleCircle: return CGSize(width: w + 30, height: max(w + 30, h))
        case .diamond:
            let d = w + h + 30
            return CGSize(width: d, height: d)
        case .hexagon: return CGSize(width: w + 15 + (h + 15) / 2, height: h + 15)
        case .stadium:
            let height = h + 15
            // Native outlines sample each semicircle at 49 intervals. Its
            // extrema fall between samples, affecting the fitted width.
            return CGSize(width: w + 15 + height / 4 - height * (1 - cos(.pi / 98)), height: height)
        case .cylinder:
            let width = w + 15
            let ry = (width / 2) / (2.5 + width / 50)
            return CGSize(width: width, height: h + 15 + ry * 3)
        case .parallelogram, .reverseParallelogram, .trapezoid: return CGSize(width: w + 15 + h + 15, height: h + 15)
        case .inverseTrapezoid: return CGSize(width: w + 30 + h + 30, height: h + 30)
        case .subroutine: return CGSize(width: w + 31, height: h + 15)
        case .asymmetric: return CGSize(width: w + 15 + (h + 15) / 4, height: h + 15)
        }
    }
    static func nodePath(_ r: CGRect, shape: Shape) -> CGPath {
        let p = CGMutablePath()
        func polygon(_ points: [CGPoint]) {
            p.addLines(between: points)
            p.closeSubpath()
        }
        let x = r.minX
        let y = r.minY
        let w = r.width
        let h = r.height
        func pt(_ a: CGFloat, _ b: CGFloat) -> CGPoint { CGPoint(x: x + a, y: y + b) }
        switch shape {
        case .rectangle: p.addRect(r)
        case .rounded: p.addRoundedRect(in: r, cornerWidth: 5, cornerHeight: 5)
        case .stadium:
            let radius = h / 2
            let extent = radius * cos(.pi / 98)
            let a = x + extent
            let b = r.maxX - extent
            p.move(to: CGPoint(x: a, y: y))
            p.addLine(to: CGPoint(x: b, y: y))
            for i in 0...49 {
                let angle = -.pi / 2 + CGFloat(i) * .pi / 49
                p.addLine(to: CGPoint(x: b + radius * cos(angle), y: r.midY + radius * sin(angle)))
            }
            p.addLine(to: CGPoint(x: a, y: r.maxY))
            for i in 0...49 {
                let angle = .pi / 2 + CGFloat(i) * .pi / 49
                p.addLine(to: CGPoint(x: a + radius * cos(angle), y: r.midY + radius * sin(angle)))
            }
            p.closeSubpath()
        case .circle: p.addEllipse(in: CGRect(x: x, y: r.midY - w / 2, width: w, height: w))
        case .doubleCircle:
            let circle = CGRect(x: x, y: r.midY - w / 2, width: w, height: w)
            p.addEllipse(in: circle)
            p.addEllipse(in: circle.insetBy(dx: 5, dy: 5))
        case .diamond: polygon([pt(w / 2 + 0.5, h), pt(w + 0.5, h / 2), pt(w / 2 + 0.5, 0), pt(0.5, h / 2)])
        case .hexagon:
            polygon([pt(h / 4, h), pt(w - h / 4, h), pt(w, h / 2), pt(w - h / 4, 0), pt(h / 4, 0), pt(0, h / 2)])
        case .parallelogram: polygon([pt(0, h), pt(w - h / 2, h), pt(w, 0), pt(h / 2, 0)])
        case .reverseParallelogram: polygon([pt(h / 2, h), pt(w, h), pt(w - h / 2, 0), pt(0, 0)])
        case .trapezoid: polygon([pt(0, h), pt(w, h), pt(w - h / 2, 0), pt(h / 2, 0)])
        case .inverseTrapezoid: polygon([pt(h / 2, h), pt(w - h / 2, h), pt(w, 0), pt(0, 0)])
        case .subroutine:
            p.addRect(r)
            p.move(to: pt(8, 0))
            p.addLine(to: pt(8, h))
            p.move(to: pt(w - 8, 0))
            p.addLine(to: pt(w - 8, h))
        case .asymmetric: polygon([pt(0, 0), pt(h / 4, h / 2), pt(0, h), pt(w, h), pt(w, 0)])
        case .cylinder:
            let ry = (w / 2) / (2.5 + w / 50)
            p.addEllipse(in: CGRect(x: x, y: y, width: w, height: ry * 2))
            p.move(to: pt(0, ry))
            p.addLine(to: pt(0, h - ry))
            p.addCurve(
                to: pt(w / 2, h), control1: pt(0, h - ry + ry * 0.55228475), control2: pt(w / 2 - w / 2 * 0.55228475, h)
            )
            p.addCurve(
                to: pt(w, h - ry), control1: pt(w / 2 + w / 2 * 0.55228475, h),
                control2: pt(w, h - ry + ry * 0.55228475))
            p.addLine(to: pt(w, ry))
        }
        return p
    }
    static func offset(_ point: CGPoint, toward other: CGPoint, by distance: CGFloat) -> CGPoint {
        let dx = other.x - point.x
        let dy = other.y - point.y
        let length = hypot(dx, dy)
        return length > 0 ? CGPoint(x: point.x + dx / length * distance, y: point.y + dy / length * distance) : point
    }
    static func intersection(_ rect: CGRect, shape: Shape, toward target: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - center.x
        let dy = target.y - center.y
        guard abs(dx) + abs(dy) > 0 else { return center }
        let factor = min(
            dx == 0 ? .infinity : rect.width / 2 / abs(dx), dy == 0 ? .infinity : rect.height / 2 / abs(dy))
        var q = CGPoint(x: center.x + dx * factor, y: center.y + dy * factor)
        switch shape {
        case .rectangle, .rounded: return q
        case .circle, .doubleCircle:
            let radius = rect.width / 2
            let distance = hypot(dx, dy)
            return CGPoint(x: center.x + dx / distance * radius, y: center.y + dy / distance * radius)
        case .cylinder:
            let rx = rect.width / 2
            let ry = rx / (2.5 + rect.width / 50)
            let x = q.x - center.x
            if abs(x) < rx || (abs(x) == rx && abs(q.y - center.y) > rect.height / 2 - ry) {
                let correction = ry - sqrt(max(0, ry * ry * (1 - x * x / (rx * rx))))
                q.y += target.y > center.y ? -correction : correction
            }
            return q
        default:
            let path: CGPath
            if shape == .diamond {
                let p = CGMutablePath()
                p.addLines(between: [
                    CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                    CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)
                ])
                p.closeSubpath()
                path = p
            } else {
                path = nodePath(rect, shape: shape)
            }
            var segments: [(CGPoint, CGPoint)] = []
            var first: CGPoint?
            var previous: CGPoint?
            path.applyWithBlock { pointer in
                let element = pointer.pointee
                switch element.type {
                case .moveToPoint:
                    first = element.points[0]
                    previous = first
                case .addLineToPoint:
                    let next = element.points[0]
                    if let previous { segments.append((previous, next)) }
                    previous = next
                case .closeSubpath:
                    if let first, let previous { segments.append((previous, first)) }
                    previous = first
                default: break
                }
            }
            var nearest: CGPoint?
            var best = CGFloat.infinity
            for (a, b) in segments {
                let ex = b.x - a.x
                let ey = b.y - a.y
                let determinant = dx * ey - dy * ex
                guard abs(determinant) > 1e-10 else { continue }
                let ax = a.x - center.x
                let ay = a.y - center.y
                let t = (ax * ey - ay * ex) / determinant
                let u = (ax * dy - ay * dx) / determinant
                guard t >= 0, u >= -1e-8, u <= 1 + 1e-8 else { continue }
                let point = CGPoint(x: center.x + t * dx, y: center.y + t * dy)
                let distance = hypot(point.x - target.x, point.y - target.y)
                if distance < best {
                    best = distance
                    nearest = point
                }
            }
            if var point = nearest {
                // The native determinant solver adds a signed half point. Its
                // diamond adapter compensates for that offset explicitly.
                point.x += point.x < 0 ? -0.5 : 0.5
                point.y += point.y < 0 ? -0.5 : 0.5
                if shape == .diamond {
                    point.x -= 0.5
                    point.y -= 0.5
                }
                return point
            }
            return q
        }
    }
    static func arrow(tip: CGPoint, previous: CGPoint) -> CGPath {
        let back = offset(tip, toward: previous, by: 8)
        let dx = back.x - tip.x
        let dy = back.y - tip.y
        let p = CGMutablePath()
        p.addLines(between: [
            tip, CGPoint(x: back.x + dy / 2, y: back.y - dx / 2), CGPoint(x: back.x - dy / 2, y: back.y + dx / 2)
        ])
        p.closeSubpath()
        return p
    }
    /// Uniform cubic B-spline, matching the reference's basis edge interpolation.
    static func basis(_ points: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        guard let first = points.first else { return p }
        p.move(to: first)
        guard points.count > 2 else {
            if let last = points.last { p.addLine(to: last) }
            return p
        }
        func mix(_ a: CGPoint, _ aw: CGFloat, _ b: CGPoint, _ bw: CGFloat, _ c: CGPoint = .zero, _ cw: CGFloat = 0)
            -> CGPoint
        { CGPoint(x: a.x * aw + b.x * bw + c.x * cw, y: a.y * aw + b.y * bw + c.y * cw) }
        p.addLine(to: mix(first, 5 / 6, points[1], 1 / 6))
        for i in 1..<points.count - 1 {
            p.addCurve(
                to: mix(points[i - 1], 1 / 6, points[i], 4 / 6, points[i + 1], 1 / 6),
                control1: mix(points[i - 1], 2 / 3, points[i], 1 / 3),
                control2: mix(points[i - 1], 1 / 3, points[i], 2 / 3))
        }
        let a = points[points.count - 2]
        let b = points[points.count - 1]
        p.addCurve(to: mix(a, 1 / 6, b, 5 / 6), control1: mix(a, 2 / 3, b, 1 / 3), control2: mix(a, 1 / 3, b, 2 / 3))
        p.addLine(to: b)
        return p
    }

    static func parse(_ source: String, dark: Bool) throws -> Graph {
        var graph = Graph()
        var indices: [String: Int] = [:]
        var parents: [String] = []
        var classes: [String: MermaidStyle] = [:]
        var assignments: [(String, String, Int)] = []
        var explicitStyles: [(String, String)] = []
        var defaultLinks: [MermaidStyle] = []
        var indexedLinks: [(Int, MermaidStyle)] = []
        let statements = try splitStatements(source)
        guard let first = statements.first else { throw MermaidError.empty }
        let header = first.0.split(whereSeparator: \.isWhitespace)
        guard header.count == 2, ["graph", "flowchart"].contains(String(header[0])) else {
            throw MermaidError.syntax(line: 1)
        }
        switch header[1] {
        case "TB", "TD": graph.direction = .topToBottom
        case "BT": graph.direction = .bottomToTop
        case "LR": graph.direction = .leftToRight
        case "RL": graph.direction = .rightToLeft
        default: throw MermaidError.syntax(line: 1)
        }
        func store(_ node: Node, explicit: Bool) {
            if let i = indices[node.id] {
                if explicit {
                    graph.nodes[i].label = node.label
                    graph.nodes[i].shape = node.shape
                }
                if graph.nodes[i].parent == nil { graph.nodes[i].parent = node.parent }
            } else {
                indices[node.id] = graph.nodes.count
                graph.nodes.append(node)
            }
        }
        for (statement, line) in statements.dropFirst() {
            var scanner = Scanner(statement, line: line)
            if statement == "end" {
                guard !parents.isEmpty else { throw MermaidError.syntax(line: line) }
                parents.removeLast()
                continue
            }
            if statement.hasPrefix("subgraph ") {
                scanner.index = 9
                scanner.skip()
                var (node, _) = try scanner.node(parent: parents.last)
                node.group = true
                scanner.skip()
                if !scanner.done { throw MermaidError.unsupported(line: line) }
                if indices[node.id] != nil || parents.count >= 24 { throw MermaidError.syntax(line: line) }
                store(node, explicit: true)
                parents.append(node.id)
                continue
            }
            if statement.hasPrefix("classDef ") {
                let rest = String(statement.dropFirst(9))
                guard let space = rest.firstIndex(where: \.isWhitespace) else { throw MermaidError.syntax(line: line) }
                try MermaidStyle.validateFlow(String(rest[space...]), line: line)
                for name in rest[..<space].split(separator: ",") {
                    classes[String(name), default: MermaidStyle()].apply(String(rest[space...]))
                }
                continue
            }
            if statement.hasPrefix("class ") {
                let pieces = statement.dropFirst(6).split(whereSeparator: \.isWhitespace)
                guard pieces.count == 2 else { throw MermaidError.syntax(line: line) }
                for id in pieces[0].split(separator: ",") { assignments.append((String(id), String(pieces[1]), line)) }
                continue
            }
            if statement.hasPrefix("style ") {
                let rest = String(statement.dropFirst(6))
                guard let space = rest.firstIndex(where: \.isWhitespace) else { throw MermaidError.syntax(line: line) }
                let id = String(rest[..<space])
                store(Node(id: id, label: id, parent: parents.last), explicit: false)
                try MermaidStyle.validateFlow(String(rest[space...]), line: line)
                explicitStyles.append((id, String(rest[space...])))
                continue
            }
            if statement.hasPrefix("click ") {
                if let (id, target) = MermaidNodeLink.parse(statement.dropFirst(6)),
                    MermaidNodeLink.isSafeTarget(target)
                {
                    graph.links[id] = target
                }
                continue
            }
            if statement.hasPrefix("linkStyle ") {
                let rest = String(statement.dropFirst(10))
                guard let space = rest.firstIndex(where: \.isWhitespace) else { throw MermaidError.syntax(line: line) }
                try MermaidStyle.validateFlow(String(rest[space...]), line: line)
                let selector = String(rest[..<space])
                var appearance = MermaidStyle()
                appearance.apply(String(rest[space...]))
                if selector == "default" {
                    defaultLinks.append(appearance)
                } else {
                    for token in selector.split(separator: ",", omittingEmptySubsequences: false) {
                        guard let i = Int(token), graph.edges.indices.contains(i) else {
                            throw MermaidError.syntax(line: line)
                        }
                        indexedLinks.append((i, appearance))
                    }
                }
                continue
            }
            if statement.hasPrefix("direction ") { throw MermaidError.unsupported(line: line) }
            var left: [String] = []
            repeat {
                let (node, explicit) = try scanner.node(parent: parents.last)
                store(node, explicit: explicit)
                left.append(node.id)
                if let name = scanner.className() { assignments.append((node.id, name, line)) }
                scanner.skip()
                if scanner.consume("&") { continue }
                break
            } while true
            while !scanner.done {
                var edge = try scanner.edge()
                var right: [String] = []
                repeat {
                    let (node, explicit) = try scanner.node(parent: parents.last)
                    store(node, explicit: explicit)
                    right.append(node.id)
                    if let name = scanner.className() { assignments.append((node.id, name, line)) }
                    scanner.skip()
                    if scanner.consume("&") { continue }
                    break
                } while true
                for a in left {
                    for b in right {
                        edge.source = a
                        edge.target = b
                        graph.edges.append(edge)
                    }
                }
                left = right
                guard graph.edges.count <= 4096 else { throw MermaidError.tooLarge }
            }
            guard graph.nodes.count <= 1024 else { throw MermaidError.tooLarge }
        }
        guard parents.isEmpty else { throw MermaidError.syntax(line: statements.last?.1 ?? 1) }
        if let defaults = classes["default"] {
            for i in graph.nodes.indices where !graph.nodes[i].group { graph.nodes[i].appearance.merge(defaults) }
        }
        for (id, name, _) in assignments {
            if let i = indices[id], let definition = classes[name] { graph.nodes[i].appearance.merge(definition) }
        }
        for (id, source) in explicitStyles { if let i = indices[id] { graph.nodes[i].appearance.apply(source) } }
        for appearance in defaultLinks { for i in graph.edges.indices { graph.edges[i].appearance.merge(appearance) } }
        for (i, appearance) in indexedLinks { graph.edges[i].appearance.merge(appearance) }
        guard !graph.nodes.isEmpty else { throw MermaidError.empty }
        return graph
    }
    static func splitStatements(_ source: String) throws -> [(String, Int)] {
        var result: [(String, Int)] = []
        var buffer = ""
        var line = 1
        var start = 1
        var stack: [Character] = []
        var quote: Character?
        var escaped = false
        var comment = false
        var pipe = false
        let characters = Array(source)
        for i in characters.indices {
            let c = characters[i]
            if comment {
                if c != "\n" { continue }
                comment = false
            }
            if quote != nil {
                buffer.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == quote { quote = nil }
            } else if c == "\"" || c == "'" && !stack.isEmpty {
                quote = c
                buffer.append(c)
            } else if c == "%" && i + 1 < characters.count && characters[i + 1] == "%" && stack.isEmpty && !pipe {
                comment = true
                continue
            } else if c == "|" && stack.isEmpty {
                pipe.toggle()
                buffer.append(c)
            } else if (c == "\n" || c == ";") && stack.isEmpty && !pipe {
                let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.append((text, start)) }
                buffer = ""
                start = line + (c == "\n" ? 1 : 0)
            } else {
                if ["[", "(", "{"].contains(c) {
                    stack.append(c)
                } else if ["]", ")", "}"].contains(c) {
                    let expected: Character = c == "]" ? "[" : c == ")" ? "(" : "{"
                    if stack.last == expected {
                        stack.removeLast()
                    } else if c != "]" {
                        throw MermaidError.syntax(line: line)
                    }
                }
                buffer.append(c)
            }
            if c == "\n" { line += 1 }
        }
        guard stack.isEmpty, quote == nil, !pipe else { throw MermaidError.syntax(line: line) }
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { result.append((text, start)) }
        return result
    }
    struct Scanner {
        let chars: [Character], line: Int
        var index = 0
        init(_ source: String, line: Int) {
            chars = Array(source)
            self.line = line
        }
        var done: Bool { index >= chars.count }
        mutating func skip() { while !done && chars[index].isWhitespace { index += 1 } }
        func has(_ token: String) -> Bool {
            let t = Array(token)
            return index + t.count <= chars.count && Array(chars[index..<index + t.count]) == t
        }
        @discardableResult mutating func consume(_ token: String) -> Bool {
            guard has(token) else { return false }
            index += token.count
            return true
        }
        mutating func className() -> String? {
            guard consume(":::") else { return nil }
            let start = index
            while !done && !chars[index].isWhitespace && chars[index] != "&" { index += 1 }
            return String(chars[start..<index])
        }
        mutating func node(parent: String?) throws -> (Node, Bool) {
            skip()
            let start = index
            while !done && !chars[index].isWhitespace && !"[({>&|:;".contains(chars[index]) && !has("--") && !has("==")
                && !has("-.") && !has("<")
            { index += 1 }
            guard index > start else { throw MermaidError.syntax(line: line) }
            let id = String(chars[start..<index])
            var node = Node(id: id, label: id, parent: parent)
            skip()
            let shapes: [(String, String, Shape)] = [
                ("(((", ")))", .doubleCircle), ("((", "))", .circle), ("([", "])", .stadium), ("[(", ")]", .cylinder),
                ("[[", "]]", .subroutine), ("{{", "}}", .hexagon), ("[/", "/]", .parallelogram),
                ("[\\", "\\]", .reverseParallelogram), ("[/", "\\]", .trapezoid), ("[\\", "/]", .inverseTrapezoid),
                ("[", "]", .rectangle), ("(", ")", .rounded), ("{", "}", .diamond), (">", "]", .asymmetric)
            ]
            // Slash shapes share an opener; select their actual closing token.
            var candidates = shapes.filter { has($0.0) }
            if has("[/") || has("[\\") {
                candidates = candidates.filter { candidate in
                    let suffix = String(chars[index...])
                    return suffix.contains(candidate.1)
                }
            }
            guard let shape = candidates.first else { return (node, false) }
            index += shape.0.count
            let labelStart = index
            var quote: Character?
            var escaped = false
            while !done {
                let c = chars[index]
                if let q = quote {
                    if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == q { quote = nil }
                } else if c == "\"" || c == "'" {
                    quote = c
                } else if has(shape.1) {
                    break
                }
                index += 1
            }
            guard !done else { throw MermaidError.syntax(line: line) }
            var label = String(chars[labelStart..<index])
            index += shape.1.count
            if label.count >= 2, let first = label.first, let last = label.last, first == "\"" || first == "'",
                first == last
            {
                label = String(label.dropFirst().dropLast())
            }
            guard !label.isEmpty else { throw MermaidError.syntax(line: line) }
            guard label.utf8.count <= 2048 else { throw MermaidError.tooLarge }
            node.label = label
            node.shape = shape.2
            return (node, true)
        }
        mutating func edge() throws -> Edge {
            skip()
            var edge = Edge(source: "", target: "")
            let remaining = String(chars[index...])
            let match = remaining.range(of: "^<?(?:-\\.+-|={2,}|-{2,})>?", options: .regularExpression)
            let token = match.map { String(remaining[$0]) }
            if let token,
                token.hasSuffix(">") || token.filter({ $0 == "-" || $0 == "=" }).count >= 3 || token.contains(".")
            {
                index += token.count
                edge.arrow = token.hasSuffix(">")
                edge.reverseArrow = token.hasPrefix("<")
                edge.dashed = token.contains(".")
                edge.thick = token.contains("=")
                edge.length =
                    edge.dashed
                    ? token.filter { $0 == "." }.count
                    : max(1, token.filter { $0 == "-" || $0 == "=" }.count - (edge.arrow ? 1 : 2))
            } else if consume("--") {
                let start = index
                while !done && !has("-->") { index += 1 }
                guard !done else { throw MermaidError.syntax(line: line) }
                edge.label = String(chars[start..<index]).trimmingCharacters(in: .whitespaces)
                index += 3
            } else {
                throw MermaidError.unsupported(line: line)
            }
            skip()
            if consume("|") {
                let start = index
                while !done && !has("|") { index += 1 }
                guard consume("|") else { throw MermaidError.syntax(line: line) }
                edge.label = String(chars[start..<index - 1]).trimmingCharacters(in: .whitespaces)
            }
            guard edge.label.utf8.count <= 2048 else { throw MermaidError.tooLarge }
            skip()
            return edge
        }
    }
}
