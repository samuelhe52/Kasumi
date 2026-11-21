// swift-tools-version: 6.2
import PackageDescription

// A checkout opts into its own Rust builds with `make native-local`.
// Release automation replaces this block with immutable URLs and checksums.
// BEGIN RELEASE NATIVE BINARIES
let releasedNative: [String: (url: String, checksum: String)] = [:]
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
    defaultLocalization: "en",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "KasumiMarkdown", targets: ["KasumiMarkdown"]),
        .library(name: "KasumiMarkdownUI", targets: ["KasumiMarkdownUI"]),
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
        nativeTarget("KasumiNative", "kasumi_native"),
        .target(
            name: "CSyntax", dependencies: ["KasumiNative"], path: "packages/NativeSyntax/Bridge",
            publicHeadersPath: "include"),
        .target(
            name: "CDagre", dependencies: ["KasumiNative"], path: "packages/NativeDagre/Bridge",
            publicHeadersPath: "include"),
        .target(
            name: "CLineBreak", dependencies: ["KasumiNative"], path: "packages/NativeLineBreak/Bridge",
            publicHeadersPath: "include"),
        .target(
            name: "CHyphenation", dependencies: ["KasumiNative"], path: "packages/NativeHyphenation/Bridge",
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
        .target(
            name: "KasumiMarkdownUI", dependencies: ["KasumiMarkdown"],
            resources: [.process("Resources")]),
        .executableTarget(name: "KasumiRender", dependencies: ["KasumiMarkdown"]),
        .executableTarget(
            name: "KasumiReflowLab", dependencies: ["KasumiMarkdown", "KasumiMarkdownUI"], path: "tools/ReflowLab",
            exclude: ["README.md"]),
        .executableTarget(name: "KasumiReaderBench", dependencies: ["KasumiMarkdown"], path: "tools/ReaderBench"),
        .testTarget(name: "KasumiMarkdownTests", dependencies: ["KasumiMarkdown"], resources: [.copy("fixtures")]),
        .testTarget(name: "KasumiMarkdownUITests", dependencies: ["KasumiMarkdown", "KasumiMarkdownUI"])
    ]
)
