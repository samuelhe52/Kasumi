// swift-tools-version: 6.2
import PackageDescription

// A checkout opts into its own Rust builds with `make native-local`.
// Release automation replaces this block with immutable URLs and checksums.
// BEGIN RELEASE NATIVE BINARIES
let releasedNative: [String: (url: String, checksum: String)] = [
    "KasumiDagreNative": (url: "https://github.com/samuelhe52/Kasumi/releases/download/0.1.0/kasumi_dagre.xcframework.zip", checksum: "d42e383990697ac0c9fbb5f2bb45db3a2ef29eb9c0a60062751a2ffc23b1476e"),
    "KasumiLineBreakNative": (url: "https://github.com/samuelhe52/Kasumi/releases/download/0.1.0/kasumi_linebreak.xcframework.zip", checksum: "58f1f39851eba4f65520b3da933d9b6bb128bf8ef46c44fea1a5183778c9455d"),
    "KasumiHyphenationNative": (url: "https://github.com/samuelhe52/Kasumi/releases/download/0.1.0/kasumi_hyphenation.xcframework.zip", checksum: "1bd29473e5f815ac9640a23f30fa7baf7cb3b410039f7f07b47d54e8bccfbe73"),
    "KasumiSyntaxNative": (url: "https://github.com/samuelhe52/Kasumi/releases/download/0.1.0/kasumi_syntax.xcframework.zip", checksum: "030404e6802fb4c583c740a7fa0786c48a7070a937ee8d6c29a511d5e01404c2"),
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
    platforms: [.iOS(.v17), .macOS(.v13)],
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
