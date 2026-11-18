import CoreGraphics
import Foundation

/// Class and ER diagrams share native graph placement, but retain distinct
/// compartment metrics, relationship markers, and parser constraints.
enum MermaidEntities {
    enum Kind { case classes, er }
    struct Node {
        var id: String
        var title: String
        var annotations: [String] = []
        var fields: [String] = []
        var methods: [String] = []
        var rows: [[String]] = []
    }
    struct Edge {
        var source: String, target: String, start = "", end = "", label = ""
        var sourceMultiplicity = "", targetMultiplicity = ""
        var dashed = false
    }
    struct Graph {
        var kind: Kind
        var nodes: [Node] = []
        var edges: [Edge] = []
        var links: [String: String] = [:]
    }
    struct Metrics {
        var size: CGSize
        var header: CGFloat = 0, fields: CGFloat = 0, methods: CGFloat = 0
        var columns: [CGFloat] = [], rowHeights: [CGFloat] = []
    }

    static func layout(
        source: String, size: CGFloat, fontFamily: String, dark: Bool, textStyle: MermaidTextStyle? = nil,
        theme: DocumentTheme? = nil
    ) throws -> MermaidScene {
        let palette = MermaidPalette(dark: dark, theme: theme)
        let graph = try parse(source)
        let textMetrics = textStyle ?? .uniform(size: size, fontFamily: fontFamily)
        func measure(_ text: String, _ role: Int = 6) -> CGSize {
            textMetrics.measure(text, role: role)
        }
        let metrics = graph.nodes.map { node -> Metrics in
            let title = measure(node.title, graph.kind == .classes ? 8 : 6)
            if graph.kind == .classes {
                let annotation = node.annotations.map { measure($0) }
                let header = title.height + annotation.reduce(0) { $0 + $1.height } + 24
                let fields =
                    node.fields.isEmpty
                    ? (node.methods.isEmpty ? 18.0 : 24.0) : node.fields.reduce(24.0) { $0 + measure($1).height }
                let methods =
                    node.methods.isEmpty
                    ? (node.fields.isEmpty ? 18.0 : 24.0)
                    : node.methods.reduce(node.fields.isEmpty ? 30.0 : 24.0) { $0 + measure($1).height }
                let members = (node.fields + node.methods).map { measure($0).width + title.width / 2 }.max() ?? 0
                let width = max(title.width, members, annotation.map(\.width).max() ?? 0) + 24
                return Metrics(
                    size: CGSize(width: width, height: header + fields + methods), header: header, fields: fields,
                    methods: methods)
            }
            guard !node.rows.isEmpty else {
                return Metrics(size: CGSize(width: max(100, title.width + 40), height: title.height + 60))
            }
            let columnCount = node.rows.map(\.count).max() ?? 2
            var columns = Array(repeating: CGFloat(0), count: columnCount)
            let rowHeights = node.rows.map { row -> CGFloat in
                var height: CGFloat = 0
                for (index, text) in row.enumerated() {
                    let textSize = measure(text)
                    columns[index] = max(columns[index], textSize.width + 25)
                    height = max(height, textSize.height)
                }
                return height + 18.75
            }
            let contentWidth = columns.reduce(0, +)
            let width = max(contentWidth, title.width + 50)
            columns = columns.map { $0 + (width - contentWidth) / CGFloat(columnCount) }
            let header = title.height + 18.75
            return Metrics(
                size: CGSize(width: width, height: header + rowHeights.reduce(0, +)), header: header, columns: columns,
                rowHeights: rowHeights)
        }
        var nodes = graph.nodes.enumerated().map {
            DagreNode(id: $0.element.id, width: metrics[$0.offset].size.width, height: metrics[$0.offset].size.height)
        }
        var edges: [DagreEdge] = []
        for (index, edge) in graph.edges.enumerated() {
            let label = measure(edge.label, graph.kind == .er ? 11 : 6)
            if edge.source == edge.target {
                // Native self edges participate in placement as a three-edge
                // cycle with two tiny helpers. Their eventual paint is a
                // separate loop below the original node.
                let first = "\u{0}self\(index)a"
                let second = "\u{0}self\(index)b"
                nodes.append(DagreNode(id: first, width: 0.1, height: 0.1))
                nodes.append(DagreNode(id: second, width: 0.1, height: 0.1))
                edges.append(DagreEdge(id: "\(index)a", source: edge.source, target: first))
                edges.append(
                    DagreEdge(
                        id: "\(index)b", source: first, target: second,
                        labelWidth: edge.label.isEmpty ? 0 : label.width,
                        labelHeight: edge.label.isEmpty ? 0 : label.height))
                edges.append(DagreEdge(id: "\(index)c", source: second, target: edge.target))
            } else {
                edges.append(
                    DagreEdge(
                        id: String(index), source: edge.source, target: edge.target,
                        labelWidth: edge.label.isEmpty ? 0 : label.width,
                        labelHeight: edge.label.isEmpty ? 0 : label.height))
            }
        }
        let layout = try DagreLayout.layout(
            nodes: nodes, edges: edges,
            options: .init(
                nodeSeparation: graph.kind == .er ? 140 : 50, rankSeparation: graph.kind == .er ? 80 : 50, marginX: 8,
                marginY: 8, tieKeepFirst: true))
        var commands: [MermaidCommand] = []
        var bounds = CGRect.null
        var routes: [Int: [CGPoint]] = [:]
        var labelCenters: [Int: CGPoint] = [:]
        let stroke = palette.nodeStroke
        let fill = palette.nodeFill
        let edgeStroke = theme == nil ? stroke : palette.edge
        func add(_ command: MermaidCommand) {
            commands.append(command)
            switch command {
            case .path(let path, _, let paint, let width, _):
                bounds = bounds.union(
                    path.boundingBox.insetBy(dx: paint == nil ? 0 : -width / 2, dy: paint == nil ? 0 : -width / 2))
            case .roundRect(let rect, _, _, let paint, let width, _), .ellipse(let rect, _, let paint, let width):
                bounds = bounds.union(
                    rect.insetBy(dx: paint == nil ? 0 : -width / 2, dy: paint == nil ? 0 : -width / 2))
            case .text(_, let rect, _), .coloredText(_, let rect, _, _): bounds = bounds.union(rect)
            }
        }
        func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat = 1) {
            let p = CGMutablePath()
            p.move(to: a)
            p.addLine(to: b)
            add(.path(p, fill: nil, stroke: stroke, width: width, dash: []))
        }
        // Paint every relationship before labels and entity compartments.
        for (index, edge) in graph.edges.enumerated() {
            var points: [CGPoint]
            if edge.source == edge.target, let node = layout.nodes[edge.source] {
                let label = measure(edge.label, graph.kind == .er ? 11 : 6)
                let extent = min(48, max(24, min(node.width, node.height) * 0.45))
                var spread = min(50, max(18, node.width * 0.175))
                if graph.kind == .er { spread = max(spread, min(40, label.width / 2)) }
                let left = CGPoint(x: node.center.x - spread, y: node.rect.maxY + extent)
                let right = CGPoint(x: node.center.x + spread, y: node.rect.maxY + extent)
                points = [
                    MermaidFlow.intersection(node.rect, shape: .rectangle, toward: left), left, right,
                    MermaidFlow.intersection(node.rect, shape: .rectangle, toward: right)
                ]
                labelCenters[index] = CGPoint(x: node.center.x, y: left.y + 4 + label.height / 2)
            } else {
                guard let routed = layout.edges[String(index)], routed.points.count >= 2 else { continue }
                points = routed.points
                labelCenters[index] = routed.labelCenter
            }
            routes[index] = points
            let start = points[0]
            let end = points[points.count - 1]
            if graph.kind == .classes {
                let startDistance: CGFloat = edge.start.isEmpty ? 0 : edge.start == ">" ? 6 : 17.25
                let endDistance: CGFloat = edge.end.isEmpty ? 0 : edge.end == ">" ? 6 : 17.25
                points[0] = MermaidFlow.offset(start, toward: points[1], by: startDistance)
                points[points.count - 1] = MermaidFlow.offset(end, toward: points[points.count - 2], by: endDistance)
            }
            add(
                .path(
                    MermaidFlow.basis(points), fill: nil, stroke: edgeStroke, width: 1,
                    dash: edge.dashed ? (graph.kind == .er ? [8, 8] : [3, 3]) : []))
            if graph.kind == .classes {
                for (marker, tip, toward, isStart) in [
                    (edge.start, start, points[1], true), (edge.end, end, points[points.count - 2], false)
                ] where !marker.isEmpty {
                    add(
                        .path(
                            classMarker(marker, tip: tip, toward: toward, start: isStart),
                            fill: marker == "*" || marker == ">" ? edgeStroke : nil, stroke: edgeStroke, width: 1,
                            dash: []))
                }
            } else {
                for (marker, tip, toward, isStart) in [
                    (edge.start, start, points[1], true), (edge.end, end, points[points.count - 2], false)
                ] {
                    for command in erMarker(
                        marker, tip: tip, toward: toward, start: isStart, stroke: edgeStroke,
                        background: palette.labelBackground)
                    { add(command) }
                }
            }
        }
        for (index, edge) in graph.edges.enumerated() {
            guard let points = routes[index], points.count >= 2 else { continue }
            if !edge.label.isEmpty, let center = labelCenters[index] {
                let measured = measure(edge.label, graph.kind == .er ? 11 : 6)
                let rect = CGRect(
                    x: center.x - measured.width / 2, y: center.y - measured.height / 2, width: measured.width,
                    height: measured.height)
                add(.roundRect(rect, radius: 0, fill: palette.labelBackground, stroke: nil, width: 0))
                add(.text(edge.label, rect, role: graph.kind == .er ? 11 : 6))
            }
            if graph.kind == .classes {
                for (text, start) in [(edge.sourceMultiplicity, true), (edge.targetMultiplicity, false)]
                where !text.isEmpty {
                    let measured = measure(text, 12)
                    let route = start ? points : Array(points.reversed())
                    let endpoint = route[0]
                    guard let nearby = point(on: route, distance: 35) else { continue }
                    let angle = atan2(endpoint.y - nearby.y, endpoint.x - nearby.x)
                    let anchor = CGPoint(
                        x: (endpoint.x + nearby.x) / 2 + sin(angle) * 15,
                        y: (endpoint.y + nearby.y) / 2 - cos(angle) * 15)
                    let rect = CGRect(
                        x: anchor.x - (start ? measured.width / 2 : 5),
                        y: anchor.y - (start ? measured.height / 2 : 5), width: measured.width, height: measured.height)
                    add(.text(text, rect, role: 12))
                }
            }
        }
        var links: [MermaidNodeLink] = []
        for (index, node) in graph.nodes.enumerated() {
            guard let rect = layout.nodes[node.id]?.rect else { continue }
            let metric = metrics[index]
            if graph.kind == .classes {
                add(.roundRect(rect, radius: 0, fill: fill, stroke: stroke, width: 1))
                var y = rect.minY + 24
                for text in node.annotations + [node.title] {
                    let measured = measure(text, text == node.title ? 8 : 6)
                    add(
                        .text(
                            text,
                            CGRect(
                                x: rect.midX - measured.width / 2, y: y - measured.height / 2, width: measured.width,
                                height: measured.height), role: text == node.title ? 8 : 6))
                    y += measured.height
                }
                if let target = graph.links[node.id] {
                    links.append(
                        .init(
                            path: CGPath(rect: rect, transform: nil), target: target,
                            labelCommands: (commands.count - 1)..<commands.count))
                }
                y = rect.minY + metric.header + 24
                for text in node.fields {
                    let measured = measure(text)
                    add(
                        .text(
                            text,
                            CGRect(
                                x: rect.minX + 12, y: y - measured.height / 2, width: measured.width,
                                height: measured.height), role: 6))
                    y += measured.height
                }
                y = rect.minY + metric.header + metric.fields + 24 + (node.fields.isEmpty ? 6 : 0)
                for text in node.methods {
                    let measured = measure(text)
                    add(
                        .text(
                            text,
                            CGRect(
                                x: rect.minX + 12, y: y - measured.height / 2, width: measured.width,
                                height: measured.height), role: 6))
                    y += measured.height
                }
                for separator in [metric.header, metric.header + metric.fields] {
                    line(
                        CGPoint(x: rect.minX, y: rect.minY + separator),
                        CGPoint(x: rect.maxX, y: rect.minY + separator + 0.001))
                }
            } else if node.rows.isEmpty {
                add(.roundRect(rect, radius: 0, fill: fill, stroke: stroke, width: 1))
                let measured = measure(node.title)
                add(
                    .text(
                        node.title,
                        CGRect(
                            x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2,
                            width: measured.width, height: measured.height), role: 6))
            } else {
                var y = rect.minY
                let header = CGRect(x: rect.minX, y: y, width: rect.width, height: metric.header)
                add(.roundRect(header, radius: 0, fill: fill, stroke: nil, width: 0))
                y += metric.header
                var rows: [CGRect] = []
                for (i, height) in metric.rowHeights.enumerated() {
                    let box = CGRect(x: rect.minX, y: y, width: rect.width, height: height)
                    rows.append(box)
                    add(
                        .roundRect(
                            box, radius: 0, fill: i.isMultiple(of: 2) ? palette.labelBackground : palette.blockFill,
                            stroke: nil, width: 0))
                    y += height
                }
                for box in rows { add(.roundRect(box, radius: 0, fill: nil, stroke: stroke, width: 1.3)) }
                add(.roundRect(rect, radius: 0, fill: nil, stroke: stroke, width: 1.3))
                let title = measure(node.title)
                add(
                    .text(
                        node.title,
                        CGRect(
                            x: rect.midX - title.width / 2, y: header.midY - title.height / 2, width: title.width,
                            height: title.height), role: 6))
                for (i, row) in node.rows.enumerated() {
                    var x = rect.minX + 12.5
                    for (j, text) in row.enumerated() {
                        if !text.isEmpty {
                            let measured = measure(text)
                            add(
                                .text(
                                    text,
                                    CGRect(
                                        x: x, y: rows[i].midY - measured.height / 2, width: measured.width,
                                        height: measured.height), role: 6))
                        }
                        x += metric.columns[j]
                    }
                }
                line(CGPoint(x: rect.minX, y: header.maxY), CGPoint(x: rect.maxX, y: header.maxY), width: 1.3)
                var x = rect.minX
                for width in metric.columns.dropLast() {
                    x += width
                    line(CGPoint(x: x, y: header.maxY), CGPoint(x: x, y: rect.maxY), width: 1.3)
                }
            }
        }
        return MermaidScene(bounds: bounds, commands: commands, theme: theme, links: links)
    }

    private static func point(on points: [CGPoint], distance: CGFloat) -> CGPoint? {
        var remaining = distance
        for (a, b) in zip(points, points.dropFirst()) {
            let length = hypot(b.x - a.x, b.y - a.y)
            if length == 0 { return a }
            if length >= remaining {
                if remaining <= 0 { return a }
                if remaining == length { return b }
                let position = MermaidFlow.offset(a, toward: b, by: remaining)
                func rounded(_ value: CGFloat) -> CGFloat {
                    let scaled = value * 100_000
                    let truncated = scaled.rounded(.towardZero)
                    return (truncated + (scaled - truncated >= 0.5 ? 1 : 0)) / 100_000
                }
                return CGPoint(x: rounded(position.x), y: rounded(position.y))
            }
            remaining -= length
        }
        return nil
    }

    private static func classMarker(_ marker: String, tip: CGPoint, toward: CGPoint, start: Bool) -> CGPath {
        let d = hypot(toward.x - tip.x, toward.y - tip.y)
        let u = CGPoint(x: (toward.x - tip.x) / max(d, 0.001), y: (toward.y - tip.y) / max(d, 0.001))
        func p(_ along: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: tip.x + u.x * along - u.y * side, y: tip.y + u.y * along + u.x * side)
        }
        let path = CGMutablePath()
        if marker == "|" {
            path.addLines(
                between: start
                    ? [p(0.25, 0), p(17.25, 6), p(17.25, -6)]
                    : [p(17.25, 6), p(17.25, -6), p(0.25, 0)])
        } else if marker == "*" || marker == "o" {
            path.addLines(
                between: start
                    ? [p(17.25, 0), p(8.25, 6), p(0.25, 0), p(8.25, -6)]
                    : [p(0.25, 0), p(9.25, -6), p(17.25, 0), p(9.25, 6)])
        } else {
            path.addLines(
                between: start
                    ? [p(5, 0), p(9, 6), p(1, 0), p(9, -6)]
                    : [p(1, 0), p(10, -6), p(5, 0), p(10, 6)])
        }
        path.closeSubpath()
        return path
    }

    private static func erMarker(
        _ marker: String, tip: CGPoint, toward: CGPoint, start: Bool, stroke: CGColor, background: CGColor
    ) -> [MermaidCommand] {
        let distance = max(0.001, hypot(toward.x - tip.x, toward.y - tip.y))
        let u = CGPoint(x: (toward.x - tip.x) / distance, y: (toward.y - tip.y) / distance)
        func p(_ along: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: tip.x + u.x * along - u.y * side, y: tip.y + u.y * along + u.x * side)
        }
        let path = CGMutablePath()
        func bar(_ along: CGFloat) {
            let side: CGFloat = start ? -9 : 9
            path.move(to: p(along, side))
            path.addLine(to: p(along, -side))
        }
        func many() {
            if start {
                path.move(to: p(-18, 0))
                path.addCurve(to: p(18, 0), control1: p(-6, -12), control2: p(6, -12))
                path.addCurve(to: p(-18, 0), control1: p(6, 12), control2: p(-6, 12))
            } else {
                path.move(to: p(18, 0))
                path.addCurve(to: p(-18, 0), control1: p(6, 12), control2: p(-6, 12))
                path.addCurve(to: p(18, 0), control1: p(-6, -12), control2: p(6, -12))
            }
        }
        let zero = marker.contains("o")
        let multiple = marker.contains("{") || marker.contains("}")
        if multiple {
            if !start && !zero { bar(24) }
            many()
            if start && !zero { bar(24) }
        } else {
            bar(9)
            if !zero { bar(15) }
        }
        var commands: [MermaidCommand] = [.path(path, fill: nil, stroke: stroke, width: 1, dash: [])]
        if zero {
            let point = p(multiple ? 30 : 21, 0)
            let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
            commands.append(.ellipse(rect, fill: background, stroke: nil, width: 0))
            commands.append(.ellipse(rect, fill: nil, stroke: stroke, width: 1))
        }
        return commands
    }

    private static func captures(_ pattern: String, _ value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
        else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" }
    }
    private static func generic(_ text: String) -> String {
        var open = false
        return text.map { character in
            if character == "~" {
                open.toggle()
                return open ? "<" : ">"
            }
            return String(character)
        }.joined()
    }

    static func parse(_ source: String) throws -> Graph {
        guard source.utf8.count <= 65_536 else { throw MermaidError.tooLarge }
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        guard let first = lines.first else { throw MermaidError.empty }
        var graph = Graph(kind: first.hasPrefix("classDiagram") ? .classes : .er)
        guard first == "classDiagram" || first == "classDiagram-v2" || first == "erDiagram" else {
            if first.hasPrefix("classDiagram") || first.hasPrefix("erDiagram") { throw MermaidError.syntax(line: 1) }
            throw MermaidError.unknownType
        }
        var indices: [String: Int] = [:]
        var current: Int?
        func node(_ name: String) -> Int {
            let id = graph.kind == .classes ? String(name.prefix { $0 != "~" }) : name
            if let index = indices[id] { return index }
            let index = graph.nodes.count
            graph.nodes.append(Node(id: id, title: generic(name)))
            indices[id] = index
            return index
        }
        func member(_ text: String, at index: Int, line: Int) throws {
            let value = text.trimmingCharacters(in: .whitespaces)
            guard value.utf8.count <= 2048 else { throw MermaidError.tooLarge }
            if value.hasSuffix("*") || value.hasSuffix("$") || value.contains("<br") {
                throw MermaidError.unsupported(line: line)
            }
            if value.hasPrefix("<<"), value.hasSuffix(">>") {
                graph.nodes[index].annotations.append("«" + value.dropFirst(2).dropLast(2) + "»")
            } else if value.contains("<") || value.contains(">") {
                throw MermaidError.unsupported(line: line)
            } else if let close = value.lastIndex(of: ")"), value.contains("(") {
                let head = String(value[...close])
                let tail = value[value.index(after: close)...].trimmingCharacters(in: .whitespaces)
                graph.nodes[index].methods.append(generic(head + (tail.isEmpty ? "" : " : " + tail)))
            } else {
                graph.nodes[index].fields.append(generic(value))
            }
        }
        for (offset, original) in lines.dropFirst().enumerated() {
            let line = offset + 2
            if original.trimmingCharacters(in: .whitespaces).hasPrefix("%%{") {
                throw MermaidError.unsupported(line: line)
            }
            let text = original.components(separatedBy: "%%")[0].trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            if let index = current {
                if text == "}" {
                    current = nil
                    continue
                }
                if graph.kind == .classes {
                    try member(text, at: index, line: line)
                } else {
                    guard
                        let values = captures(
                            #"^(\S+)\s+(\S+)(?:\s+((?:PK|FK|UK)(?:\s*,\s*(?:PK|FK|UK))*))?(?:\s+"([^"]*)")?\s*$"#, text)
                    else { throw MermaidError.syntax(line: line) }
                    var row = [values[0], values[1]]
                    if !values[2].isEmpty || !values[3].isEmpty {
                        row.append(values[2].replacingOccurrences(of: " ", with: ""))
                    }
                    if !values[3].isEmpty { row.append(values[3]) }
                    graph.nodes[index].rows.append(row)
                }
                continue
            }
            if graph.kind == .classes {
                if text.hasPrefix("click "),
                    let (id, target) = MermaidNodeLink.parse(text.dropFirst(6), requiresHref: true)
                {
                    if MermaidNodeLink.isSafeTarget(target) { graph.links[id] = target }
                    continue
                }
                if text.hasPrefix("link "),
                    let (id, target) = MermaidNodeLink.parse(text.dropFirst(5))
                {
                    if MermaidNodeLink.isSafeTarget(target) { graph.links[id] = target }
                    continue
                }
            }
            if ["direction ", "namespace ", "note ", "style ", "classDef ", "cssClass "].contains(where: text.hasPrefix)
                || text.contains("[")
            {
                throw MermaidError.unsupported(line: line)
            }
            if text.hasPrefix("accTitle:") || text.hasPrefix("accDescr:") { continue }
            if graph.kind == .classes {
                if let values = captures(#"^class\s+([\w~,.-]+)\s*\{\s*(.*?)\s*\}$"#, text) {
                    let index = node(values[0])
                    if !values[1].isEmpty { try member(values[1], at: index, line: line) }
                    continue
                }
                if let values = captures(#"^<<(.*?)>>\s+([\w~,.-]+)$"#, text) {
                    try member("<<" + values[0] + ">>", at: node(values[1]), line: line)
                    continue
                }
                if let values = captures(#"^class\s+([\w~,.-]+)\s*(\{)?$"#, text) {
                    let index = node(values[0])
                    if !values[1].isEmpty { current = index }
                    continue
                }
                if let values = captures(#"^([\w~,.-]+)\s*:\s*(.+)$"#, text) {
                    try member(values[1], at: node(values[0]), line: line)
                    continue
                }
                if text.contains("()--") || text.contains("--()") { throw MermaidError.unsupported(line: line) }
                if let values = captures(
                    #"^([\w~,.-]+)\s*(?:"([^"]*)")?\s*([<|*o>]*)(--|\.\.)([<|*o>]*)\s*(?:"([^"]*)")?\s*([\w~,.-]+)(?:\s*:\s*(.+))?$"#,
                    text)
                {
                    let sourceIndex = node(values[0])
                    let targetIndex = node(values[6])
                    let source = graph.nodes[sourceIndex].id
                    let target = graph.nodes[targetIndex].id
                    func marker(_ text: String) -> String {
                        text.contains("|")
                            ? "|" : text.contains("*") ? "*" : text.contains("o") ? "o" : text.isEmpty ? "" : ">"
                    }
                    graph.edges.append(
                        Edge(
                            source: source, target: target, start: marker(values[2]), end: marker(values[4]),
                            label: values[7], sourceMultiplicity: values[1], targetMultiplicity: values[5],
                            dashed: values[3] == ".."))
                    continue
                }
                if captures(#"^[\w~,.-]+$"#, text) != nil { continue }
            } else {
                if let values = captures(#"^(?:"([^"]+)"|([\w-]+))\s*\{$"#, text) {
                    current = node(values[0].isEmpty ? values[1] : values[0])
                    continue
                }
                if let values = captures(
                    #"^(?:"([^"]+)"|([\w-]+))\s+([|o}{]{2})(--|\.\.)([|o}{]{2})\s+(?:"([^"]+)"|([\w-]+))\s*:\s*(?:"([^"]*)"|([\w-]+))$"#,
                    text)
                {
                    if ["one", "many", "to"].contains(values[8]) { throw MermaidError.syntax(line: line) }
                    let source = values[0].isEmpty ? values[1] : values[0]
                    let target = values[5].isEmpty ? values[6] : values[5]
                    _ = node(source)
                    _ = node(target)
                    graph.edges.append(
                        Edge(
                            source: source, target: target, start: values[2], end: values[4],
                            label: values[7].isEmpty ? values[8] : values[7], dashed: values[3] == ".."))
                    continue
                }
                if let values = captures(#"^(?:"([^"]+)"|([\w-]+))$"#, text) {
                    _ = node(values[0].isEmpty ? values[1] : values[0])
                    continue
                }
            }
            throw MermaidError.syntax(line: line)
        }
        if current != nil { throw MermaidError.syntax(line: lines.count) }
        guard !graph.nodes.isEmpty else {
            throw graph.kind == .classes && lines.count == 1 ? MermaidError.syntax(line: 1) : MermaidError.empty
        }
        var selfIndices: [String: Int] = [:]
        var deduplicated: [Edge] = []
        for edge in graph.edges {
            if edge.source == edge.target {
                if let previous = selfIndices[edge.source] {
                    deduplicated[previous] = edge
                } else {
                    selfIndices[edge.source] = deduplicated.count
                    deduplicated.append(edge)
                }
            } else {
                deduplicated.append(edge)
            }
        }
        graph.edges = deduplicated
        guard graph.nodes.count <= 4096, graph.edges.count <= 16384 else { throw MermaidError.tooLarge }
        guard graph.nodes.count + selfIndices.count * 2 <= 4096 else { throw MermaidError.tooLarge }
        var requests = Set<String>()
        func request(_ text: String, role: Int) throws {
            guard text.utf8.count <= 2048 else { throw MermaidError.tooLarge }
            if !text.isEmpty { requests.insert("\(role):" + text) }
        }
        for node in graph.nodes {
            try request(node.title, role: graph.kind == .classes ? 8 : 6)
            for text in node.annotations + node.fields + node.methods + node.rows.flatMap({ $0 }) {
                try request(text, role: 6)
            }
        }
        for edge in graph.edges {
            try request(edge.label, role: graph.kind == .classes ? 6 : 11)
            try request(edge.sourceMultiplicity, role: 12)
            try request(edge.targetMultiplicity, role: 12)
        }
        guard requests.count <= 4096 else { throw MermaidError.tooLarge }
        return graph
    }
}
