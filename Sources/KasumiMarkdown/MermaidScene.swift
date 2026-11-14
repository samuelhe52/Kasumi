import Foundation
import CoreGraphics
import CoreText

enum MermaidError: Error, Equatable {
    case unsupported(line: Int), syntax(line: Int), tooLarge, unsupportedType(String), unknownType, empty

    var explanation: String {
        switch self {
        case .unsupported(let line): return "unsupported construct · line \(line)"
        case .syntax(let line): return "syntax · line \(line)"
        case .tooLarge: return "too large"
        case .unsupportedType(let type): return "unsupported diagram type (\(type))"
        case .unknownType: return "unknown diagram type"
        case .empty: return "empty diagram"
        }
    }
}

enum MermaidCommand {
    case path(CGPath, fill: CGColor?, stroke: CGColor?, width: CGFloat, dash: [CGFloat])
    case roundRect(CGRect, radius: CGFloat, fill: CGColor?, stroke: CGColor?, width: CGFloat, dash: [CGFloat] = [])
    case ellipse(CGRect, fill: CGColor?, stroke: CGColor?, width: CGFloat)
    /// `role` is the font role from a native measurement request (0...16).
    case text(String, CGRect, role: Int)
    case coloredText(String, CGRect, role: Int, color: CGColor)
}

/// Vector commands in a top-left, downward-positive space.
struct MermaidScene {
    var bounds: CGRect
    var commands: [MermaidCommand]
    var textStyle: MermaidTextStyle? = nil
    var theme: DocumentTheme? = nil

    func draw(in context: CGContext, size: CGFloat, fontFamily: String, dark: Bool) {
        let textMetrics = textStyle ?? .uniform(size: size, fontFamily: fontFamily)
        func paint(_ path: CGPath, fill: CGColor?, stroke: CGColor?, width: CGFloat, dash: [CGFloat] = []) {
            context.saveGState()
            context.addPath(path)
            if let fill { context.setFillColor(fill) }
            if let stroke { context.setStrokeColor(stroke) }
            context.setLineWidth(width)
            context.setLineDash(phase: 0, lengths: dash)
            context.setLineJoin(.round)
            if fill != nil && stroke != nil { context.drawPath(using: .fillStroke) }
            else if fill != nil { context.fillPath() }
            else if stroke != nil { context.strokePath() }
            context.restoreGState()
        }
        for command in commands {
            switch command {
            case let .path(path, fill, stroke, width, dash): paint(path, fill: fill, stroke: stroke, width: width, dash: dash)
            case let .roundRect(rect, radius, fill, stroke, width, dash):
                paint(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil), fill: fill, stroke: stroke, width: width, dash: dash)
            case let .ellipse(rect, fill, stroke, width):
                paint(CGPath(ellipseIn: rect, transform: nil), fill: fill, stroke: stroke, width: width)
            case let .text(text, rect, role):
                textMetrics.draw(text, in: rect, role: role, color: MermaidPalette(dark: dark, theme: theme).text, context: context)
            case let .coloredText(text, rect, role, color):
                textMetrics.draw(text, in: rect, role: role, color: color, context: context)
            }
        }
    }
}

enum MermaidText {
    static func measure(_ text: String, role: Int, size: CGFloat, fontFamily: String) -> CGSize {
        MermaidTextStyle.uniform(size: size, fontFamily: fontFamily).measure(text, role: role)
    }
}

/// Semantic native paint slots. The static Mono defaults preserve the uniform
/// oracle policy; an instance carries its selected document palette explicitly.
struct MermaidPalette {
    let dark: Bool
    var theme: DocumentTheme? = nil

    private func color(_ key: String, fallback: CGColor) -> CGColor { theme?.color(key)?.cgColor ?? fallback }
    var text: CGColor { color("text", fallback: Self.text(dark: dark)) }
    var edge: CGColor { text }
    var nodeFill: CGColor { color("diagram_node_fill", fallback: Self.nodeFill(dark: dark)) }
    var nodeStroke: CGColor { color("diagram_node_stroke", fallback: Self.nodeStroke(dark: dark)) }
    var badgeText: CGColor { color("diagram_badge_text", fallback: Self.badgeText(dark: dark)) }
    var labelBackground: CGColor { color("diagram_edge_label_background", fallback: Self.labelBackground(dark: dark)) }
    var noteFill: CGColor { color("diagram_note_fill", fallback: Self.noteFill(dark: dark)) }
    var blockFill: CGColor { color("diagram_block_fill", fallback: Self.blockFill(dark: dark)) }
    func color(tint: Int) -> CGColor {
        let key: String
        switch tint {
        case 1...24:
            let hues = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"]
            let shades = ["tint", "mid", "deep"]
            key = "diagram_accent_\(hues[(tint - 1) / 3])_\(shades[(tint - 1) % 3])"
        case 25: key = "diagram_accent_neutral_mid"
        case 26: key = "diagram_accent_neutral_deep"
        case 27: key = "diagram_accent_ink"
        case 28...35: key = "diagram_series_\(tint - 27)_fill"
        case 36...43: key = "diagram_series_\(tint - 35)_edge"
        case 44: key = "diagram_series_ink"
        default: return text
        }
        return color(key, fallback: Self.color(tint: tint, dark: dark))
    }
    static func hex(_ value: String) -> CGColor {
        let rgb = UInt32(value.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        return CGColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
    static func text(dark: Bool) -> CGColor { hex(dark ? "C7C7C7" : "313131") }
    static func nodeFill(dark: Bool) -> CGColor { hex(dark ? "1D1D1D" : "EDEDEB") }
    static func nodeStroke(dark: Bool) -> CGColor { hex(dark ? "8B8B8B" : "7C7C7C") }
    static func edge(dark: Bool) -> CGColor { text(dark: dark) }
    static func badgeText(dark: Bool) -> CGColor { hex(dark ? "262626" : "FAFAF8") }
    static func labelBackground(dark: Bool) -> CGColor { hex(dark ? "262626" : "FAFAF8") }
    static func noteFill(dark: Bool) -> CGColor { hex(dark ? "3C3C3C" : "DDDDDB") }
    static func blockFill(dark: Bool) -> CGColor { hex(dark ? "2C2C2C" : "F1F1EF") }
    static func color(tint: Int, dark: Bool) -> CGColor {
        let light = ["F9C6C0","FFADA6","C14E49", "F1CAAB","F9B47A","AD5F00", "F2EBBD","D6C770","837400", "D4F7D4","ABEDAC","00711B", "BBF7F6","60DCDC","008181", "DCEBFF","9FC9FF","2C74CA", "D5C7F1","BBA0EC","744CAD", "FFE1F1","FDADDA","B44E8D", "C5C5C5","313131","FAFAF8"]
        let night = ["4D2523","742725","DF6862", "482A0F","653500","D1760D", "3A3307","584D00","A08D00", "2C4A2D","1E5E25","5AB660", "003B3B","005959","009D9E", "2B4361","1C4D87","468EE5", "372A4C","482D6F","B58FF6", "5B374B","79335E","D169A7", "4D4D4D","C7C7C7","262626"]
        if (28...43).contains(tint) {
            let seriesLight = ["6CA8F5","F18E6A","4FC593","E3A648","F08BB0","6FB66A","928FE9","EF867F", "286EC3","B3481C","008359","956300","AC456F","2E832A","665EC1","B64340"]
            let seriesDark = ["508CD7","CB6C4A","1DA273","C38523","C96686","468C41","8F86DF","D8706E", "85BAFF","FF9874","5CD1A0","EEA83F","FF8FB2","7BCF74","B2ACFF","FF9592"]
            return hex((dark ? seriesDark : seriesLight)[tint - 28])
        }
        if tint == 44 { return CGColor(gray: 0, alpha: 1) }
        guard (1...27).contains(tint) else { return text(dark: dark) }
        return hex((dark ? night : light)[tint - 1])
    }
}

enum MermaidTypesetter {
    static func layout(_ source: String, size: CGFloat, fontFamily: String, dark: Bool, textStyle: MermaidTextStyle? = nil, theme: DocumentTheme? = nil) throws -> MermaidScene {
        guard source.utf8.count <= 65_536 else { throw MermaidError.tooLarge }
        let prepared = try MermaidSource.prepare(source)
        let header = prepared.source.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        var scene: MermaidScene
        do {
        if header.hasPrefix("graph ") || header.hasPrefix("flowchart ") {
            scene = try MermaidFlow.layout(source: prepared.source, size: size, fontFamily: fontFamily, dark: dark, textStyle: textStyle, theme: theme)
        } else if header.hasPrefix("sequenceDiagram") {
            scene = try MermaidSequence.layout(source: prepared.source, size: size, fontFamily: fontFamily, dark: dark, textStyle: textStyle, theme: theme)
        } else if header.hasPrefix("stateDiagram") {
            scene = try MermaidState.layout(source: prepared.source, size: size, fontFamily: fontFamily, dark: dark, textStyle: textStyle, theme: theme)
        } else if header.hasPrefix("classDiagram") || header.hasPrefix("erDiagram") {
            scene = try MermaidEntities.layout(source: prepared.source, size: size, fontFamily: fontFamily, dark: dark, textStyle: textStyle, theme: theme)
        } else if header.hasPrefix("pie") {
            scene = try MermaidPie.layout(source: prepared.source, size: size, fontFamily: fontFamily, dark: dark, textStyle: textStyle, fallbackTitle: prepared.title, theme: theme)
        } else if header == "mindmap" || header == "treeView-beta" {
            scene = try MermaidTree.layout(source: prepared.source, size: size, fontFamily: fontFamily, dark: dark, textStyle: textStyle, theme: theme)
        } else {
            let name = header.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            let unsupported = ["gantt", "xychart-beta", "xychart", "radar-beta", "quadrantChart", "timeline", "sankey-beta", "packet-beta", "C4Context", "C4Container", "gitGraph", "block-beta", "journey", "requirementDiagram", "treemap-beta", "architecture-beta", "zenuml", "kanban"]
            if unsupported.contains(name) { throw MermaidError.unsupportedType(name) }
            throw MermaidError.unknownType
        }
        } catch let error as MermaidError {
            switch error {
            case .syntax(let line): throw MermaidError.syntax(line: line + prepared.lineOffset)
            case .unsupported(let line): throw MermaidError.unsupported(line: line + prepared.lineOffset)
            default: throw error
            }
        }
        if let title = prepared.title, !title.isEmpty, !header.hasPrefix("pie"), header != "mindmap", header != "treeView-beta" {
            let sequence = header.hasPrefix("sequenceDiagram")
            let role = header.hasPrefix("graph ") || header.hasPrefix("flowchart ") || header.hasPrefix("stateDiagram") ? 10 : 0
            let measured = (textStyle ?? .uniform(size: size, fontFamily: fontFamily)).measure(title, role: role)
            let x: CGFloat
            if sequence {
                x = scene.commands.compactMap { command -> CGFloat? in
                    if case let .text(_, rect, fontRole) = command, fontRole == 2 { return rect.midX }
                    return nil
                }.min() ?? 75
            } else { x = scene.bounds.midX - measured.width / 2 }
            let rect = CGRect(x: x, y: (role == 10 ? -31.3 : -30.6) - measured.height / 2, width: measured.width, height: measured.height)
            scene.commands.append(.text(title, rect, role: role)); scene.bounds = scene.bounds.union(rect)
            if sequence { scene.bounds = scene.bounds.union(CGRect(x: scene.bounds.minX, y: -50, width: scene.bounds.width, height: 0)) }
        }
        scene.textStyle = textStyle
        scene.theme = theme
        return scene
    }
}

enum MermaidSource {
    static func prepare(_ source: String) throws -> (source: String, title: String?, lineOffset: Int) {
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        if !lines.isEmpty { lines[0] = lines[0].replacingOccurrences(of: "\u{FEFF}", with: "") }
        var start = 0, title: String?
        while start < lines.count && lines[start].trimmingCharacters(in: .whitespaces).isEmpty { start += 1 }
        if start < lines.count && lines[start].trimmingCharacters(in: .whitespaces) == "---" {
            guard start == 0 else { throw MermaidError.syntax(line: start + 1) }
            start += 1
            while start < lines.count && lines[start].trimmingCharacters(in: .whitespaces) != "---" {
                let value = lines[start].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("title:") { title = String(value.dropFirst(6)).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                start += 1
            }
            guard start < lines.count else { throw MermaidError.syntax(line: 1) }
            start += 1
        }
        var result: [String] = [], lineOffset = start
        for index in start..<lines.count {
            let value = lines[index].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("%%{") { throw MermaidError.unsupported(line: index + 1) }
            if value.hasPrefix("%%") || value.isEmpty {
                if result.isEmpty { lineOffset = index + 1 } else { result.append("") }
                continue
            }
            if result.isEmpty && value == "---" { throw MermaidError.syntax(line: index + 1) }
            result.append(result.isEmpty ? value : lines[index])
        }
        guard result.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw MermaidError.empty }
        return (result.joined(separator: "\n"), title, lineOffset)
    }
}
