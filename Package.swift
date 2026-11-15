// swift-tools-version: 6.2
import PackageDescription

// The Rust dependencies are prebuilt by scripts/build-native into
// .build/native/*.xcframework (macOS, iOS device and iOS simulator slices).
let native = ".build/native"

let package = Package(
    name: "KasumiMarkdown",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "KasumiMarkdown", targets: ["KasumiMarkdown"]),
        .executable(name: "KasumiRender", targets: ["KasumiRender"])
    ],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")],
    targets: [
        .binaryTarget(name: "KasumiDagreNative", path: "\(native)/kasumi_dagre.xcframework"),
        .binaryTarget(name: "KasumiLineBreakNative", path: "\(native)/kasumi_linebreak.xcframework"),
        .binaryTarget(name: "KasumiHyphenationNative", path: "\(native)/kasumi_hyphenation.xcframework"),
        .target(
            name: "CDagre", dependencies: ["KasumiDagreNative"], path: "packages/NativeDagre/Bridge",
            publicHeadersPath: "include"),
        .target(
            name: "CLineBreak", dependencies: ["KasumiLineBreakNative"], path: "packages/NativeLineBreak/Bridge",
            publicHeadersPath: "include"),
        .target(
            name: "CHyphenation", dependencies: ["KasumiHyphenationNative"], path: "packages/NativeHyphenation/Bridge",
            publicHeadersPath: "include"),
        .target(
            name: "KasumiMarkdown",
            dependencies: [
                "CDagre", "CLineBreak", "CHyphenation", .product(name: "Markdown", package: "swift-markdown")
            ],
            resources: [.copy("Bundled")]
        ),
        .executableTarget(name: "KasumiRender", dependencies: ["KasumiMarkdown"]),
        .testTarget(name: "KasumiMarkdownTests", dependencies: ["KasumiMarkdown"], resources: [.copy("fixtures")])
    ]
)
