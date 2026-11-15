import Foundation

enum MathAtomClass { case ordinary, binary, relation, opening, closing, punctuation, largeOperator, function }
enum MathAlphabet { case italic, upright, bold, doubleStruck, script, fraktur, sans, monospace }
enum MathAccent {
    case hat, wideHat, tilde, wideTilde, bar, vector, dot, doubleDot, overline, underline, overbrace, underbrace
}
enum MathStyle { case display, text, script, scriptScript }

indirect enum MathNode {
    case row([MathNode])
    case symbol(String, MathAtomClass)
    case text(String)
    case space(Double)
    case fraction(MathNode, MathNode, rule: Bool, display: Bool?)
    case scripts(MathNode, lower: MathNode?, upper: MathNode?, limits: Bool?)
    case radical(MathNode, degree: MathNode?)
    case delimited(String, MathNode, String)
    case accent(MathAccent, MathNode)
    case alphabet(MathAlphabet, MathNode)
    case matrix([[MathNode]], left: String, right: String, aligned: Bool)
    case overUnder(MathNode, above: MathNode?, below: MathNode?)
    case color(UInt32, MathNode)
    case style(MathStyle, MathNode)
}

struct ParsedMath {
    let root: MathNode
    let diagnostics: [String]
}

/// A bounded TeX math parser. Unknown commands remain visible and are reported;
/// they are never silently removed from the document's semantic source.
struct MathParser {
    private enum Token: Equatable {
        case character(Character)
        case command(String)
        case whitespace
    }
    private var tokens: [Token]
    private var cursor = 0
    private var diagnostics: [String] = []
    private var depth = 0

    init(_ source: String) {
        let chars = Array(source)
        var result: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            i += 1
            if c == "\\", i < chars.count {
                var name = String(chars[i])
                i += 1
                if name.first?.isASCII == true, name.first?.isLetter == true {
                    while i < chars.count, chars[i].isASCII, chars[i].isLetter {
                        name.append(chars[i])
                        i += 1
                    }
                    while i < chars.count, chars[i].isWhitespace { i += 1 }
                }
                result.append(.command(name))
            } else if c.isWhitespace {
                result.append(.whitespace)
            } else {
                result.append(.character(c))
            }
        }
        tokens = result
    }

    mutating func parse() -> ParsedMath {
        let root = sequence(stoppingAt: [])
        return ParsedMath(root: root, diagnostics: diagnostics)
    }

    private mutating func skipSpaces() { while cursor < tokens.count, tokens[cursor] == .whitespace { cursor += 1 } }
    private mutating func sequence(stoppingAt stops: [Token]) -> MathNode {
        depth += 1
        defer { depth -= 1 }
        guard depth <= 24 else {
            diagnostics.append("Math nesting exceeds 24 levels")
            // Consume the rest rather than recurse or loop indefinitely on malformed input.
            cursor = tokens.count
            return .text("…")
        }
        var nodes: [MathNode] = []
        while cursor < tokens.count {
            skipSpaces()
            guard cursor < tokens.count, !stops.contains(tokens[cursor]) else { break }
            if case .command(let command) = tokens[cursor], let style = Self.styles[command] {
                cursor += 1
                nodes.append(.style(style, sequence(stoppingAt: stops)))
                break
            } else if tokens[cursor] == .character("^") || tokens[cursor] == .character("_") {
                let upper = tokens[cursor] == .character("^")
                cursor += 1
                let argument = argument()
                let prior = nodes.popLast() ?? .row([])
                if case .scripts(let base, let lower, let superscript, let limits) = prior {
                    if (upper && superscript != nil) || (!upper && lower != nil) {
                        diagnostics.append("Repeated math script")
                    }
                    nodes.append(
                        .scripts(
                            base, lower: upper ? lower : argument, upper: upper ? argument : superscript, limits: limits
                        ))
                } else {
                    nodes.append(
                        .scripts(prior, lower: upper ? nil : argument, upper: upper ? argument : nil, limits: nil))
                }
            } else if tokens[cursor] == .command("limits") || tokens[cursor] == .command("nolimits") {
                let limits = tokens[cursor] == .command("limits")
                cursor += 1
                if let prior = nodes.popLast() {
                    if case .scripts(let base, let lower, let upper, _) = prior {
                        nodes.append(.scripts(base, lower: lower, upper: upper, limits: limits))
                    } else {
                        nodes.append(.scripts(prior, lower: nil, upper: nil, limits: limits))
                    }
                }
            } else if tokens[cursor] == .character("'") {
                cursor += 1
                var primes = "′"
                while cursor < tokens.count, tokens[cursor] == .character("'") {
                    primes += "′"
                    cursor += 1
                }
                let prior = nodes.popLast() ?? .row([])
                nodes.append(.scripts(prior, lower: nil, upper: .symbol(primes, .ordinary), limits: false))
            } else {
                nodes.append(atom())
            }
        }
        return .row(nodes)
    }

    private mutating func argument() -> MathNode {
        depth += 1
        defer { depth -= 1 }
        guard depth <= 24 else {
            diagnostics.append("Math nesting exceeds 24 levels")
            cursor = tokens.count
            return .row([])
        }
        skipSpaces()
        guard cursor < tokens.count else {
            diagnostics.append("Missing math argument")
            return .row([])
        }
        return atom()
    }

    private mutating func rawGroup() -> String {
        skipSpaces()
        guard cursor < tokens.count, tokens[cursor] == .character("{") else {
            diagnostics.append("Expected math group")
            return ""
        }
        cursor += 1
        var nesting = 1
        var result = ""
        while cursor < tokens.count {
            let token = tokens[cursor]
            cursor += 1
            switch token {
            case .character("{"):
                nesting += 1
                result += "{"
            case .character("}"):
                nesting -= 1
                if nesting == 0 { return result }
                result += "}"
            case .character(let c): result.append(c)
            case .whitespace: result += " "
            case .command(let c): result += c.count == 1 ? c : "\\" + c
            }
        }
        diagnostics.append("Unclosed math group")
        return result
    }

    private mutating func delimiter() -> String {
        skipSpaces()
        guard cursor < tokens.count else { return "" }
        let token = tokens[cursor]
        cursor += 1
        switch token {
        case .character(let c): return c == "." ? "" : String(c)
        case .command(let c): return Self.delimiters[c] ?? Self.symbols[c]?.0 ?? c
        case .whitespace: return ""
        }
    }

    private mutating func atom() -> MathNode {
        guard cursor < tokens.count else { return .row([]) }
        let token = tokens[cursor]
        cursor += 1
        switch token {
        case .whitespace: return .row([])
        case .character("{"):
            let node = sequence(stoppingAt: [.character("}")])
            if cursor < tokens.count { cursor += 1 } else { diagnostics.append("Unclosed math group") }
            return node
        case .character("}"):
            diagnostics.append("Unexpected closing math brace")
            return .symbol("}", .closing)
        case .character(let c): return .symbol(String(c), Self.atomClass(c))
        case .command(let command):
            if let symbol = Self.symbols[command] { return .symbol(symbol.0, symbol.1) }
            if let value = Self.functions[command] { return .symbol(value, .function) }
            if let spacing = Self.spaces[command] { return .space(spacing) }
            if let alphabet = Self.alphabets[command] { return .alphabet(alphabet, argument()) }
            if let accent = Self.accents[command] { return .accent(accent, argument()) }
            switch command {
            case "frac", "dfrac", "tfrac", "binom", "dbinom", "tbinom":
                let numerator = argument()
                let denominator = argument()
                let display: Bool? = command.first == "d" ? true : command.first == "t" ? false : nil
                let fraction = MathNode.fraction(
                    numerator, denominator, rule: !command.contains("binom"), display: display)
                return command.contains("binom") ? .delimited("(", fraction, ")") : fraction
            case "sqrt":
                skipSpaces()
                var degree: MathNode?
                if cursor < tokens.count, tokens[cursor] == .character("[") {
                    cursor += 1
                    degree = sequence(stoppingAt: [.character("]")])
                    if cursor < tokens.count { cursor += 1 } else { diagnostics.append("Unclosed root degree") }
                }
                return .radical(argument(), degree: degree)
            case "left":
                let left = delimiter()
                let body = sequence(stoppingAt: [.command("right")])
                if cursor < tokens.count {
                    cursor += 1
                    return .delimited(left, body, delimiter())
                }
                diagnostics.append("Missing \\right delimiter")
                return .delimited(left, body, "")
            case "right":
                diagnostics.append("Unexpected \\right")
                return .symbol(delimiter(), .closing)
            case "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr", "Biggl", "Biggr":
                // Explicit sizing commands are preserved as delimiters; automatic
                // enclosure sizing is provided by \left...\right.
                return .symbol(delimiter(), .ordinary)
            case "text", "textrm", "textnormal", "mbox": return .text(rawGroup())
            case "operatorname": return .symbol(rawGroup(), .function)
            case "color", "textcolor":
                let name = rawGroup()
                let color = Self.color(name)
                if color == nil { diagnostics.append("Unsupported math color \(name)") }
                return .color(color ?? 0x0000_00FF, argument())
            case "overset", "stackrel":
                let above = argument()
                return .overUnder(argument(), above: above, below: nil)
            case "underset":
                let below = argument()
                return .overUnder(argument(), above: nil, below: below)
            case "begin": return environment(rawGroup())
            case "{", "}", "_", "%", "#", "$", "&": return .symbol(command, .ordinary)
            case "|": return .symbol("‖", .ordinary)
            case "\\": return .space(0)
            default:
                diagnostics.append("Unsupported math command \\\(command)")
                return .text("\\" + command)
            }
        }
    }

    private mutating func environment(_ name: String) -> MathNode {
        let delimiters: (String, String)
        switch name {
        case "matrix", "smallmatrix", "aligned", "align", "align*", "gathered", "gather", "gather*", "array":
            delimiters = ("", "")
        case "pmatrix": delimiters = ("(", ")")
        case "bmatrix": delimiters = ("[", "]")
        case "Bmatrix": delimiters = ("{", "}")
        case "vmatrix": delimiters = ("|", "|")
        case "Vmatrix": delimiters = ("‖", "‖")
        case "cases": delimiters = ("{", "")
        default:
            diagnostics.append("Unsupported math environment \(name)")
            delimiters = ("", "")
        }
        if name == "array" {
            _ = rawGroup()
            diagnostics.append("Array column specification is not yet applied")
        }
        var rows: [[MathNode]] = []
        var row: [MathNode] = []
        while cursor < tokens.count {
            row.append(sequence(stoppingAt: [.character("&"), .command("\\"), .command("end")]))
            guard cursor < tokens.count else { break }
            let stop = tokens[cursor]
            cursor += 1
            if stop == .character("&") { continue }
            rows.append(row)
            row = []
            if stop == .command("end") {
                let end = rawGroup()
                if end != name { diagnostics.append("Mismatched math environment \(name)/\(end)") }
                return .matrix(
                    rows, left: delimiters.0, right: delimiters.1, aligned: name.hasPrefix("align") || name == "cases")
            }
        }
        if !row.isEmpty { rows.append(row) }
        diagnostics.append("Unclosed math environment \(name)")
        return .matrix(
            rows, left: delimiters.0, right: delimiters.1, aligned: name.hasPrefix("align") || name == "cases")
    }

    private static func atomClass(_ c: Character) -> MathAtomClass {
        if "+−-*/×÷±∓⋅∪∩".contains(c) { return .binary }
        if "=<>≤≥≠≈≡∈∉⊂⊃⊆⊇→←↔".contains(c) { return .relation }
        if "([{⌈⌊".contains(c) { return .opening }
        if ")] }⌉⌋".filter({ !$0.isWhitespace }).contains(c) { return .closing }
        if ",;:".contains(c) { return .punctuation }
        return .ordinary
    }
    private static let spaces: [String: Double] = [
        ",": 3.0 / 18, ":": 4.0 / 18, ";": 5.0 / 18, "!": -3.0 / 18, " ": 1.0 / 3, "quad": 1, "qquad": 2,
        "enspace": 0.5, "thinspace": 3.0 / 18
    ]
    private static let styles: [String: MathStyle] = [
        "displaystyle": .display, "textstyle": .text, "scriptstyle": .script, "scriptscriptstyle": .scriptScript
    ]
    private static func color(_ name: String) -> UInt32? {
        if name.hasPrefix("#"), name.count == 7, let value = UInt32(name.dropFirst(), radix: 16) {
            return value << 8 | 0xFF
        }
        return [
            "black": 0x0000_00FF, "white": 0xFFFF_FFFF, "red": 0xFF00_00FF, "green": 0x0080_00FF, "blue": 0x0000_FFFF,
            "yellow": 0xFFFF_00FF, "cyan": 0x00FF_FFFF, "magenta": 0xFF00_FFFF, "gray": 0x8080_80FF,
            "orange": 0xFFA5_00FF, "purple": 0x8000_80FF
        ][name.lowercased()]
    }
    private static let functions = Dictionary(
        uniqueKeysWithValues: [
            "sin", "cos", "tan", "cot", "sec", "csc", "sinh", "cosh", "tanh", "arcsin", "arccos", "arctan", "log", "ln",
            "exp", "lim", "limsup", "liminf", "max", "min", "sup", "inf", "det", "dim", "gcd", "Pr", "ker", "arg",
            "deg", "hom"
        ].map { ($0, $0) })
    private static let alphabets: [String: MathAlphabet] = [
        "mathrm": .upright, "mathnormal": .italic, "mathit": .italic, "mathbf": .bold, "boldsymbol": .bold,
        "mathbb": .doubleStruck, "mathcal": .script, "mathscr": .script, "mathfrak": .fraktur, "mathsf": .sans,
        "mathtt": .monospace
    ]
    private static let accents: [String: MathAccent] = [
        "hat": .hat, "widehat": .wideHat, "tilde": .tilde, "widetilde": .wideTilde, "bar": .bar, "vec": .vector,
        "dot": .dot, "ddot": .doubleDot, "overline": .overline, "underline": .underline, "overbrace": .overbrace,
        "underbrace": .underbrace
    ]
    private static let delimiters = [
        "langle": "⟨", "rangle": "⟩", "lbrace": "{", "rbrace": "}", "lvert": "|", "rvert": "|", "lVert": "‖",
        "rVert": "‖", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "backslash": "\\"
    ]
    private static let symbols: [String: (String, MathAtomClass)] = {
        var values: [String: (String, MathAtomClass)] = [:]
        let names = [
            "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu",
            "xi", "omicron", "pi", "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega"
        ]
        let greek = Array("αβγδεζηθικλμνξοπρστυφχψω")
        for (name, symbol) in zip(names, greek) { values[name] = (String(symbol), .ordinary) }
        for (name, symbol) in [
            "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ",
            "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω", "varepsilon": "ϵ", "vartheta": "ϑ", "varpi": "ϖ", "varrho": "ϱ",
            "varsigma": "ς", "varphi": "ϕ", "infty": "∞", "partial": "∂", "nabla": "∇", "ell": "ℓ", "hbar": "ℏ",
            "imath": "ı", "jmath": "ȷ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ", "emptyset": "∅", "varnothing": "∅",
            "forall": "∀", "exists": "∃", "neg": "¬", "ldots": "…", "dots": "…", "cdots": "⋯", "vdots": "⋮",
            "ddots": "⋱", "angle": "∠", "prime": "′"
        ] { values[name] = (symbol, .ordinary) }
        for (name, symbol) in [
            "times": "×", "div": "÷", "cdot": "⋅", "pm": "±", "mp": "∓", "ast": "∗", "star": "⋆", "circ": "∘",
            "bullet": "∙", "cup": "∪", "cap": "∩", "setminus": "∖", "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨",
            "oplus": "⊕", "otimes": "⊗", "odot": "⊙"
        ] { values[name] = (symbol, .binary) }
        for (name, symbol) in [
            "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠", "equiv": "≡", "approx": "≈",
            "sim": "∼", "simeq": "≃", "cong": "≅", "propto": "∝", "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂",
            "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "to": "→", "rightarrow": "→", "leftarrow": "←",
            "leftrightarrow": "↔", "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔", "implies": "⇒",
            "iff": "⟺", "mapsto": "↦", "perp": "⊥", "parallel": "∥", "mid": "∣", "ll": "≪", "gg": "≫", "prec": "≺",
            "succ": "≻"
        ] { values[name] = (symbol, .relation) }
        for (name, symbol) in [
            "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮", "bigcup": "⋃",
            "bigcap": "⋂", "bigvee": "⋁", "bigwedge": "⋀", "bigoplus": "⨁", "bigotimes": "⨂"
        ] { values[name] = (symbol, .largeOperator) }
        for (name, symbol) in ["subsetneqq": "⫋", "supsetneqq": "⫌", "subsetneq": "⊊", "supsetneq": "⊋"] {
            values[name] = (symbol, .relation)
        }
        for (name, symbol) in delimiters { values[name] = (symbol, .ordinary) }
        return values
    }()
}
