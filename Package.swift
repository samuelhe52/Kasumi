// swift-tools-version: 6.2
import PackageDescription

// A checkout opts into its own Rust builds with `make native-local`.
// Release automation replaces this block with immutable URLs and checksums.
// BEGIN RELEASE NATIVE BINARIES
let releasedNative: [String: (url: String, checksum: String)] = [:]
// END RELEASE NATIVE BINARIES
let native = ".build/native"
// Local mode changes this checkout-only switch for a tagged release.
let forceLocalNative = false // KASUMI_LOCAL_NATIVE_MODE
let useLocalNative = releasedNative.isEmpty || forceLocalNative
func nativeTarget(_ name: String, _ library: String) -> Target {
    if useLocalNative { return .binaryTarget(name: name, path: "\(native)/\(library).xcframework") }
    guard let artifact = releasedNative[name] else { fatalError("Missing release binary: \(name)") }
    return .binaryTarget(name: name, url: artifact.url, checksum: artifact.checksum)
}

let package = Package(
    name: "KasumiMarkdown",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "KasumiMarkdown", targets: ["KasumiMarkdown"]),
        .executable(name: "KasumiRender", targets: ["KasumiRender"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        .package(url: "https://github.com/dduan/TOMLDecoder.git", exact: "0.4.5")
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
                "CDagre", "CLineBreak", "CHyphenation", "CSyntax", .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder")
            ],
            resources: [.copy("Bundled")]
        ),
        .executableTarget(name: "KasumiRender", dependencies: ["KasumiMarkdown"]),
        .testTarget(name: "KasumiMarkdownTests", dependencies: ["KasumiMarkdown"], resources: [.copy("fixtures")])
    ]
)
