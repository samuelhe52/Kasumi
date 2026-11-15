import Foundation

/// The reference substitutes emphasis faces for its two Simplified Chinese
/// families. Other families, including Traditional Chinese, remain generic.
struct CJKFontFace {
    let name: String
    let baselineDelta: Double
    static func resolve(family: String, strong: Bool, emphasis: Bool, heading: Bool, italic: String, heavy: String)
        -> CJKFontFace?
    {
        let song = family == "Songti SC"
        let ping = family == "PingFang SC"
        guard song || ping else { return nil }
        if heading { return .init(name: song ? "STSongti-SC-Bold" : "PingFangSC-Semibold", baselineDelta: 0) }
        if emphasis {
            switch italic {
            case "kai":
                return .init(
                    name: strong ? "STKaitiSC-Bold" : "STKaitiSC-Regular",
                    baselineDelta: song ? (strong ? 0 : 0.006) : (strong ? 0.06 : 0.067))
            case "fangsong": return .init(name: "STFangsong", baselineDelta: song ? -0.065 : 0)
            case "xihei": return .init(name: strong ? "STHeiti" : "STXihei", baselineDelta: song ? -0.065 : 0)
            default: break
            }
        }
        if strong {
            if ping {
                return .init(name: heavy == "bold" ? "PingFangSC-Medium" : "PingFangSC-Semibold", baselineDelta: 0)
            }
            switch heavy {
            case "bold": return .init(name: "STSongti-SC-Bold", baselineDelta: 0)
            case "hei": return .init(name: "STHeiti", baselineDelta: -0.065)
            default: return .init(name: "STSongti-SC-Black", baselineDelta: -0.055)
            }
        }
        return .init(name: song ? "STSongti-SC-Regular" : "PingFangSC-Regular", baselineDelta: 0)
    }
}
