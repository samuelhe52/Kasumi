import AppKit
import Markdown

/// Indented native mindmap and directory tree layouts. Geometry is checked
/// against recorded reference cases.
enum MermaidTree {
    enum Shape { case plain, square, rounded, circle, hexagon, bang, cloud }
    struct Node {
        var label: String
        var shape: Shape
        var indent: Int
        var line: Int
        var parent: Int?
        var children: [Int] = []
    }
    struct Diagram { var tree: Bool; var nodes: [Node] }
    struct Label { var lines: [(String, CGSize)]; var size: CGSize }

    static func layout(source: String, size: CGFloat, fontFamily: String, dark: Bool, textStyle: MermaidTextStyle? = nil, theme: DocumentTheme? = nil) throws -> MermaidScene {
        let palette = MermaidPalette(dark: dark, theme: theme)
        let textMetrics = textStyle ?? .uniform(size: size, fontFamily: fontFamily)
        let diagram = try parse(source)
        let labels = diagram.nodes.enumerated().map { index, node -> Label in
            let lines = diagram.tree ? (node.label.isEmpty ? [] : [node.label]) : labelLines(node.label)
            let measured = lines.map { ($0, textMetrics.measure($0, role: diagram.tree && index == 0 ? 8 : 6)) }
            return Label(lines: measured, size: CGSize(width: measured.map { $0.1.width }.max() ?? 0,
                                                       height: measured.reduce(0) { $0 + $1.1.height }))
        }
        var scene = diagram.tree ? treeLayout(diagram.nodes, labels: labels, dark: dark, palette: palette) : mindmapLayout(diagram.nodes, labels: labels, dark: dark, palette: palette)
        scene.textStyle = textStyle
        scene.theme = theme
        return scene
    }

    static func parse(_ source: String) throws -> Diagram {
        guard source.utf8.count <= 65_536 else { throw MermaidError.tooLarge }
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        guard let header = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("%%") }) else { throw MermaidError.empty }
        let type = lines[header].trimmingCharacters(in: .whitespaces)
        let tree = type.hasPrefix("treeView-beta")
        guard type == "treeView-beta" || type == "mindmap" else {
            if tree { throw MermaidError.syntax(line: header + 1) }
            if type.hasPrefix("mindmap") { throw MermaidError.syntax(line: header + 2) }
            throw MermaidError.unknownType
        }
        var nodes: [Node] = tree ? [Node(label: "/", shape: .plain, indent: -1, line: header + 1, parent: nil)] : []
        var stack: [Int] = tree ? [0] : []
        for index in (header + 1)..<lines.count {
            let raw = lines[index], value = raw.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("%%{") { throw MermaidError.unsupported(line: index + 1) }
            if value.isEmpty || value.hasPrefix("%%") { continue }
            if value.hasPrefix(":::") || (!tree && value.hasPrefix("::icon(")) {
                guard nodes.count > (tree ? 1 : 0) else { throw MermaidError.syntax(line: index + 1) }
                continue
            }
            if tree && value.hasPrefix("title ") { continue }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let label: String, shape: Shape
            if tree {
                if value.hasPrefix("\"") {
                    guard value.count >= 2 && value.hasSuffix("\"") else { throw MermaidError.syntax(line: index + 1) }
                    label = String(value.dropFirst().dropLast()); shape = .plain
                } else { label = value; shape = .plain }
            } else { (label, shape) = try mindmapLabel(value, line: index + 1) }
            guard label.utf8.count <= 2048 else { throw MermaidError.tooLarge }
            while let last = stack.last, nodes[last].indent >= indent { stack.removeLast() }
            if tree && stack.isEmpty { stack = [0] }
            guard tree || nodes.isEmpty || !stack.isEmpty else { throw MermaidError.syntax(line: index + 1) }
            let parent = stack.last, id = nodes.count
            if id >= (tree ? 2001 : 500) { throw MermaidError.tooLarge }
            nodes.append(Node(label: label, shape: shape, indent: indent, line: index + 1, parent: parent))
            if let parent { nodes[parent].children.append(id) }
            stack.append(id)
        }
        guard tree || !nodes.isEmpty else { throw MermaidError.syntax(line: max(header + 1, lines.count - (lines.last == "" ? 1 : 0))) }
        return Diagram(tree: tree, nodes: nodes)
    }

    private static func mindmapLabel(_ value: String, line: Int) throws -> (String, Shape) {
        var label = value, shape = Shape.plain
        if let start = value.firstIndex(where: { "[({)".contains($0) }) {
            let tail = String(value[start...])
            let wrappers: [(String, String, Shape)] = [("((", "))", .circle), ("{{", "}}", .hexagon),
                ("))", "((", .bang), ("[", "]", .square), ("(", ")", .rounded), (")", "(", .cloud)]
            guard let wrapper = wrappers.first(where: { tail.hasPrefix($0.0) && tail.hasSuffix($0.1) && tail.count >= $0.0.count + $0.1.count }) else { throw MermaidError.syntax(line: line) }
            label = String(tail.dropFirst(wrapper.0.count).dropLast(wrapper.1.count)).trimmingCharacters(in: .whitespaces)
            shape = wrapper.2
            if label.hasPrefix("\"") {
                guard label.count >= 2 && label.hasSuffix("\"") else { throw MermaidError.syntax(line: line) }
                label = String(label.dropFirst().dropLast())
            }
            if label.contains("\"") || label.contains("[") || label.contains("]") || label.contains("{") || label.contains("}") { throw MermaidError.syntax(line: line) }
        }
        if label.contains("\\") || label.range(of: "&#x", options: .caseInsensitive) != nil { throw MermaidError.unsupported(line: line) }
        guard !label.isEmpty else { throw MermaidError.syntax(line: line) }
        return (label, shape)
    }

    private static func labelLines(_ source: String) -> [String] {
        let breaks = source.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        let stripped = breaks.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00a0}"]
        let regex = try! NSRegularExpression(pattern: "&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);")
        var text = stripped
        for match in regex.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)).reversed() {
            guard let range = Range(match.range, in: text), let keyRange = Range(match.range(at: 1), in: stripped) else { continue }
            let key = String(stripped[keyRange]); var replacement = named[key]
            if key.hasPrefix("#") {
                let hex = key.hasPrefix("#x")
                if let number = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) { replacement = "&" + String(scalar) }
            } else if replacement == nil {
                // Reuse CommonMark's maintained HTML entity catalog without
                // parsing the label itself as Markdown.
                let entity = "&" + key + ";"
                if let paragraph = Markdown.Document(parsing: entity).child(at: 0) as? Paragraph {
                    replacement = paragraph.plainText
                }
            }
            if let replacement { text.replaceSubrange(range, with: replacement) }
        }
        return text.components(separatedBy: "\n")
    }

    private static func line(_ a: CGPoint, _ b: CGPoint, color: NSColor, width: CGFloat = 1) -> MermaidCommand {
        let path = CGMutablePath(); path.move(to: a); path.addLine(to: b)
        return .path(path, fill: nil, stroke: color, width: width, dash: [])
    }

    private static func treeLayout(_ nodes: [Node], labels: [Label], dark: Bool, palette: MermaidPalette) -> MermaidScene {
        var commands: [MermaidCommand] = [], y: CGFloat = 0, right: CGFloat = 0
        let color = palette.edge
        @discardableResult func visit(_ index: Int, depth: Int) -> CGFloat {
            let label = labels[index], x = CGFloat(depth) * 15 + 5
            let top = y, center = top + (label.size.height + 10) / 2
            for (text, measured) in label.lines {
                commands.append(.text(text, CGRect(x: x, y: top + 5, width: measured.width, height: measured.height), role: index == 0 ? 8 : 6))
            }
            commands.append(line(CGPoint(x: index == 0 ? -0.5 : x - 15, y: center), CGPoint(x: x - 5, y: center), color: color))
            right = max(right, x + label.size.width + 4.5)
            y += label.size.height + 10
            let childrenStart = y
            var lastChildCenter: CGFloat?
            for child in nodes[index].children { lastChildCenter = visit(child, depth: depth + 1) }
            if let lastChildCenter {
                commands.append(line(CGPoint(x: x, y: childrenStart), CGPoint(x: x, y: lastChildCenter + 0.5), color: color))
            }
            return center
        }
        visit(0, depth: 0)
        return MermaidScene(bounds: CGRect(x: -0.5, y: 0, width: right + 0.5, height: y), commands: commands)
    }

    private static func nominalSize(_ label: CGSize, shape: Shape) -> CGSize {
        switch shape {
        case .plain: return CGSize(width: label.width + 40, height: label.height + 10)
        case .square: return CGSize(width: label.width + 40, height: label.height + 20)
        case .rounded: return CGSize(width: label.width + 30, height: label.height + 30)
        case .circle: return CGSize(width: label.width + 20, height: label.width + 20)
        case .hexagon: return CGSize(width: label.width + 20 + (label.height + 20) / 2, height: label.height + 20)
        case .bang: return CGSize(width: label.width + 50, height: label.height + 40)
        case .cloud: return CGSize(width: label.width + 10, height: label.height + 10)
        }
    }

    private static func mindmapLayout(_ nodes: [Node], labels: [Label], dark: Bool, palette: MermaidPalette) -> MermaidScene {
        let sizes = nodes.indices.map { index -> CGSize in
            let nominal = nominalSize(labels[index].size, shape: nodes[index].shape)
            if nodes[index].shape == .bang || nodes[index].shape == .cloud {
                return nodePath(CGRect(x: -nominal.width / 2, y: -nominal.height / 2, width: nominal.width, height: nominal.height), shape: nodes[index].shape).boundingBoxOfPath.size
            }
            return nominal
        }
        var centers = [CGPoint](repeating: .zero, count: nodes.count)
        var heights = [CGFloat](repeating: 0, count: nodes.count)
        // Descendant stacks center within their parent's subtree height.
        // The two root-side stacks then align their first/last branch roots.
        @discardableResult func arrange(_ index: Int) -> CGFloat {
            var cursor: CGFloat = 0
            for child in nodes[index].children {
                let height = arrange(child)
                centers[child].y += cursor
                cursor += height + 20
            }
            let childHeight = max(0, cursor - 20)
            let height = max(sizes[index].height, childHeight)
            centers[index].y = height / 2
            for child in nodes[index].children { centers[child].y += (height - childHeight) / 2 }
            heights[index] = height
            return height
        }
        for child in nodes[0].children { arrange(child) }
        var branch = [Int](repeating: 0, count: nodes.count)
        func place(_ index: Int, center: CGPoint, direction: CGFloat, tint: Int) {
            let offsetY = center.y - centers[index].y
            centers[index] = center; branch[index] = tint
            for child in nodes[index].children {
                let y = centers[child].y + offsetY
                place(child, center: CGPoint(x: center.x + direction * (sizes[index].width / 2 + 40 + sizes[child].width / 2), y: y), direction: direction, tint: tint)
            }
        }
        centers[0] = CGPoint(x: 0, y: 20)
        for side in 0...1 {
            let children = nodes[0].children.enumerated().filter { $0.offset % 2 == side }
            var cursor: CGFloat = 0, positions: [(Int, Int, CGFloat)] = []
            for (order, child) in children {
                positions.append((order, child, centers[child].y + cursor)); cursor += heights[child] + 20
            }
            guard let first = positions.first, let last = positions.last else { continue }
            let shift = sizes[first.1].height / 2 - (first.2 + last.2) / 2
            let direction: CGFloat = side == 0 ? -1 : 1
            for (order, child, y) in positions {
                place(child, center: CGPoint(x: direction * (sizes[0].width / 2 + 71 + sizes[child].width / 2), y: y + shift), direction: direction, tint: order % 8)
            }
        }
        var commands: [MermaidCommand] = []
        // Edges precede every node and follow source preorder.
        for child in nodes.indices.dropFirst() {
            guard let parent = nodes[child].parent else { continue }
            let direction: CGFloat = centers[child].x < 0 ? -1 : 1
            let a = CGPoint(x: centers[parent].x + direction * sizes[parent].width / 2, y: centers[parent].y)
            let b = CGPoint(x: centers[child].x - direction * sizes[child].width / 2, y: centers[child].y)
            var ancestor = child
            while let p = nodes[ancestor].parent, p != 0 { ancestor = p }
            let depth = nodes[child].indent - nodes[ancestor].indent
            let width = 11 - CGFloat(depth) * 3
            let sourceRadius = (nodes[parent].shape == .cloud || nodes[parent].shape == .bang) ? min(sizes[parent].width,sizes[parent].height) / 2 : sizes[parent].width / 2
            let targetRadius = (nodes[child].shape == .cloud || nodes[child].shape == .bang) ? min(sizes[child].width,sizes[child].height) / 2 : sizes[child].width / 2
            let clippedA = CGPoint(x: centers[parent].x + direction * sourceRadius, y: a.y)
            let clippedB = CGPoint(x: centers[child].x - direction * targetRadius, y: b.y)
            commands.append(.path(branchPath(clippedA, clippedB,
                                            control1: CGPoint(x: a.x + direction * 30, y: a.y),
                                            control2: CGPoint(x: b.x - direction * 30, y: b.y)), fill: nil,
                                  stroke: palette.color(tint: 36 + branch[child]), width: width > 0 ? width : 3, dash: []))
        }
        var bounds = CGRect.null
        for index in nodes.indices {
            let nominal = nominalSize(labels[index].size, shape: nodes[index].shape)
            let rect = CGRect(x: centers[index].x - nominal.width / 2, y: centers[index].y - nominal.height / 2, width: nominal.width, height: nominal.height)
            let fill = index == 0 ? palette.nodeFill : palette.color(tint: 28 + branch[index])
            let stroke = palette.nodeStroke
            let path = nodePath(rect, shape: nodes[index].shape)
            bounds = bounds.union(path.boundingBoxOfPath)
            switch nodes[index].shape {
            case .circle: commands.append(.ellipse(rect, fill: fill, stroke: stroke, width: 1))
            case .square, .rounded: commands.append(.roundRect(rect, radius: nodes[index].shape == .rounded ? 5 : 0, fill: fill, stroke: stroke, width: 1))
            default: commands.append(.path(path, fill: fill, stroke: stroke, width: 1, dash: []))
            }
            if nodes[index].shape == .plain {
                commands.append(line(CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), color: stroke, width: 3))
            }
            var y = centers[index].y - labels[index].size.height / 2
            for (text, measured) in labels[index].lines {
                let textRect = CGRect(x: centers[index].x - measured.width / 2, y: y, width: measured.width, height: measured.height)
                if index == 0 { commands.append(.text(text, textRect, role: 6)) }
                else { commands.append(.coloredText(text, textRect, role: 6, color: palette.color(tint: 44))) }
                y += measured.height
            }
        }
        return MermaidScene(bounds: bounds.insetBy(dx: -10, dy: -10), commands: commands)
    }

    private static func branchPath(_ a: CGPoint, _ b: CGPoint, control1 c: CGPoint, control2 d: CGPoint) -> CGPath {
        let p = CGMutablePath()
        func blend(_ terms: [(CGPoint, CGFloat)], divisor: CGFloat) -> CGPoint {
            CGPoint(x: terms.reduce(0) { $0 + $1.0.x * $1.1 } / divisor,
                    y: terms.reduce(0) { $0 + $1.0.y * $1.1 } / divisor)
        }
        p.move(to: a); p.addLine(to: blend([(a,5),(c,1)], divisor: 6))
        p.addCurve(to: blend([(a,1),(c,4),(d,1)], divisor: 6), control1: blend([(a,2),(c,1)], divisor: 3), control2: blend([(a,1),(c,2)], divisor: 3))
        p.addCurve(to: blend([(c,1),(d,4),(b,1)], divisor: 6), control1: blend([(c,2),(d,1)], divisor: 3), control2: blend([(c,1),(d,2)], divisor: 3))
        p.addCurve(to: blend([(d,1),(b,5)], divisor: 6), control1: blend([(d,2),(b,1)], divisor: 3), control2: blend([(d,1),(b,2)], divisor: 3))
        p.addLine(to: b); return p
    }

    private static func nodePath(_ rect: CGRect, shape: Shape) -> CGPath {
        let p = CGMutablePath(), x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        switch shape {
        case .square: p.addRect(rect)
        case .rounded: p.addRoundedRect(in: rect, cornerWidth: 5, cornerHeight: 5)
        case .circle: p.addEllipse(in: rect)
        case .hexagon:
            p.addLines(between: [CGPoint(x: x+h/4,y:y+h),CGPoint(x:x+w-h/4,y:y+h),CGPoint(x:x+w,y:y+h/2),CGPoint(x:x+w-h/4,y:y),CGPoint(x:x+h/4,y:y),CGPoint(x:x,y:y+h/2)]); p.closeSubpath()
        case .plain:
            // Native mindmap corners use a quadratic-to-cubic 2/3 conversion,
            // unlike CGPath's circular rounded-rectangle approximation.
            let r: CGFloat = 5
            p.move(to: CGPoint(x:x,y:y+h-r)); p.addLine(to: CGPoint(x:x,y:y+r))
            p.addCurve(to: CGPoint(x:x+r,y:y), control1: CGPoint(x:x,y:y+r/3), control2: CGPoint(x:x+r/3,y:y))
            p.addLine(to: CGPoint(x:x+w-r,y:y)); p.addCurve(to: CGPoint(x:x+w,y:y+r), control1: CGPoint(x:x+w-r/3,y:y), control2: CGPoint(x:x+w,y:y+r/3))
            p.addLine(to: CGPoint(x:x+w,y:y+h-r)); p.addCurve(to: CGPoint(x:x+w-r,y:y+h), control1: CGPoint(x:x+w,y:y+h-r/3), control2: CGPoint(x:x+w-r/3,y:y+h))
            p.addLine(to: CGPoint(x:x+r,y:y+h)); p.addCurve(to: CGPoint(x:x,y:y+h-r), control1: CGPoint(x:x+r/3,y:y+h), control2: CGPoint(x:x,y:y+h-r/3)); p.closeSubpath()
        case .bang, .cloud:
            func point(_ a: CGFloat, _ b: CGFloat) -> CGPoint { CGPoint(x: rect.midX + a*w, y: rect.midY + b*h) }
            var current = point(-0.5,-0.5)
            p.move(to: current)
            func arc(_ target: CGPoint, radius: CGFloat, sweep: Bool) {
                circularArc(p, from: current, to: target, radius: radius, sweep: sweep); current = target
            }
            if shape == .bang {
                for (a,b,r) in [(-0.25,-0.6,0.15),(0,-0.6,0.15),(0.25,-0.6,0.15),(0.5,-0.5,0.15),
                                (0.65,-0.17,0.15),(0.65,0.17,0.12),(0.5,0.5,0.15),
                                (0.25,0.65,0.15),(0,0.65,0.15),(-0.25,0.65,0.15),(-0.5,0.5,0.15),
                                (-0.6,0.17,0.15),(-0.6,-0.17,0.12),(-0.5,-0.5,0.15)] {
                    arc(point(CGFloat(a),CGFloat(b)), radius: CGFloat(r)*w, sweep: false)
                }
            } else {
                arc(CGPoint(x: rect.midX-w/4,y:y-w*0.1), radius: w*0.15, sweep: true)
                arc(CGPoint(x: rect.midX+w*0.15,y:y-w*0.2), radius: w*0.35, sweep: true)
                arc(point(0.5,-0.5), radius: w*0.25, sweep: true)
                arc(point(0.65,-0.15), radius: w*0.15, sweep: true)
                arc(point(0.5,0.5), radius: w*0.2, sweep: true)
                // The shipped cloud lobe is an ellipse rotated one degree,
                // making its quarter-turn split into two cubic segments.
                ellipticalArc(p, from: current,
                              to: CGPoint(x:rect.midX+w/4,y:rect.maxY+w*0.15),
                              radiusX: w*0.25, radiusY: w*0.15, rotation: .pi/180, sweep: true)
                current = CGPoint(x:rect.midX+w/4,y:rect.maxY+w*0.15)
                arc(CGPoint(x:rect.midX-w/4,y:rect.maxY+w*0.15), radius: w*0.35, sweep: true)
                arc(point(-0.5,0.5), radius: w*0.15, sweep: true)
                arc(point(-0.6,0.15), radius: w*0.15, sweep: true)
                arc(point(-0.5,-0.5), radius: w*0.2, sweep: true)
            }
            p.addLine(to: current); p.addLine(to: current); p.closeSubpath()
        }
        return p
    }

    /// SVG endpoint circular arcs with adaptive cubic subdivision.
    /// The radius correction is required for narrow labels and tall lobes.
    private static func circularArc(_ path: CGMutablePath, from a: CGPoint, to b: CGPoint, radius: CGFloat, sweep: Bool) {
        ellipticalArc(path, from: a, to: b, radiusX: radius, radiusY: radius, rotation: 0, sweep: sweep)
    }

    private static func ellipticalArc(_ path: CGMutablePath, from a: CGPoint, to b: CGPoint,
                                      radiusX: CGFloat, radiusY: CGFloat, rotation: CGFloat, sweep: Bool) {
        let cosine = cos(rotation), sine = sin(rotation)
        let dx = (a.x-b.x)/2, dy = (a.y-b.y)/2
        let x = cosine*dx+sine*dy, y = -sine*dx+cosine*dy
        guard x != 0 || y != 0 else { return }
        var rx = radiusX, ry = radiusY
        let correction = x*x/(rx*rx)+y*y/(ry*ry)
        if correction > 1 { rx *= sqrt(correction); ry *= sqrt(correction) }
        let numerator = rx*rx*ry*ry-rx*rx*y*y-ry*ry*x*x
        let denominator = rx*rx*y*y+ry*ry*x*x
        let factor = sqrt(max(0,numerator/denominator)) * (sweep ? 1 : -1)
        let cx = factor*rx*y/ry, cy = -factor*ry*x/rx
        let center = CGPoint(x:(a.x+b.x)/2+cosine*cx-sine*cy,y:(a.y+b.y)/2+sine*cx+cosine*cy)
        var start = atan2((y-cy)/ry,(x-cx)/rx)
        var delta = atan2((-y-cy)/ry,(-x-cx)/rx)-start
        if sweep && delta < 0 { delta += 2 * .pi }
        if !sweep && delta > 0 { delta -= 2 * .pi }
        // The native path adapter bounds cubic radial error at 0.001pt.
        // Circle cubic error is approximately radius * angle^6 / 55296;
        // the resulting subdivision depends on absolute dimensions.
        let maximumSweep = pow(55.296 / max(rx,ry), 1.0/6.0)
        var count = 1
        while abs(delta) / CGFloat(count) > maximumSweep { count *= 2 }
        let step = delta/CGFloat(count)
        func point(_ angle: CGFloat) -> CGPoint {
            CGPoint(x:center.x+cosine*rx*cos(angle)-sine*ry*sin(angle),
                    y:center.y+sine*rx*cos(angle)+cosine*ry*sin(angle))
        }
        func tangent(_ angle: CGFloat) -> CGPoint {
            CGPoint(x:-cosine*rx*sin(angle)-sine*ry*cos(angle),
                    y:-sine*rx*sin(angle)+cosine*ry*cos(angle))
        }
        for index in 0..<count {
            let end = start+step, coefficient = 4/3*tan(step/4)
            let p0 = point(start), p1 = point(end), d0 = tangent(start), d1 = tangent(end)
            path.addCurve(to:index == count-1 ? b : p1,
                          control1:CGPoint(x:p0.x+coefficient*d0.x,y:p0.y+coefficient*d0.y),
                          control2:CGPoint(x:p1.x-coefficient*d1.x,y:p1.y-coefficient*d1.y))
            start = end
        }
    }
}
