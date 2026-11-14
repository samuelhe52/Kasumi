import AppKit

/// Sequence parsing and vector geometry, fitted to recorded measurements of
/// authored diagrams.
enum MermaidSequence {
    private struct Participant {
        var id: String
        var label: String
        var actor: Bool
    }
    private enum Arrow: String {
        case line = "->", dashedLine = "-->", triangle = "->>", dashedTriangle = "-->>"
        case cross = "-x", dashedCross = "--x", open = "-)", dashedOpen = "--)"
        case both = "<<->>", dashedBoth = "<<-->>"
        var dashed: Bool { rawValue.contains("--") }
        var head: Bool { self != .line && self != .dashedLine }
        var double: Bool { self == .both || self == .dashedBoth }
    }
    private final class Frame {
        let kind: String
        let label: String
        let line: Int
        var actors = Set<Int>()
        var nested: [Frame] = []
        var top: CGFloat = 0
        var bottom: CGFloat = 0
        var rect = CGRect.zero
        var branches: [(CGFloat, String)] = []
        init(_ kind: String, _ label: String, _ line: Int) { self.kind = kind; self.label = label; self.line = line }
    }
    private enum Event {
        case message(Int, Int, Arrow, String, Int)
        case note(String, Int, Int, String)
        case activate(Int), deactivate(Int)
        case begin(Frame), branch(Frame, String), end(Frame)
        case number(Int?, Int)
    }
    private struct Parsed { var actors: [Participant]; var events: [Event] }
    private struct PositionedMessage {
        var from: Int; var to: Int; var arrow: Arrow; var label: String
        var x1: CGFloat; var x2: CGFloat; var y: CGFloat; var labelTop: CGFloat; var number: Int?
    }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let result = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func label(_ text: String, line: Int) throws -> String {
        guard text.utf8.count <= 2048 else { throw MermaidError.tooLarge }
        let result = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        if result.contains("<") || result.contains(">") || result.contains("#") { throw MermaidError.unsupported(line: line) }
        return result
    }

    private static func parse(_ source: String) throws -> Parsed {
        guard source.utf8.count <= 65_536 else { throw MermaidError.tooLarge }
        var actors: [Participant] = [], indices: [String: Int] = [:], events: [Event] = [], frames: [Frame] = []
        var active: [Int: Int] = [:]
        func actor(_ id: String) throws -> Int {
            guard !id.isEmpty, !id.contains(where: { $0.isWhitespace }), !id.contains("@{") else { throw MermaidError.syntax(line: 1) }
            if let index = indices[id] { return index }
            guard actors.count < 4096 else { throw MermaidError.tooLarge }
            let i = actors.count; indices[id] = i; actors.append(Participant(id: id, label: id, actor: false)); return i
        }
        func touch(_ ids: [Int]) { for frame in frames { frame.actors.formUnion(ids) } }
        var sawHeader = false
        for (lineIndex, rawLine) in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated() {
            let line = lineIndex + 1
            if trim(rawLine).hasPrefix("%%{") { throw MermaidError.unsupported(line: line) }
            if trim(rawLine).hasPrefix("%%") { continue }
            for part in rawLine.components(separatedBy: ";") {
                let text = trim(part)
                if text.isEmpty { continue }
                if !sawHeader {
                    guard text == "sequenceDiagram" else { throw MermaidError.unknownType }
                    sawHeader = true; continue
                }
                guard events.count < 4096 else { throw MermaidError.tooLarge }
                if text.hasPrefix("%%") { break }
                if let m = match("^(participant|actor)\\s+(\\S+?)(?:\\s+as\\s+(.+))?$", text) {
                    if m[1].contains("@{") { throw MermaidError.unsupported(line: line) }
                    let i = try actor(m[1]); actors[i].actor = m[0] == "actor"
                    actors[i].label = try label(m[2].isEmpty ? m[1] : m[2], line: line)
                } else if let m = match("^([^\\s:<>]+?)\\s*(<<-->>|<<->>|-->>|->>|--x|-x|--\\)|-\\)|-->|->)\\s*([+-]?)([^:]+):\\s*(.*)$", text) {
                    let from = try actor(trim(m[0])), to = try actor(trim(m[3]))
                    let activation = m[2] == "+" ? 1 : m[2] == "-" ? -1 : 0
                    if activation < 0 {
                        guard active[from, default: 0] > 0 else { throw MermaidError.syntax(line: line) }
                        active[from, default: 0] -= 1
                    } else if activation > 0 { active[to, default: 0] += 1 }
                    touch([from, to]); events.append(.message(from, to, Arrow(rawValue: m[1])!, try label(m[4], line: line), activation))
                } else if let m = match("(?i)^note\\s+(left of|right of|over)\\s+([^:]+):\\s*(.*)$", text) {
                    let ids = m[1].components(separatedBy: ",").map(trim)
                    guard ids.count <= 2, ids.count == 1 || m[0].lowercased() == "over" else { throw MermaidError.syntax(line: line) }
                    let first = try actor(ids[0]), last = try actor(ids.last!)
                    touch([first, last]); events.append(.note(m[0].lowercased(), first, last, try label(m[2], line: line)))
                } else if let m = match("^(activate|deactivate)\\s+(\\S+)$", text) {
                    let i = try actor(m[1]); touch([i])
                    if m[0] == "activate" { active[i, default: 0] += 1; events.append(.activate(i)) }
                    else {
                        guard active[i, default: 0] > 0 else { throw MermaidError.syntax(line: line) }
                        active[i, default: 0] -= 1; events.append(.deactivate(i))
                    }
                } else if text == "autonumber off" { events.append(.number(nil, 1))
                } else if let m = match("^autonumber(?:\\s+(\\d+)(?:\\s+(\\d+))?)?$", text) {
                    guard let start = Int(m[0].isEmpty ? "1" : m[0]), let step = Int(m[1].isEmpty ? "1" : m[1]) else { throw MermaidError.tooLarge }
                    events.append(.number(start, step))
                } else if let m = match("^(loop|alt|opt|par|critical|break|rect)(?:\\s+(.*))?$", text) {
                    let frame = Frame(m[0], try label(m[1], line: line), line)
                    if let parent = frames.last { parent.nested.append(frame) }
                    frames.append(frame); events.append(.begin(frame))
                } else if let m = match("^(else|and|option)(?:\\s+(.*))?$", text) {
                    guard let frame = frames.last,
                          (m[0] == "else" && frame.kind == "alt") || (m[0] == "and" && frame.kind == "par") || (m[0] == "option" && frame.kind == "critical") else { throw MermaidError.syntax(line: line) }
                    events.append(.branch(frame, try label(m[1], line: line)))
                } else if text == "end" {
                    guard let frame = frames.popLast() else { throw MermaidError.syntax(line: line) }
                    events.append(.end(frame))
                } else if text.hasPrefix("accTitle:") || text.hasPrefix("accDescr:") || text.hasPrefix("par_over") || ["box", "create", "destroy", "link", "links", "properties", "details", "title"].contains(where: { text == $0 || text.hasPrefix($0 + " ") }) {
                    throw MermaidError.unsupported(line: line)
                } else { throw MermaidError.syntax(line: line) }
            }
        }
        guard sawHeader else { throw MermaidError.empty }
        if let frame = frames.first { throw MermaidError.syntax(line: frame.line) }
        return Parsed(actors: actors, events: events)
    }

    static func layout(source: String, size: CGFloat, fontFamily: String, dark: Bool, textStyle: MermaidTextStyle? = nil, theme: DocumentTheme? = nil) throws -> MermaidScene {
        let palette = MermaidPalette(dark: dark, theme: theme)
        let textMetrics = textStyle ?? .uniform(size: size, fontFamily: fontFamily)
        let parsed = try parse(source)
        if parsed.actors.isEmpty { return MermaidScene(bounds: CGRect(x: -50, y: -10, width: 100, height: 41), commands: [], textStyle:textMetrics, theme: theme) }
        func measured(_ text: String, _ role: Int = 0) -> CGSize { textMetrics.measure(text, role: role) }
        func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }
        func textSize(_ text: String, _ role: Int = 0) -> CGSize {
            let sizes = lines(text).map { measured($0, role) }
            return CGSize(width: sizes.map(\.width).max() ?? 0, height: role == 2 ? CGFloat(sizes.count)*16 : sizes.reduce(0) { $0 + $1.height })
        }
        let widths = parsed.actors.map { max(150, (textSize($0.label, 2).width + 20).rounded()) }
        // Participant boxes and their 16-unit label pitch remain fixed even
        // when supplied glyph measurements are taller than those slots.
        let headerHeight:CGFloat = 65
        var centers: [CGFloat] = []
        for i in widths.indices { centers.append(i == 0 ? widths[i] / 2 : centers[i - 1] + (widths[i - 1] + widths[i]) / 2 + 50) }
        // Native measurement rounds participant widths and spacing constraints
        // to integer units, while text positions retain subpixel precision.
        for event in parsed.events {
            if case let .message(from, to, _, label, _) = event, from != to {
                let a = min(from, to), b = max(from, to), needed = textSize(label).width.rounded() + 70
                let delta = max(0, needed - (centers[b] - centers[a]))
                for i in b..<centers.count { centers[i] += delta }
            } else if case let .note(position, first, last, label) = event, first == last, position == "over", first + 1 < centers.count {
                let noteWidth = max(150, (textSize(label, 1).width + 20).rounded())
                let delta = max(0, centers[first] + noteWidth / 2 + 50 - centers[first + 1])
                for i in (first + 1)..<centers.count { centers[i] += delta }
            }
        }
        let fill = palette.nodeFill, stroke = palette.nodeStroke
        let edge = palette.edge, noteFill = palette.noteFill
        var cursor = headerHeight
        var messages: [PositionedMessage] = [], noteCommands: [MermaidCommand] = [], frameCommands: [MermaidCommand] = []
        var background: [MermaidCommand] = [], activationCommands: [MermaidCommand] = []
        var active: [Int: [(CGFloat, CGFloat)]] = [:]
        var number: Int?, numberStep = 1
        var minX: CGFloat = 0, maxX: CGFloat = zip(centers, widths).map { $0 + $1 / 2 }.max() ?? 0
        func path(_ points: [CGPoint], close: Bool = false, fill: NSColor? = nil, stroke: NSColor? = nil, width: CGFloat = 1, dash: [CGFloat] = []) -> MermaidCommand {
            let path = CGMutablePath()
            if let first = points.first { path.move(to: first); for p in points.dropFirst() { path.addLine(to: p) } }
            if close { path.closeSubpath() }
            return .path(path, fill: fill, stroke: stroke, width: width, dash: dash)
        }
        func text(_ value: String, center: CGFloat, top: CGFloat, role: Int, color: NSColor? = nil) -> [MermaidCommand] {
            var top = top
            return lines(value).map { line in
                let m = measured(line, role)
                let rect = CGRect(x: center - m.width / 2, y: role == 2 ? top+8-m.height/2 : top, width: m.width, height: m.height)
                let command: MermaidCommand = color.map { .coloredText(line, rect, role: role, color: $0) } ?? .text(line, rect, role: role)
                top += role == 2 ? 16 : m.height; return command
            }
        }
        func activate(_ actor: Int, at y: CGFloat) {
            let depth = active[actor, default: []].count
            active[actor, default: []].append((y, centers[actor] - 5 + CGFloat(depth) * 5))
        }
        func deactivate(_ actor: Int, at y: CGFloat) {
            guard let start = active[actor]?.popLast() else { return }
            activationCommands.append(.roundRect(CGRect(x: start.1, y: start.0, width: 10, height: max(0, y - start.0)), radius: 0, fill: fill, stroke: stroke, width: 1))
        }
        func activationEdge(_ actor: Int, right: Bool) -> CGFloat {
            guard let stack = active[actor], !stack.isEmpty else { return centers[actor] + (right ? 1 : -1) }
            return right ? stack.last!.1 + 10 : stack.first!.1
        }
        func frameRect(_ frame: Frame) -> CGRect {
            var left = frame.actors.map { centers[$0] - 11 }.min() ?? 0
            var right = frame.actors.map { centers[$0] + 11 }.max() ?? 0
            for child in frame.nested where child.rect.width > 0 { left = min(left, child.rect.minX - 10); right = max(right, child.rect.maxX + 10) }
            return CGRect(x: left, y: frame.top, width: max(50, right - left), height: frame.bottom - frame.top)
        }
        for event in parsed.events {
            switch event {
            case let .number(start, step): number = start; numberStep = step
            case let .activate(actor): activate(actor, at: cursor)
            case let .deactivate(actor): deactivate(actor, at: cursor)
            case let .message(from, to, arrow, label, activation):
                // Message labels keep a fixed first-line center while the
                // arrow advances by both block height and one line of space.
                let h = textSize(label).height, lineHeight = measured(lines(label)[0]).height
                let y = cursor + h + lineHeight + 10
                let right = centers[to] >= centers[from]
                var x1 = activationEdge(from, right: right)
                var x2 = activationEdge(to, right: !right)
                if activation > 0, from != to { x2 += right ? -4 : 4 }
                if arrow.head { x2 += right ? -3 : 3 }
                if arrow.double { x1 += right ? 3 : -3 }
                messages.append(PositionedMessage(from: from, to: to, arrow: arrow, label: label, x1: x1, x2: x2, y: y, labelTop:cursor+31-lineHeight/2, number: number))
                cursor = y + (from == to ? 30 : 0)
                if let current = number {
                    let (next, overflow) = current.addingReportingOverflow(numberStep)
                    guard !overflow else { throw MermaidError.tooLarge }; number = next
                }
                if activation > 0 { activate(to, at: from == to ? cursor + 2 : y) }
                else if activation < 0 { deactivate(from, at: cursor) }
                if from == to { maxX = max(maxX, x1 + 75) }
            case let .note(position, first, last, label):
                let content = textSize(label, 1)
                let a = min(centers[first], centers[last]), b = max(centers[first], centers[last])
                let w = max((content.width + 20).rounded(), first == last ? 150 : b - a + 50)
                let x: CGFloat
                if position == "left of" { x = centers[first] - 25 - w }
                else if position == "right of" { x = centers[first] + 25 }
                else { x = (a + b - w) / 2 }
                let rect = CGRect(x: x, y: cursor + 10, width: w, height: content.height + 20)
                noteCommands.append(.roundRect(rect, radius: 0, fill: noteFill, stroke: stroke, width: 1))
                noteCommands += text(label, center: rect.midX, top: rect.minY + 21 - measured(lines(label)[0],1).height/2, role: 1)
                cursor = rect.maxY; minX = min(minX, rect.minX); maxX = max(maxX, rect.maxX)
            case let .begin(frame):
                frame.top = cursor + 10
                cursor += frame.kind == "rect" ? 20 : max(45,textSize(frame.label).height+25)
            case let .branch(frame, label):
                frame.branches.append((cursor + 15, label)); cursor += max(45,textSize(label).height+25)
            case let .end(frame):
                cursor += 10; frame.bottom = cursor; frame.rect = frameRect(frame)
                let rect = frame.rect
                minX = min(minX, rect.minX); maxX = max(maxX, rect.maxX)
                if frame.kind == "rect" {
                    // The core validates the authored color but its display
                    // command uses blockBackground's semantic fill channel.
                    let authored = try backgroundColor(frame.label, line: frame.line)
                    background.append(.roundRect(rect, radius: 0, fill: theme == nil ? authored : palette.blockFill, stroke: nil, width: 0))
                    continue
                }
                for pair in [(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY)),
                             (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)),
                             (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)),
                             (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY))] {
                    frameCommands.append(path([pair.0, pair.1], stroke: stroke, width: 2, dash: [2, 2]))
                }
                for (y, _) in frame.branches { frameCommands.append(path([CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)], stroke: stroke, width: 2, dash: [3, 3])) }
                frameCommands.append(path([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX + 50, y: rect.minY), CGPoint(x: rect.minX + 50, y: rect.minY + 13), CGPoint(x: rect.minX + 41.6, y: rect.minY + 20), CGPoint(x: rect.minX, y: rect.minY + 20)], close: true, fill: fill, stroke: stroke))
                frameCommands += text(frame.kind, center: rect.minX + 25, top: rect.minY + 13 - measured(frame.kind).height/2, role: 0)
                frameCommands += text(frame.label.isEmpty ? "" : "[\(frame.label)]", center: rect.midX + 25, top: rect.minY + 12.4 - measured(lines(frame.label)[0]).height/2, role: 0)
                for (y, label) in frame.branches { frameCommands += text(label.isEmpty ? "" : "[\(label)]", center: rect.midX, top: y + 12.4 - measured(lines(label)[0]).height/2, role: 0) }
            }
        }
        let footerY = cursor + 20
        var commands = background
        func participant(_ i: Int, at y: CGFloat) -> [MermaidCommand] {
            let rect = CGRect(x: centers[i] - widths[i] / 2, y: y, width: widths[i], height: headerHeight)
            return [.roundRect(rect, radius: 3, fill: fill, stroke: stroke, width: 1)] + text(parsed.actors[i].label, center: rect.midX, top: rect.midY - textSize(parsed.actors[i].label, 2).height / 2, role: 2)
        }
        func actor(_ i: Int, at y: CGFloat) -> [MermaidCommand] {
            let x = centers[i]
            var result: [MermaidCommand] = []
            for points in [[CGPoint(x:x,y:y+25),CGPoint(x:x,y:y+45)], [CGPoint(x:x-18,y:y+33),CGPoint(x:x+18,y:y+33)], [CGPoint(x:x-18,y:y+60),CGPoint(x:x,y:y+45)], [CGPoint(x:x,y:y+45),CGPoint(x:x+16,y:y+60)]] { result.append(path(points, stroke: stroke, width: 2)) }
            result.append(.ellipse(CGRect(x: x - 15, y: y - 5, width: 30, height: 30), fill: theme == nil ? nil : fill, stroke: stroke, width: 2))
            return result + text(parsed.actors[i].label, center: x, top: y + 67.5 - textSize(parsed.actors[i].label,2).height/2, role: 2)
        }
        for i in parsed.actors.indices.reversed() where !parsed.actors[i].actor { commands += participant(i, at: footerY) }
        for i in parsed.actors.indices.reversed() {
            commands.append(path([CGPoint(x: centers[i], y: parsed.actors[i].actor ? 80 : headerHeight), CGPoint(x: centers[i], y: footerY)], stroke: stroke, width: 2))
            commands += parsed.actors[i].actor ? actor(i, at: 0) : participant(i, at: 0)
        }
        // Outer activations paint first even when the inner interval closes first.
        activationCommands.sort { a, b in
            if case let .roundRect(ra, _, _, _, _, _) = a, case let .roundRect(rb, _, _, _, _, _) = b { return ra.minY < rb.minY }
            return false
        }
        commands += activationCommands + noteCommands + frameCommands
        func arrowHead(_ arrow: Arrow, at origin: CGPoint, vector: CGVector) -> MermaidCommand {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + x * vector.dx - y * vector.dy, y: origin.y + x * vector.dy + y * vector.dx)
            }
            if arrow == .cross || arrow == .dashedCross {
                let p = CGMutablePath()
                p.move(to: point(-4.5, -3.75)); p.addLine(to: point(3, 3.75))
                p.move(to: point(3, -3.75)); p.addLine(to: point(-4.5, 3.75))
                return .path(p, fill: nil, stroke: edge, width: 2, dash: [])
            } else if arrow == .open || arrow == .dashedOpen {
                return path([point(3.75, 0), point(-9.75, 9), point(-2.25, 0), point(-9.75, -9)], close: true, fill: edge, width: 0)
            }
            return path([point(-8.9, -5), point(2.1, 0), point(-7.9, 5)], close: true, fill: edge, stroke: edge)
        }
        for message in messages {
            let selfMessage = message.from == message.to
            let center = selfMessage ? message.x1 : ((message.x1 + message.x2) / 2).rounded()
            commands += text(message.label, center: center, top: message.labelTop, role: 0)
            let dash: [CGFloat] = message.arrow.dashed ? [3, 3] : []
            if selfMessage {
                let p = CGMutablePath(); p.move(to: CGPoint(x: message.x1, y: message.y))
                p.addCurve(to: CGPoint(x: message.x1, y: message.y + 20), control1: CGPoint(x: message.x1 + 60, y: message.y - 10), control2: CGPoint(x: message.x1 + 60, y: message.y + 30))
                commands.append(.path(p, fill: nil, stroke: edge, width: 1.5, dash: dash))
                if message.arrow.head {
                    // Marker follows the incoming tangent (-60,-10).
                    let length = sqrt(CGFloat(3700))
                    commands.append(arrowHead(message.arrow, at: CGPoint(x: message.x1, y: message.y + 20), vector: CGVector(dx: -60 / length, dy: -10 / length)))
                }
            } else {
                let direction: CGFloat = message.x2 > message.x1 ? 1 : -1
                let start = message.x1 + (message.number == nil ? 0 : 6)
                commands.append(path([CGPoint(x: start, y: message.y), CGPoint(x: message.x2, y: message.y)], stroke: edge, width: 1.5, dash: dash))
                if message.arrow.double { commands.append(arrowHead(message.arrow, at: CGPoint(x: message.x1, y: message.y), vector: CGVector(dx: -direction, dy: 0))) }
                if message.arrow.head { commands.append(arrowHead(message.arrow, at: CGPoint(x: message.x2, y: message.y), vector: CGVector(dx: direction, dy: 0))) }
            }
            if let number = message.number {
                let x = centers[message.from], y = message.y
                let value = String(number), role = value.count < 4 ? 3 : value.count < 6 ? 4 : 5
                // The reference fits badge digit counts to these three nominal sizes;
                // supplied metrics determine the actual ink-box height.
                let nominalSize:CGFloat = role == 3 ? 10.5 : role == 4 ? 7.875 : 6.125
                commands.append(.ellipse(CGRect(x:x-12,y:y-12,width:24,height:24), fill: edge, stroke: nil, width: 0))
                commands += text(value, center: x, top: y - measured(value,role).height/2 + 4 - nominalSize*0.4, role: role, color: palette.badgeText)
            }
        }
        for i in parsed.actors.indices.reversed() where parsed.actors[i].actor { commands += actor(i, at: footerY) }
        return MermaidScene(bounds: CGRect(x: minX - 50, y: -10, width: maxX - minX + 100, height: footerY + headerHeight + 21), commands: commands, textStyle:textMetrics, theme: theme)
    }

    private static func backgroundColor(_ value: String, line: Int) throws -> NSColor {
        if let m = match("^rgba?\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)(?:\\s*,\\s*([0-9.]+))?\\s*\\)$", value),
           let r = Double(m[0]), let g = Double(m[1]), let b = Double(m[2]), let a = Double(m[3].isEmpty ? "1" : m[3]),
           [r,g,b].allSatisfy({ (0...255).contains($0) }), (0...1).contains(a) {
            return NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
        }
        if value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil { return MermaidPalette.hex(value) }
        let named = ["blue":"0000FF", "red":"FF0000", "green":"008000", "yellow":"FFFF00", "white":"FFFFFF", "black":"000000", "gray":"808080", "grey":"808080", "lightblue":"ADD8E6", "transparent":"000000"]
        if let hex = named[value.lowercased()] { return MermaidPalette.hex(hex).withAlphaComponent(value.lowercased() == "transparent" ? 0 : 1) }
        throw MermaidError.unsupported(line: line)
    }
}
