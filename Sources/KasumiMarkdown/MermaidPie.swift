import AppKit

/// Native vector pie layout fitted to recorded reference cases.
/// Its fixed chart geometry is independent of the caller's text measurements.
enum MermaidPie {
    struct Section {
        var label: String
        var value: Double
    }
    struct Diagram {
        var sections: [Section]
        var title: String?
        var showData: Bool
    }

    static func layout(source: String, size: CGFloat, fontFamily: String, dark: Bool, textStyle: MermaidTextStyle? = nil, fallbackTitle: String? = nil, theme: DocumentTheme? = nil) throws -> MermaidScene {
        let palette = MermaidPalette(dark: dark, theme: theme)
        let textMetrics = textStyle ?? .uniform(size: size, fontFamily: fontFamily)
        var diagram = try parse(source)
        if diagram.title == nil { diagram.title = fallbackTitle }
        func measure(_ text: String, role: Int) -> CGSize {
            textMetrics.measure(text, role: role)
        }
        let stroke = palette.nodeStroke
        let ink = palette.color(tint: 44)
        let center = CGPoint(x: 225, y: 225), radius: CGFloat = 185
        var commands: [MermaidCommand] = [
            .ellipse(CGRect(x: 39, y: 39, width: 372, height: 372), fill: nil, stroke: stroke, width: 2)
        ]
        let total = diagram.sections.reduce(0) { $0 + $1.value }
        guard total.isFinite else { throw MermaidError.tooLarge }
        let visible = diagram.sections.enumerated().filter { total > 0 && $0.element.value / total >= 0.01 }
        let visibleTotal = visible.reduce(0) { $0 + $1.element.value }
        var angle = -CGFloat.pi / 2
        var percentLabels: [(String, CGRect)] = []
        for (index, section) in visible {
            let fraction = section.value / visibleTotal
            let sweep = CGFloat(fraction) * 2 * .pi
            let end = angle + sweep
            // The reference omits sections below one percent, then renormalizes
            // the remaining angles. Percentage text retains the original total.
            if fraction > 0 {
                let fill = palette.color(tint: 28 + index % 8)
                if fraction >= 1 {
                    commands.append(.ellipse(CGRect(x: 40, y: 40, width: 370, height: 370), fill: fill, stroke: stroke, width: 2))
                } else {
                    commands.append(.path(sector(center: center, radius: radius, start: angle, sweep: sweep), fill: fill, stroke: stroke, width: 2, dash: []))
                }
                let label = "\(index + 1) · \(Int((section.value / total * 100).rounded()))%"
                let measured = measure(label, role: 13)
                let middle = (angle + end) / 2
                percentLabels.append((label, CGRect(
                    x: center.x + radius * 0.75 * cos(middle) - measured.width / 2,
                    y: center.y + radius * 0.75 * sin(middle) - 5.95 - measured.height / 2,
                    width: measured.width, height: measured.height)))
            }
            angle = end
        }
        commands += percentLabels.map { .coloredText($0.0, $0.1, role: 13, color: ink) }
        var bounds = CGRect(x: 0, y: 0, width: 412, height: 450)
        if let title = diagram.title, !title.isEmpty {
            let measured = measure(title, role: 14)
            let rect = CGRect(x: 225 - measured.width / 2, y: 16.25 - measured.height / 2,
                              width: measured.width, height: measured.height)
            commands.append(.text(title, rect, role: 14))
            bounds = bounds.union(rect)
        }
        let firstY = 225 - CGFloat(diagram.sections.count) * 11
        for (index, section) in diagram.sections.enumerated() {
            let y = firstY + CGFloat(index) * 22
            let fill = palette.color(tint: 28 + index % 8)
            let square = CGRect(x: 441, y: y, width: 18, height: 18)
            commands.append(.roundRect(square, radius: 0, fill: fill, stroke: stroke, width: 1))
            let number = String(index + 1), badge = measure(number, role: 3)
            commands.append(.coloredText(number,
                CGRect(x: 450 - badge.width / 2, y: y + 9 - badge.height / 2,
                       width: badge.width, height: badge.height), role: 3, color: ink))
            let label = diagram.showData ? "\(section.label) [\(numberString(section.value))]" : section.label
            let measured = measure(label, role: 13)
            let rect = CGRect(x: 463, y: y + 8.05 - measured.height / 2,
                              width: measured.width, height: measured.height)
            commands.append(.text(label, rect, role: 13))
            bounds = bounds.union(CGRect(x: 0, y: y - 0.5,
                width: 512 + measured.width, height: max(19, measured.height + 1)))
        }
        return MermaidScene(bounds: bounds, commands: commands, textStyle: textStyle, theme: theme)
    }

    private static func sector(center: CGPoint, radius: CGFloat, start: CGFloat, sweep: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func point(_ a: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        }
        path.move(to: point(start))
        let segments = max(1, Int(ceil(sweep / (.pi / 2))))
        let step = sweep / CGFloat(segments)
        for segment in 0..<segments {
            let a = start + CGFloat(segment) * step, b = a + step
            let p = point(a), q = point(b), tangent = 4 / CGFloat(3) * tan(step / 4) * radius
            path.addCurve(to: q,
                control1: CGPoint(x: p.x - tangent * sin(a), y: p.y + tangent * cos(a)),
                control2: CGPoint(x: q.x + tangent * sin(b), y: q.y - tangent * cos(b)))
        }
        path.addLine(to: center); path.closeSubpath()
        return path
    }

    private static func numberString(_ value: Double) -> String {
        String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func parse(_ source: String) throws -> Diagram {
        guard source.utf8.count <= 65_536 else { throw MermaidError.tooLarge }
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let chars = Array(normalized)
        var offset = 0, line = 1
        var result = Diagram(sections: [], title: nil, showData: false)
        func starts(_ text: String) -> Bool { chars[offset...].starts(with: Array(text)) }
        func advance() { if chars[offset] == "\n" { line += 1 }; offset += 1 }
        func lineText() -> String {
            let start = offset
            while offset < chars.count && chars[offset] != "\n" { advance() }
            return String(chars[start..<offset]).trimmingCharacters(in: .whitespaces)
        }
        func skip() throws {
            while offset < chars.count {
                if chars[offset].isWhitespace || chars[offset] == "\u{FEFF}" { advance() }
                else if starts("%%{") { throw MermaidError.unsupported(line: line) }
                else if starts("%%") { _ = lineText() }
                else { break }
            }
        }
        try skip()
        let headerLine = line
        guard starts("pie") else { throw MermaidError.unknownType }
        offset += 3
        let header = lineText().components(separatedBy: "%%")[0].trimmingCharacters(in: .whitespaces)
        var options = header
        if options.hasPrefix("showData") {
            result.showData = true
            options = String(options.dropFirst(8)).trimmingCharacters(in: .whitespaces)
        }
        if options.hasPrefix("title ") { result.title = String(options.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        else if !options.isEmpty { throw MermaidError.syntax(line: headerLine) }
        var labels = Set<String>()
        while true {
            try skip()
            guard offset < chars.count else { break }
            if starts("title ") {
                offset += 6; result.title = lineText(); continue
            }
            if starts("accTitle:") || starts("accDescr:") { _ = lineText(); continue }
            let entryLine = line
            guard chars[offset] == "\"" else { throw MermaidError.syntax(line: line) }
            advance()
            var label = "", closed = false
            while offset < chars.count {
                if chars[offset] == "\"" { advance(); closed = true; break }
                if chars[offset] == "\\", offset + 1 < chars.count, chars[offset + 1] == "\"" {
                    advance(); label.append(chars[offset]); advance()
                } else if chars[offset].isWhitespace {
                    label.append(" "); advance()
                } else { label.append(chars[offset]); advance() }
            }
            guard closed else { throw MermaidError.syntax(line: entryLine) }
            guard label.utf8.count <= 2048 else { throw MermaidError.tooLarge }
            if label.contains("#quot;") || label.contains("#apos;") { throw MermaidError.unsupported(line: entryLine) }
            while offset < chars.count && (chars[offset] == " " || chars[offset] == "\t") { advance() }
            guard offset < chars.count && chars[offset] == ":" else { throw MermaidError.syntax(line: line) }
            advance()
            while offset < chars.count && (chars[offset] == " " || chars[offset] == "\t") { advance() }
            let start = offset
            while offset < chars.count && chars[offset].isASCII && chars[offset].isNumber { advance() }
            guard offset > start else { throw MermaidError.syntax(line: line) }
            if offset < chars.count && chars[offset] == "." {
                advance(); let fractionStart = offset
                while offset < chars.count && chars[offset].isASCII && chars[offset].isNumber { advance() }
                guard offset > fractionStart else { throw MermaidError.syntax(line: line) }
            }
            guard let value = Double(String(chars[start..<offset])), value.isFinite else { throw MermaidError.tooLarge }
            while offset < chars.count && (chars[offset] == " " || chars[offset] == "\t") { advance() }
            guard offset == chars.count || chars[offset] == "\n" || starts("%%") else { throw MermaidError.syntax(line: line) }
            if labels.insert(label).inserted { result.sections.append(Section(label: label, value: value)) }
            guard result.sections.count <= 4096 else { throw MermaidError.tooLarge }
        }
        return result
    }
}
