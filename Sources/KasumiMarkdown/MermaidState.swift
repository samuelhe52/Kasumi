import CoreGraphics
import Foundation

/// The reference's supported state subset uses a vertical graph, with an
/// independently laid-out compound graph for every nested state body.
enum MermaidState {
    private enum Kind { case state, start, end, choice, fork, group, note }
    private struct Node {
        var key: String, label: String, parent: String?
        var kind: Kind = .state
        var appearance = MermaidStyle()
    }
    private struct Edge {
        var from: String, to: String, parent: String?, label = ""
        var note = false
    }
    private struct Graph {
        var nodes: [Node] = []
        var edges: [Edge] = []
    }
    private struct Body {
        var size: CGSize
        var rects: [String: CGRect]
        var edges: [Int: [CGPoint]]
        var labels: [Int: CGPoint]
    }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
            let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }
    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func parse(_ source: String, dark: Bool) throws -> Graph {
        guard source.utf8.count <= 65_536 else { throw MermaidError.tooLarge }
        var graph = Graph()
        var indices: [String: Int] = [:]
        var scopes: [String] = []
        var classes: [String: MermaidStyle] = [:]
        var assignments: [(String, String, Int)] = []
        var explicitStyles: [(String, String, Int)] = []
        var groupLines: [String: Int] = [:]
        var header = false
        var note: (String, String, String, Int)?
        func key(_ id: String) -> String { (id.hasPrefix("$") ? (scopes.last ?? "") : "") + "/" + id }
        func store(_ id: String, kind: Kind = .state, label: String? = nil) throws -> String {
            let k = key(id)
            if let i = indices[k] {
                if kind != .state { graph.nodes[i].kind = kind }
                return k
            }
            guard graph.nodes.count < 1024 else { throw MermaidError.tooLarge }
            indices[k] = graph.nodes.count
            graph.nodes.append(Node(key: k, label: label ?? id, parent: scopes.last, kind: kind))
            return k
        }
        func endpoint(_ raw: String, start: Bool, line: Int) throws -> String {
            let pieces = raw.components(separatedBy: ":::")
            let id = trim(pieces[0])
            guard id == "[*]" || id.range(of: "^[\\p{L}\\p{N}_-]+$", options: .regularExpression) != nil else {
                throw MermaidError.syntax(line: line)
            }
            let k =
                try id == "[*]" ? store(start ? "$start" : "$end", kind: start ? .start : .end, label: "") : store(id)
            if pieces.count == 2 {
                assignments.append((k, pieces[1], line))
            } else if pieces.count > 2 {
                throw MermaidError.syntax(line: line)
            }
            return k
        }
        func addNote(_ position: String, _ id: String, _ content: String, _ line: Int) throws {
            let owner = try endpoint(id, start: true, line: line)
            let n = try store("$note\(graph.nodes.count)", kind: .note, label: try checkedLabel(content, line: line))
            graph.nodes[indices[n]!].parent = nil
            graph.edges.append(
                Edge(
                    from: position.lowercased() == "left" ? n : owner, to: position.lowercased() == "left" ? owner : n,
                    parent: nil, note: true))
        }
        for (index, raw) in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .enumerated()
        {
            let line = index + 1
            let text = trim(raw.components(separatedBy: "%%").first ?? "")
            if let pending = note {
                if text.lowercased() == "end note" {
                    try addNote(pending.0, pending.1, pending.2, pending.3)
                    note = nil
                } else {
                    note!.2 += (pending.2.isEmpty ? "" : "\n") + text
                }
                continue
            }
            if text.isEmpty || text.hasPrefix("%%") { continue }
            if !header {
                guard text == "stateDiagram-v2" || text == "stateDiagram" else {
                    if text.hasPrefix("stateDiagram") { throw MermaidError.syntax(line: line) }
                    throw MermaidError.unknownType
                }
                header = true
                continue
            }
            guard graph.edges.count < 4096 else { throw MermaidError.tooLarge }
            if text.hasPrefix("direction ") || text == "--" || text.hasPrefix("state \"")
                || text.range(of: "^[\\p{L}\\p{N}_-]+\\s*:(?!:)", options: .regularExpression) != nil
            {
                throw MermaidError.unsupported(line: line)
            }
            if text == "}" {
                guard let group = scopes.last else { throw MermaidError.syntax(line: line) }
                guard graph.nodes.contains(where: { $0.parent == group }) else {
                    throw MermaidError.unsupported(line: groupLines[group] ?? line)
                }
                scopes.removeLast()
                continue
            }
            if let m = match("^state\\s+([\\p{L}\\p{N}_-]+)\\s*\\{$", text) {
                guard scopes.count < 24 else { throw MermaidError.tooLarge }
                let group = try store(m[0], kind: .group)
                guard groupLines[group] == nil else { throw MermaidError.syntax(line: line) }
                groupLines[group] = line
                scopes.append(group)
                continue
            }
            if let m = match("^state\\s+([\\p{L}\\p{N}_-]+)(?:\\s+<<([^>]+)>>)?$", text) {
                if m[1] == "choice" {
                    _ = try store(m[0], kind: .choice, label: "")
                } else if m[1] == "fork" || m[1] == "join" {
                    _ = try store(m[0], kind: .fork, label: "")
                }
                // Ordinary declarations have no visual effect until referenced.
                continue
            }
            if let m = match("(?i)^note\\s+(left|right)\\s+of\\s+([\\p{L}\\p{N}_-]+)(?:\\s*:\\s*(.*))?$", text) {
                if text.contains(":") { try addNote(m[0], m[1], m[2], line) } else { note = (m[0], m[1], "", line) }
                continue
            }
            if text.hasPrefix("classDef ") {
                let rest = String(text.dropFirst(9))
                guard let space = rest.firstIndex(where: \.isWhitespace) else { throw MermaidError.syntax(line: line) }
                if rest[..<space] == "default" || rest[..<space].contains(",") { throw MermaidError.syntax(line: line) }
                try MermaidStyle.validateState(String(rest[space...]), line: line)
                classes[String(rest[..<space]), default: MermaidStyle()].applyValidated(String(rest[space...]))
                continue
            }
            if let m = match("^class\\s+(\\S+)\\s+(\\S+)$", text) {
                for id in m[0].components(separatedBy: ",") { assignments.append((key(id), m[1], line)) }
                continue
            }
            if let m = match("^style\\s+(\\S+)\\s+(.+)$", text) {
                if m[0] == "[*]" { throw MermaidError.syntax(line: line) }
                try MermaidStyle.validateState(m[1], line: line)
                explicitStyles.append((key(m[0]), m[1], line))
                continue
            }
            if text.hasPrefix("linkStyle ") {
                if text.split(separator: ":", maxSplits: 1).first?.contains("-") == true {
                    throw MermaidError.syntax(line: line)
                }
                throw MermaidError.unsupported(line: line)
            }
            if let m = match("^(.+?)\\s*-->\\s*([^:]+(?:::[^:]+)?)(?:\\s*:\\s*(.*))?$", text) {
                let from = try endpoint(trim(m[0]), start: true, line: line)
                let to = try endpoint(trim(m[1]), start: false, line: line)
                graph.edges.append(
                    Edge(from: from, to: to, parent: scopes.last, label: try checkedLabel(m[2], line: line)))
                continue
            }
            if text.range(of: "^[\\p{L}\\p{N}_-]+(?:::\\S+)?$", options: .regularExpression) != nil {
                _ = try endpoint(text, start: true, line: line)
                continue
            }
            throw MermaidError.syntax(line: line)
        }
        if let note { throw MermaidError.syntax(line: note.3) }
        if !scopes.isEmpty { throw MermaidError.syntax(line: source.components(separatedBy: "\n").count) }
        for (k, name, line) in assignments {
            if let i = indices[k], let definition = classes[name] {
                if graph.nodes[i].kind == .fork { throw MermaidError.unsupported(line: line) }
                if graph.nodes[i].kind != .group { graph.nodes[i].appearance.merge(definition) }
            }
        }
        var lastStyles: [String: (String, Int)] = [:]
        for (id, source, line) in explicitStyles { lastStyles[id] = (source, line) }
        for (id, (source, line)) in lastStyles.sorted(by: { $0.value.1 < $1.value.1 }) {
            if let i = indices[id] {
                if graph.nodes[i].kind == .fork { throw MermaidError.unsupported(line: line) }
                if graph.nodes[i].kind != .group { graph.nodes[i].appearance.applyValidated(source) }
            }
        }
        // The reference reuses one proxy pair per self-transition source;
        // later declarations replace that self edge's label in place.
        var selfIndices: [String: Int] = [:]
        var edges: [Edge] = []
        for edge in graph.edges {
            if edge.from == edge.to, let i = selfIndices[edge.from] {
                edges[i] = edge
            } else {
                if edge.from == edge.to { selfIndices[edge.from] = edges.count }
                edges.append(edge)
            }
        }
        graph.edges = edges
        guard !graph.nodes.isEmpty else { throw MermaidError.empty }
        return graph
    }

    static func layout(
        source: String, size: CGFloat, fontFamily: String, dark: Bool, textStyle: MermaidTextStyle? = nil,
        theme: DocumentTheme? = nil
    ) throws -> MermaidScene {
        let palette = MermaidPalette(dark: dark, theme: theme)
        let graph = try parse(source, dark: dark)
        let textMetrics = textStyle ?? .uniform(size: size, fontFamily: fontFamily)
        let nodesByKey = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.key, $0) })
        func lines(_ text: String) -> [String] {
            text.isEmpty
                ? []
                : text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression).components(
                    separatedBy: "\n")
        }
        func textSize(_ text: String, role: Int = 6) -> CGSize {
            let measurements = lines(text).map { textMetrics.measure($0, role: role) }
            return CGSize(
                width: measurements.map(\.width).max() ?? 0, height: measurements.reduce(0) { $0 + $1.height })
        }
        let labelSizes = Dictionary(
            uniqueKeysWithValues: graph.nodes.map {
                ($0.key, textSize($0.label, role: $0.appearance.role(group: $0.kind == .group)))
            })
        let edgeSizes = graph.edges.map { textSize($0.label) }
        var bodies: [String: Body] = [:]
        func dimensions(_ node: Node) -> CGSize {
            switch node.kind {
            case .start: return CGSize(width: 14, height: 14)
            // The reference end-state hit box is slightly wider than its painted
            // 14-unit circle; this also affects isolated start/end alignment.
            case .end: return CGSize(width: 14.013292312, height: 14)
            case .choice: return CGSize(width: 28, height: 28)
            case .fork: return CGSize(width: 70, height: 10)
            case .group: return bodies[node.key]?.size ?? .zero
            case .note:
                let s = labelSizes[node.key]!
                return CGSize(width: s.width + 30, height: s.height + 30)
            case .state:
                let s = labelSizes[node.key]!
                return CGSize(width: s.width + 16, height: s.height + 16)
            }
        }
        func body(parent: String?, depth: Int, flattened: Bool = false) throws -> Body {
            let local = flattened ? graph.nodes : graph.nodes.filter { $0.parent == parent }
            if !flattened {
                for node in local where node.kind == .group {
                    bodies[node.key] = try body(parent: node.key, depth: depth + 1)
                }
            }
            let root = "$container\(parent ?? "")"
            var inputs: [DagreNode] = []
            for n in local {
                let d = flattened && n.kind == .group ? CGSize.zero : dimensions(n)
                let parentID = flattened ? n.parent : parent == nil ? nil : root
                if n.kind == .note {
                    let container = "$noteContainer\(n.key)"
                    inputs.append(DagreNode(id: container, width: 0, height: 0, parentID: parentID))
                    inputs.append(DagreNode(id: n.key, width: d.width, height: d.height, parentID: container))
                } else {
                    inputs.append(DagreNode(id: n.key, width: d.width, height: d.height, parentID: parentID))
                }
            }
            if parent != nil { inputs.insert(DagreNode(id: root, width: 0, height: 0), at: 0) }
            let localEdges = graph.edges.enumerated().filter { flattened || $0.element.parent == parent }
            var edges: [DagreEdge] = []
            for (i, e) in localEdges {
                if e.from == e.to {
                    let p1 = "$self\(i)a"
                    let p2 = "$self\(i)b"
                    let parentID = flattened ? nodesByKey[e.from]?.parent : parent == nil ? nil : root
                    inputs.append(DagreNode(id: p1, width: 0.1, height: 0.1, parentID: parentID))
                    inputs.append(DagreNode(id: p2, width: 0.1, height: 0.1, parentID: parentID))
                    edges.append(DagreEdge(id: "$self\(i)start", source: e.from, target: p1))
                    edges.append(
                        DagreEdge(
                            id: String(i), source: p1, target: p2, labelWidth: edgeSizes[i].width,
                            labelHeight: edgeSizes[i].height, labelPosition: .center))
                    edges.append(DagreEdge(id: "$self\(i)end", source: p2, target: e.to))
                } else {
                    edges.append(
                        DagreEdge(
                            id: String(i), source: e.from, target: e.to, labelWidth: edgeSizes[i].width,
                            labelHeight: edgeSizes[i].height, labelPosition: .center))
                }
            }
            let layout = try DagreLayout.layout(
                nodes: inputs, edges: edges,
                options: .init(rankSeparation: 40 + Double(depth) * 25, marginX: 8, marginY: 8, tieKeepFirst: true))
            let enclosing = parent.flatMap { _ in layout.nodes[root]?.rect }
            let offset = CGPoint(x: enclosing?.minX ?? 0, y: enclosing?.minY ?? 0)
            var rects = layout.nodes.filter { nodesByKey[$0.key] != nil }.mapValues {
                $0.rect.offsetBy(dx: -offset.x, dy: -offset.y)
            }
            var routed: [Int: [CGPoint]] = [:]
            var labels: [Int: CGPoint] = [:]
            for (i, _) in localEdges {
                routed[i] = layout.edges[String(i)]?.points.map { CGPoint(x: $0.x - offset.x, y: $0.y - offset.y) }
                if let c = layout.edges[String(i)]?.labelCenter {
                    labels[i] = CGPoint(x: c.x - offset.x, y: c.y - offset.y)
                }
            }
            for node in local where node.kind == .group && !flattened {
                guard let child = bodies[node.key], let origin = rects[node.key]?.origin else { continue }
                for (k, r) in child.rects { rects[k] = r.offsetBy(dx: origin.x, dy: origin.y) }
                for (i, path) in child.edges {
                    routed[i] = path.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
                }
                for (i, c) in child.labels { labels[i] = CGPoint(x: c.x + origin.x, y: c.y + origin.y) }
            }
            var resultSize = enclosing?.size ?? layout.size
            if let parent, let label = labelSizes[parent], label.width + 8 > resultSize.width {
                let delta = label.width + 8 - resultSize.width
                resultSize.width += delta
                rects = rects.mapValues { $0.offsetBy(dx: delta / 2, dy: 0) }
                routed = routed.mapValues { $0.map { CGPoint(x: $0.x + delta / 2, y: $0.y) } }
                labels = labels.mapValues { CGPoint(x: $0.x + delta / 2, y: $0.y) }
            }
            return Body(size: resultSize, rects: rects, edges: routed, labels: labels)
        }
        let crossScope = graph.edges.contains {
            nodesByKey[$0.from]?.parent != $0.parent || nodesByKey[$0.to]?.parent != $0.parent
        }
        let layout = try body(parent: nil, depth: 0, flattened: crossScope)
        let fill = palette.nodeFill
        let stroke = palette.nodeStroke
        let edgeColor = palette.edge
        let ink = palette.text
        var commands: [MermaidCommand] = []
        var bounds = CGRect.null
        func include(_ rect: CGRect) { bounds = bounds.union(rect) }
        func text(_ label: String, center: CGFloat, top: CGFloat, role: Int, color: CGColor? = nil) {
            var y = top
            for line in lines(label) {
                let s = textMetrics.measure(line, role: role)
                let r = CGRect(x: center - s.width / 2, y: y, width: s.width, height: s.height)
                if let color {
                    commands.append(.coloredText(line, r, role: role, color: color))
                } else {
                    commands.append(.text(line, r, role: role))
                }
                y += s.height
            }
        }
        // Compound plates precede every transition and leaf state.
        for node in graph.nodes where node.kind == .group {
            guard let r = layout.rects[node.key] else { continue }
            let p = CGMutablePath()
            let k: CGFloat = 0.55228475
            let headerHeight = labelSizes[node.key]!.height + 2
            let bodyRect = CGRect(
                x: r.minX, y: r.minY + headerHeight, width: r.width, height: r.height - headerHeight - 4)
            p.move(to: CGPoint(x: r.minX, y: r.minY + headerHeight))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + 5))
            p.addCurve(
                to: CGPoint(x: r.minX + 5, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + 5 - 5 * k),
                control2: CGPoint(x: r.minX + 5 - 5 * k, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - 5, y: r.minY))
            p.addCurve(
                to: CGPoint(x: r.maxX, y: r.minY + 5), control1: CGPoint(x: r.maxX - 5 + 5 * k, y: r.minY),
                control2: CGPoint(x: r.maxX, y: r.minY + 5 - 5 * k))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + headerHeight))
            p.closeSubpath()
            commands.append(
                .path(
                    p, fill: node.appearance.fill(dark: dark, fallback: fill, palette: palette), stroke: nil, width: 0,
                    dash: []))
            let bottom = CGMutablePath()
            bottom.move(to: CGPoint(x: r.minX, y: r.maxY - 4))
            bottom.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 4))
            bottom.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 4))
            bottom.addCurve(
                to: CGPoint(x: r.maxX - 4, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.maxY - 4 + 4 * k),
                control2: CGPoint(x: r.maxX - 4 + 4 * k, y: r.maxY))
            bottom.addLine(to: CGPoint(x: r.minX + 4, y: r.maxY))
            bottom.addCurve(
                to: CGPoint(x: r.minX, y: r.maxY - 4), control1: CGPoint(x: r.minX + 4 - 4 * k, y: r.maxY),
                control2: CGPoint(x: r.minX, y: r.maxY - 4 + 4 * k))
            bottom.closeSubpath()
            commands.append(
                .path(
                    bottom, fill: node.appearance.fill(dark: dark, fallback: fill, palette: palette), stroke: nil,
                    width: 0, dash: []))
            if node.parent != nil {
                commands.append(.roundRect(bodyRect, radius: 0, fill: palette.blockFill, stroke: nil, width: 0))
            }
            let outline = node.appearance.stroke(dark: dark, fallback: stroke, palette: palette)
            let width = node.appearance.nodeWidth
            let dash = node.appearance.dash()
            commands.append(.roundRect(r, radius: 5, fill: nil, stroke: outline, width: width, dash: dash))
            commands.append(.roundRect(bodyRect, radius: 0, fill: nil, stroke: outline, width: width, dash: dash))
            text(
                node.label, center: r.midX, top: r.minY + 1, role: node.appearance.role(group: true),
                color: node.appearance.text(dark: dark, palette: palette))
            include(r.insetBy(dx: -width / 2, dy: -width / 2))
        }
        func intersect(_ node: Node, toward p: CGPoint, rect: CGRect) -> CGPoint {
            let dx = p.x - rect.midX
            let dy = p.y - rect.midY
            if node.kind == .choice {
                let f = 14 / max(0.00001, abs(dx) + abs(dy))
                return CGPoint(x: rect.midX + 0.5 + dx * f, y: rect.midY + 0.5 + dy * f)
            }
            if node.kind == .start || node.kind == .end {
                let d = max(0.00001, hypot(dx, dy))
                let radius = rect.width / 2
                return CGPoint(x: rect.midX + dx / d * radius, y: rect.midY + dy / d * radius)
            }
            return MermaidFlow.intersection(rect, shape: .rectangle, toward: p)
        }
        for (i, edge) in graph.edges.enumerated() {
            guard var points = layout.edges[i], points.count >= 2, let from = nodesByKey[edge.from],
                let to = nodesByKey[edge.to], let a = layout.rects[edge.from], let b = layout.rects[edge.to]
            else { continue }
            let original = points
            if edge.from == edge.to {
                let spread = min(50, max(18, a.width * 0.175))
                let extent = min(48, max(24, min(a.width, a.height) * 0.45))
                let left = CGPoint(x: a.midX - spread, y: a.maxY + extent)
                let right = CGPoint(x: a.midX + spread, y: a.maxY + extent)
                points = [intersect(from, toward: left, rect: a), left, right, intersect(to, toward: right, rect: b)]
            } else if from.kind != .group && to.kind != .group {
                points[0] = intersect(from, toward: original[1], rect: a)
                points[points.count - 1] = intersect(to, toward: original[original.count - 2], rect: b)
            }
            let p = MermaidFlow.basis(points)
            commands.append(.path(p, fill: nil, stroke: edgeColor, width: 1, dash: edge.note ? [5, 5] : []))
            include(p.boundingBox)
            if !edge.note, let tip = points.last {
                let previous = points[points.count - 2]
                let d = max(0.00001, hypot(tip.x - previous.x, tip.y - previous.y))
                let dx = (tip.x - previous.x) / d
                let dy = (tip.y - previous.y) / d
                let arrow = CGMutablePath()
                arrow.addLines(between: [
                    tip, CGPoint(x: tip.x - 10 * dx - 6 * dy, y: tip.y - 10 * dy + 6 * dx),
                    CGPoint(x: tip.x - 5 * dx, y: tip.y - 5 * dy),
                    CGPoint(x: tip.x - 10 * dx + 6 * dy, y: tip.y - 10 * dy - 6 * dx)
                ])
                arrow.closeSubpath()
                commands.append(.path(arrow, fill: edgeColor, stroke: edgeColor, width: 1, dash: []))
                include(arrow.boundingBoxOfPath)
            }
        }
        for (i, edge) in graph.edges.enumerated() where !edge.label.isEmpty {
            guard var center = layout.labels[i] else { continue }
            if edge.from == edge.to, let node = layout.rects[edge.from] {
                center = CGPoint(x: node.midX, y: node.maxY + 28 + edgeSizes[i].height / 2)
            }
            let s = edgeSizes[i]
            let r = CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height)
            commands.append(.roundRect(r, radius: 0, fill: palette.labelBackground, stroke: nil, width: 0))
            text(edge.label, center: center.x, top: r.minY, role: 6)
            include(r)
        }
        for node in graph.nodes where node.kind != .group {
            guard let r = layout.rects[node.key] else { continue }
            switch node.kind {
            case .start:
                commands.append(.ellipse(r, fill: ink, stroke: nil, width: 0))
                include(r)
            case .end:
                let circle = CGRect(x: r.midX - 7, y: r.midY - 7, width: 14, height: 14)
                commands.append(.ellipse(circle, fill: nil, stroke: ink, width: 2))
                commands.append(
                    .ellipse(
                        CGRect(x: r.midX - 2.5, y: r.midY - 2.5, width: 5, height: 5), fill: ink, stroke: ink, width: 2)
                )
                include(circle.insetBy(dx: -1, dy: -1))
            case .fork:
                commands.append(.roundRect(r, radius: 0, fill: ink, stroke: nil, width: 0))
                include(r)
            case .choice:
                let p = CGMutablePath()
                p.addLines(between: [
                    CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.minY),
                    CGPoint(x: r.minX, y: r.midY)
                ])
                p.closeSubpath()
                commands.append(
                    .path(
                        p, fill: node.appearance.fill(dark: dark, fallback: fill, palette: palette),
                        stroke: node.appearance.stroke(dark: dark, fallback: stroke, palette: palette),
                        width: node.appearance.nodeWidth, dash: node.appearance.dash()))
                include(r)
            case .note:
                commands.append(.roundRect(r, radius: 0, fill: palette.noteFill, stroke: stroke, width: 1.3))
                text(node.label, center: r.midX, top: r.minY + 15, role: 6)
                include(r.insetBy(dx: -0.65, dy: -0.65))
            case .state:
                commands.append(
                    .path(
                        rounded(r), fill: node.appearance.fill(dark: dark, fallback: fill, palette: palette),
                        stroke: node.appearance.stroke(dark: dark, fallback: stroke, palette: palette),
                        width: node.appearance.nodeWidth, dash: node.appearance.dash()))
                text(
                    node.label, center: r.midX, top: r.midY - labelSizes[node.key]!.height / 2,
                    role: node.appearance.role(), color: node.appearance.text(dark: dark, palette: palette))
                include(r)
            case .group: break
            }
        }
        guard !bounds.isNull else { throw MermaidError.empty }
        var scene = MermaidScene(bounds: bounds, commands: commands)
        scene.textStyle = textMetrics
        scene.theme = theme
        return scene
    }

    private static func checkedLabel(_ value: String, line: Int) throws -> String {
        guard value.utf8.count <= 2048 else { throw MermaidError.tooLarge }
        let clean = value.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        if clean.contains("<") || clean.contains(">") { throw MermaidError.unsupported(line: line) }
        return clean
    }
    private static func rounded(_ r: CGRect) -> CGPath {
        let p = CGMutablePath()
        let a: CGFloat = 5
        let k: CGFloat = 0.55228475
        p.move(to: CGPoint(x: r.minX + a, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - a, y: r.minY))
        p.addCurve(
            to: CGPoint(x: r.maxX, y: r.minY + a), control1: CGPoint(x: r.maxX - a + a * k, y: r.minY),
            control2: CGPoint(x: r.maxX, y: r.minY + a - a * k))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - a))
        p.addCurve(
            to: CGPoint(x: r.maxX - a, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.maxY - a + a * k),
            control2: CGPoint(x: r.maxX - a + a * k, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + a, y: r.maxY))
        p.addCurve(
            to: CGPoint(x: r.minX, y: r.maxY - a), control1: CGPoint(x: r.minX + a - a * k, y: r.maxY),
            control2: CGPoint(x: r.minX, y: r.maxY - a + a * k))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + a))
        p.addCurve(
            to: CGPoint(x: r.minX + a, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + a - a * k),
            control2: CGPoint(x: r.minX + a - a * k, y: r.minY))
        p.closeSubpath()
        return p
    }
}
