import Foundation

/// Author CSS colors select semantic theme accents rather than literal paint.
/// The OKLab bucket/shade rules match the recorded reference classifier.
enum MermaidStyleColor {
    enum Channel: String, CaseIterable, Sendable { case fill, stroke, text }
    enum Selection: Equatable, Sendable { case themeDefault, transparent, tint(Int) }

    static func recognizes(_ source: String) -> Bool {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "none" || value == "transparent" || rgb(value) != nil
    }

    static func parse(_ source: String, channel: Channel) -> Selection {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source == "none" || source == "transparent" {
            return channel == .text ? .themeDefault : .transparent
        }
        guard let rgb = rgb(source) else { return .themeDefault }
        let lab = oklab(rgb.0, rgb.1, rgb.2)
        let chroma = hypot(lab.a, lab.b)
        let neutral = chroma < 0.015
        switch channel {
        case .fill:
            let shade: Int
            if lab.l >= 0.85 && (lab.l >= 0.9 || chroma < 0.1) { shade = 0 } else { shade = lab.l < 0.6 ? 2 : 1 }
            if neutral { return shade == 0 ? .themeDefault : .tint(shade == 1 ? 25 : 26) }
            return .tint(hue(lab.a, lab.b) * 3 + shade + 1)
        case .stroke:
            if neutral { return lab.l < 0.6 ? .tint(26) : .themeDefault }
            return .tint(hue(lab.a, lab.b) * 3 + 3)
        case .text:
            return neutral ? .themeDefault : .tint(hue(lab.a, lab.b) * 3 + 3)
        }
    }

    private static func hue(_ a: Double, _ b: Double) -> Int {
        var degrees = atan2(b, a) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        switch degrees {
        case 5..<42.5: return 0
        case 42.5..<80: return 1
        case 80..<122.5: return 2
        case 122.5..<170: return 3
        case 170..<225: return 4
        case 225..<277.5: return 5
        case 277.5..<322.5: return 6
        default: return 7
        }
    }

    private static func oklab(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> (l: Double, a: Double, b: Double) {
        func linear(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r = linear(red)
        let g = linear(green)
        let b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (
            0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        )
    }

    private static func rgb(_ source: String) -> (UInt8, UInt8, UInt8)? {
        let hex: String
        if let named = keywords[source] {
            hex = named
        } else {
            guard source.hasPrefix("#") else { return nil }
            hex = String(source.dropFirst())
        }
        guard [3, 4, 6, 8].contains(hex.utf8.count),
            hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { return nil }
        let expanded = hex.count <= 4 ? hex.map { "\($0)\($0)" }.joined() : hex
        guard let value = UInt32(expanded, radix: 16) else { return nil }
        let alpha = expanded.count == 8 ? Double(value & 255) / 255 : 1
        let rgb = expanded.count == 8 ? value >> 8 : value
        // Native author alpha is composited over white in encoded sRGB and
        // rounded to bytes before the OKLab conversion. It is not paint alpha.
        func composite(_ shift: UInt32) -> UInt8 {
            let channel = Double((rgb >> shift) & 255)
            return UInt8((channel * alpha + 255 * (1 - alpha)).rounded())
        }
        return (composite(16), composite(8), composite(0))
    }

    // Standard CSS/SVG keyword RGB values. Every keyword is corroborated
    // against the recorded reference fixture.
    private static let keywords: [String: String] = [
        "aliceblue": "f0f8ff",
        "antiquewhite": "faebd7",
        "aqua": "00ffff",
        "aquamarine": "7fffd4",
        "azure": "f0ffff",
        "beige": "f5f5dc",
        "bisque": "ffe4c4",
        "black": "000000",
        "blanchedalmond": "ffebcd",
        "blue": "0000ff",
        "blueviolet": "8a2be2",
        "brown": "a52a2a",
        "burlywood": "deb887",
        "cadetblue": "5f9ea0",
        "chartreuse": "7fff00",
        "chocolate": "d2691e",
        "coral": "ff7f50",
        "cornflowerblue": "6495ed",
        "cornsilk": "fff8dc",
        "crimson": "dc143c",
        "cyan": "00ffff",
        "darkblue": "00008b",
        "darkcyan": "008b8b",
        "darkgoldenrod": "b8860b",
        "darkgray": "a9a9a9",
        "darkgreen": "006400",
        "darkgrey": "a9a9a9",
        "darkkhaki": "bdb76b",
        "darkmagenta": "8b008b",
        "darkolivegreen": "556b2f",
        "darkorange": "ff8c00",
        "darkorchid": "9932cc",
        "darkred": "8b0000",
        "darksalmon": "e9967a",
        "darkseagreen": "8fbc8f",
        "darkslateblue": "483d8b",
        "darkslategray": "2f4f4f",
        "darkslategrey": "2f4f4f",
        "darkturquoise": "00ced1",
        "darkviolet": "9400d3",
        "deeppink": "ff1493",
        "deepskyblue": "00bfff",
        "dimgray": "696969",
        "dimgrey": "696969",
        "dodgerblue": "1e90ff",
        "firebrick": "b22222",
        "floralwhite": "fffaf0",
        "forestgreen": "228b22",
        "fuchsia": "ff00ff",
        "gainsboro": "dcdcdc",
        "ghostwhite": "f8f8ff",
        "gold": "ffd700",
        "goldenrod": "daa520",
        "gray": "808080",
        "green": "008000",
        "greenyellow": "adff2f",
        "grey": "808080",
        "honeydew": "f0fff0",
        "hotpink": "ff69b4",
        "indianred": "cd5c5c",
        "indigo": "4b0082",
        "ivory": "fffff0",
        "khaki": "f0e68c",
        "lavender": "e6e6fa",
        "lavenderblush": "fff0f5",
        "lawngreen": "7cfc00",
        "lemonchiffon": "fffacd",
        "lightblue": "add8e6",
        "lightcoral": "f08080",
        "lightcyan": "e0ffff",
        "lightgoldenrodyellow": "fafad2",
        "lightgray": "d3d3d3",
        "lightgreen": "90ee90",
        "lightgrey": "d3d3d3",
        "lightpink": "ffb6c1",
        "lightsalmon": "ffa07a",
        "lightseagreen": "20b2aa",
        "lightskyblue": "87cefa",
        "lightslategray": "778899",
        "lightslategrey": "778899",
        "lightsteelblue": "b0c4de",
        "lightyellow": "ffffe0",
        "lime": "00ff00",
        "limegreen": "32cd32",
        "linen": "faf0e6",
        "magenta": "ff00ff",
        "maroon": "800000",
        "mediumaquamarine": "66cdaa",
        "mediumblue": "0000cd",
        "mediumorchid": "ba55d3",
        "mediumpurple": "9370db",
        "mediumseagreen": "3cb371",
        "mediumslateblue": "7b68ee",
        "mediumspringgreen": "00fa9a",
        "mediumturquoise": "48d1cc",
        "mediumvioletred": "c71585",
        "midnightblue": "191970",
        "mintcream": "f5fffa",
        "mistyrose": "ffe4e1",
        "moccasin": "ffe4b5",
        "navajowhite": "ffdead",
        "navy": "000080",
        "oldlace": "fdf5e6",
        "olive": "808000",
        "olivedrab": "6b8e23",
        "orange": "ffa500",
        "orangered": "ff4500",
        "orchid": "da70d6",
        "palegoldenrod": "eee8aa",
        "palegreen": "98fb98",
        "paleturquoise": "afeeee",
        "palevioletred": "db7093",
        "papayawhip": "ffefd5",
        "peachpuff": "ffdab9",
        "peru": "cd853f",
        "pink": "ffc0cb",
        "plum": "dda0dd",
        "powderblue": "b0e0e6",
        "purple": "800080",
        "rebeccapurple": "663399",
        "red": "ff0000",
        "rosybrown": "bc8f8f",
        "royalblue": "4169e1",
        "saddlebrown": "8b4513",
        "salmon": "fa8072",
        "sandybrown": "f4a460",
        "seagreen": "2e8b57",
        "seashell": "fff5ee",
        "sienna": "a0522d",
        "silver": "c0c0c0",
        "skyblue": "87ceeb",
        "slateblue": "6a5acd",
        "slategray": "708090",
        "slategrey": "708090",
        "snow": "fffafa",
        "springgreen": "00ff7f",
        "steelblue": "4682b4",
        "tan": "d2b48c",
        "teal": "008080",
        "thistle": "d8bfd8",
        "tomato": "ff6347",
        "turquoise": "40e0d0",
        "violet": "ee82ee",
        "wheat": "f5deb3",
        "white": "ffffff",
        "whitesmoke": "f5f5f5",
        "yellow": "ffff00",
        "yellowgreen": "9acd32"
    ]
}
