// swift-tools-version: 6.2
import PackageDescription

// A checkout opts into its own Rust builds with `make native-local`.
// Release automation replaces this block with immutable URLs and checksums.
// BEGIN RELEASE NATIVE BINARIES
let releasedNative: [String: (url: String, checksum: String)] = [
    "KasumiDagreNative": (url: "https://github.com/samuelhe52/Kasumi/releases/download/0.1.1/kasumi_dagre.xcframework.zip", checksum: "596a32ba450acfc2bb4a9d0aaf53b02f606a25015f34f629b3d75cbeffda57d2"),
    "KasumiLineBreakNative": (url: "https://github.com/samuelhe52/Kasumi/releases/download/0.1.1/kasumi_linebreak.xcframework.zip", checksum: "85bd907d36d914287136517687d777dbbef29b3f350632d7b8c2caeb8be21c0a"),
    "KasumiHyphenationNative": (url: "https://github.com/samuelhe52/Kasumi/releases/download/0.1.1/kasumi_hyphenation.xcframework.zip", checksum: "bb9f254b0f319df29b2363466d6b682324f991be0b3f5c406eeff5707f80586b"),
    "KasumiSyntaxNative": (url: "https://github.com/samuelhe52/Kasumi/releases/download/0.1.1/kasumi_syntax.xcframework.zip", checksum: "d434aeb2b834edeeafe5f9a304e3ebe8666c4cb192cb845cb479d02302dc9182"),
]
// END RELEASE NATIVE BINARIES
let native = ".build/native"
// Local mode changes this checkout-only switch for a tagged release.
let forceLocalNative = false  // KASUMI_LOCAL_NATIVE_MODE
let useLocalNative = releasedNative.isEmpty || forceLocalNative
func nativeTarget(_ name: String, _ library: String) -> Target {
    if useLocalNative { return .binaryTarget(name: name, path: "\(native)/\(library).xcframework") }
    guard let artifact = releasedNative[name] else { fatalError("Missing release binary: \(name)") }
    return .binaryTarget(name: name, url: artifact.url, checksum: artifact.checksum)
}

let package = Package(
    name: "KasumiMarkdown",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "KasumiMarkdown", targets: ["KasumiMarkdown"]),
        .executable(name: "KasumiRender", targets: ["KasumiRender"]),
        .executable(name: "KasumiReflowLab", targets: ["KasumiReflowLab"]),
        .executable(name: "KasumiReaderBench", targets: ["KasumiReaderBench"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        .package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.9.0"),
        .package(url: "https://github.com/dduan/TOMLDecoder.git", exact: "0.4.5"),
        .package(url: "https://github.com/swhitty/SwiftDraw.git", exact: "0.30.0")
    ],
    targets: [
        nativeTarget("KasumiDagreNative", "kasumi_dagre"),
        nativeTarget("KasumiLineBreakNative", "kasumi_linebreak"),
        nativeTarget("KasumiHyphenationNative", "kasumi_hyphenation"),
        nativeTarget("KasumiSyntaxNative", "kasumi_syntax"),
        .target(
            name: "CSyntax", dependencies: ["KasumiSyntaxNative"], path: "packages/NativeSyntax/Bridge",
            publicHeadersPath: "include"),
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
                "CDagre", "CLineBreak", "CHyphenation", "CSyntax",
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
                .product(name: "SwiftDraw", package: "SwiftDraw")
            ],
            resources: [.copy("Bundled")]
        ),
        .executableTarget(name: "KasumiRender", dependencies: ["KasumiMarkdown"]),
        .executableTarget(
            name: "KasumiReflowLab", dependencies: ["KasumiMarkdown"], path: "tools/ReflowLab",
            exclude: ["README.md"]),
        .executableTarget(name: "KasumiReaderBench", dependencies: ["KasumiMarkdown"], path: "tools/ReaderBench"),
        .testTarget(name: "KasumiMarkdownTests", dependencies: ["KasumiMarkdown"], resources: [.copy("fixtures")])
    ]
)
