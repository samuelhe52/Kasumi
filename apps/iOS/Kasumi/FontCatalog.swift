import Foundation

/// The CJK faces Kasumi's presets use and the open faces that replace them.
/// Apple's faces come from iOS's on-demand system download and can't be
/// redistributed. Open faces are fetched from pinned upstream files and
/// checked byte for byte before they're registered.
struct FontPackage: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// PostScript names requested through Core Text's system download.
        case apple(postScriptNames: [String])
        case open([OpenFile], license: String, licenseURL: URL)
    }

    struct OpenFile: Hashable, Sendable {
        let url: URL
        let fileName: String
        let postScriptName: String
        let byteCount: Int64
        let sha256: String
    }

    let id: String
    let name: String
    /// A short phrase in the face, shown once it's available.
    let sample: String
    /// What the reader uses the face for.
    let role: String
    let source: Source
    /// The open package downloaded when this Apple package can't be.
    let fallbackID: String?
    /// Offered by onboarding.
    let recommended: Bool

    var postScriptNames: [String] {
        switch source {
        case .apple(let names): names
        case .open(let files, _, _): files.map(\.postScriptName)
        }
    }

    var isApple: Bool { if case .apple = source { true } else { false } }

    var byteCount: Int64? {
        if case .open(let files, _, _) = source { files.reduce(0) { $0 + $1.byteCount } } else { nil }
    }
}

/// A role an Apple face and its open replacement compete for. The renderer uses
/// the Apple face when it's available, unless the user chose the open one.
struct FontChoice: Identifiable, Sendable {
    let id: String
    let title: String
    let apple: FontPackage
    let open: FontPackage
    /// The family name `RenderStyle.preferredOpenFamilies` expects.
    let openFamily: String

    static let all: [FontChoice] = [
        .init(
            id: "simplified", title: "Simplified Chinese", apple: FontPackage.named("songti-sc")!,
            open: FontPackage.named("noto-serif-sc")!, openFamily: "Noto Serif SC"),
        .init(
            id: "emphasis", title: "Emphasis", apple: FontPackage.named("kaiti-sc")!,
            open: FontPackage.named("lxgw-wenkai-lite")!, openFamily: "LXGW WenKai Lite"),
        .init(
            id: "traditional", title: "Traditional Chinese", apple: FontPackage.named("songti-tc")!,
            open: FontPackage.named("noto-serif-tc")!, openFamily: "Noto Serif TC")
    ]

    static func containing(_ package: FontPackage) -> FontChoice? {
        all.first { $0.apple.id == package.id || $0.open.id == package.id }
    }

    /// Apple faces that only work together with Songti SC or PingFang SC.
    static let supporting: [FontPackage] = ["simsong", "fangsong", "heiti"].compactMap(FontPackage.named)
}

extension FontPackage {
    static let catalog: [FontPackage] = apple + open

    static func named(_ id: String) -> FontPackage? { catalog.first { $0.id == id } }

    static let apple: [FontPackage] = [
        .init(
            id: "songti-sc", name: "Songti SC", sample: "宋体 霞光与晨雾", role: "Simplified Chinese body text",
            source: .apple(postScriptNames: ["STSongti-SC-Regular", "STSongti-SC-Bold", "STSongti-SC-Black"]),
            fallbackID: "noto-serif-sc", recommended: true),
        .init(
            id: "simsong", name: "SimSong", sample: "，。、「」《》", role: "Punctuation in Songti SC text",
            source: .apple(postScriptNames: ["SimSong-Regular", "SimSong-Bold"]),
            fallbackID: nil, recommended: true),
        .init(
            id: "kaiti-sc", name: "Kaiti SC", sample: "楷体 霞光与晨雾", role: "Emphasis in Chinese text",
            source: .apple(postScriptNames: ["STKaitiSC-Regular", "STKaitiSC-Bold"]),
            fallbackID: "lxgw-wenkai-lite", recommended: true),
        .init(
            id: "fangsong", name: "STFangsong", sample: "仿宋 霞光与晨雾", role: "Fangsong emphasis with Songti SC",
            source: .apple(postScriptNames: ["STFangsong"]), fallbackID: nil, recommended: true),
        .init(
            id: "heiti", name: "STHeiti", sample: "黑体 霞光与晨雾", role: "Xihei emphasis and Hei bold with Songti SC",
            source: .apple(postScriptNames: ["STXihei", "STHeiti"]), fallbackID: nil, recommended: true),
        .init(
            id: "songti-tc", name: "Songti TC", sample: "宋體 霞光與晨霧", role: "Traditional Chinese body text",
            source: .apple(postScriptNames: ["STSongti-TC-Regular", "STSongti-TC-Bold"]),
            fallbackID: "noto-serif-tc", recommended: true)
    ]

    private static let ofl = URL(string: "https://openfontlicense.org")!

    // Noto CJK tag Serif2.003 (SubsetOTF) and LXGW WenKai Lite v1.530, fetched
    // and checksummed on 2026-11-16.
    private static func noto(_ region: String, _ style: String, bytes: Int64, sha256: String) -> OpenFile {
        let name = "NotoSerif\(region)-\(style)"
        return OpenFile(
            url: URL(
                string:
                    "https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003/Serif/SubsetOTF/\(region)/\(name).otf"
            )!,
            fileName: name + ".otf", postScriptName: name, byteCount: bytes, sha256: sha256)
    }

    private static func wenKai(_ style: String, bytes: Int64, sha256: String) -> OpenFile {
        let name = "LXGWWenKaiLite-\(style)"
        return OpenFile(
            url: URL(string: "https://github.com/lxgw/LxgwWenKai-Lite/releases/download/v1.530/\(name).ttf")!,
            fileName: name + ".ttf", postScriptName: name, byteCount: bytes, sha256: sha256)
    }

    static let open: [FontPackage] = [
        .init(
            id: "noto-serif-sc", name: "Noto Serif SC", sample: "思源宋体 霞光与晨雾",
            role: "Open alternative to Songti SC",
            source: .open(
                [
                    noto(
                        "SC", "Regular", bytes: 11_625_800,
                        sha256: "e8f396decc1f0963a016a989c3d8852e863d1350996f573860a80767c83a1cd3"),
                    noto(
                        "SC", "Bold", bytes: 12_094_336,
                        sha256: "24693d48bdb9152f0a06b02af625638a1097abd6de4010ebba027f6e82710527")
                ], license: "SIL Open Font License 1.1", licenseURL: ofl),
            fallbackID: nil, recommended: false),
        .init(
            id: "noto-serif-tc", name: "Noto Serif TC", sample: "思源宋體 霞光與晨霧",
            role: "Open alternative to Songti TC",
            source: .open(
                [
                    noto(
                        "TC", "Regular", bytes: 7_936_104,
                        sha256: "63515eb0622d589a2f4062e8757c598b3da3bffd053f69abd181c210158ef10c"),
                    noto(
                        "TC", "Bold", bytes: 8_253_304,
                        sha256: "3ca2b3294ec84b795d0a45695e78e3612a44dce50f9fc776cd40206340a5768d")
                ], license: "SIL Open Font License 1.1", licenseURL: ofl),
            fallbackID: nil, recommended: false),
        .init(
            id: "lxgw-wenkai-lite", name: "LXGW WenKai Lite", sample: "霞鹜文楷 霞光与晨雾",
            role: "Open alternative to Kaiti SC",
            source: .open(
                [
                    wenKai(
                        "Regular", bytes: 13_949_472,
                        sha256: "f799a538a3355877e597a0ae04050e897932c9ae7689eb9227c2953c5dd549ea"),
                    wenKai(
                        "Medium", bytes: 13_801_408,
                        sha256: "9282063131640c9558a102560cf6d6f8ecc4bb441e74f2bcff032ce4786238d0")
                ], license: "SIL Open Font License 1.1", licenseURL: ofl),
            fallbackID: nil, recommended: false)
    ]
}
