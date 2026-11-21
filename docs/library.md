# Using KasumiMarkdown

KasumiMarkdown is the Swift package behind the Kasumi reader. It parses Markdown, lays it out with Kasumi's typesetting engine, and draws it into any `CGContext`. This guide covers installation, the rendering API, customization, and the command-line renderer. For a quick start, see the [README](../README.md#using-the-library).

## Requirements and installation

KasumiMarkdown requires Swift 6.2 or later and supports arm64 macOS 13+, iOS 15+, and iOS Simulator. Tagged releases include prebuilt Rust XCFrameworks.

Set compatible deployment targets in your package manifest, such as `platforms: [.macOS(.v13), .iOS(.v15)]`.

You can use local native builds. Clone the repository, run `make native-local`, and add the checkout as a local Swift package. Building needs Rust with the `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets; see the [README](../README.md#building).

A tagged checkout can also use local binaries with `make native-local`. This changes its `Package.swift` locally. Run `make native-release` to select its published binaries again.

## Embedding a native reader

Add the `KasumiMarkdownUI` product to your target for UIKit, AppKit, or SwiftUI. It uses the same iOS 15 and arm64 macOS 13 minimums as `KasumiMarkdown`. Use the headless product alone if you only render or export.

```swift
import KasumiMarkdown
import KasumiMarkdownUI
import SwiftUI

struct DocumentView: View {
    let document: MarkdownDocument
    @State private var showFind = false

    var body: some View {
        if #available(iOS 16, *) {
            MarkdownReader(document: document)
                .markdownFindNavigator(isPresented: $showFind)
                .toolbar {
                    Button("Find") { showFind = true }
                        .keyboardShortcut("f", modifiers: .command)
                }
        } else {
            MarkdownReader(document: document)
        }
    }
}
```

Give the reader a viewport; do not wrap it in another scroll view. The host supplies toolbar controls and handles external links through `.onMarkdownLink`. Heading and footnote links within the document work without a callback. Use `MarkdownReaderScope` for outline jumps or custom Find. Its proxy accepts `setFindQuery`, `moveToFindMatch`, and `clearFind`; `.onMarkdownFindResultChange` reports the count and zero-based current index. On iOS 15, use these commands with a host search field instead of a system Find panel.

In UIKit or AppKit, embed a `MarkdownReaderView(frame: .zero)` and constrain it to the available space. Set its `style` and call `setDocument(_:url:restoring:)`. Use `scroll(toAnchorID:)` for outline actions and `onPositionChange` to save a `ReadingAnchor` in your app. Use `canPresentFind` and `presentFind()` for a native Find button.

Both native readers preserve the reading position when replacing content at the same non-nil URL. A distinct document without a URL starts at the top unless you supply a `restoring` anchor.

SwiftUI consumes `initialAnchor` when the document or its URL changes. Use the scope proxy to navigate an already displayed document. A final queued `.onMarkdownPositionChange` may be delivered after the reader is removed.

On UIKit, `.markdownCodeBlockControl(id:_:)` adds app-provided controls to code blocks. Without an ID, the reader refreshes controls on SwiftUI updates. Supply an ID that changes with the factory's configuration to keep existing controls during unrelated updates.

### Reader images

Remote HTTP(S) images do not load by default. Use `.markdownRemoteImages(.http)` or `setRemoteImages(.http)` to opt in to Kasumi's bounded downloader. For an app-managed byte cache or authenticated loader, create one `MarkdownRemoteImages` configuration and keep it across view updates:

```swift
let images = MarkdownRemoteImages { url in
    guard let bytes = try await myCache.imageData(for: url) else { return nil }
    return try MarkdownImageResource(encodedData: bytes)
}
```

To supply custom pixels, return `MarkdownImageResource(intrinsicSize:rasterize:)`. The async rasterizer receives a bounded target size in pixels. A decline or failure uses the document placeholder; the reader does not try another loader. Change the configuration or its `revision` to reload the same URLs. The provider only affects reader views; `DocumentExport` continues to use its own explicit preload.

## Rendering a document

```swift
import KasumiMarkdown

let document = MarkdownDocument(markdown: source)
let style = RenderStyle()  // default preset and theme
let rendered = RenderedDocument(document, width: 390, style: style)

rendered.draw(in: context, rect: visibleRect)  // any CGContext
```

`MarkdownDocument` also accepts plain text (`init(plainText:)`) and file data (`init(data:fileExtension:)`). `RenderedDocument` is an immutable layout for one width and style; create a new one when either changes.

## Exporting

```swift
let pdf = try DocumentExport.pdf(document, style: style)
let png = try DocumentExport.png(rendered, scale: 2)
```

## Querying a layout

`RenderedDocument` answers hit-testing, selection rectangles, text search, outline positions and link lookups for one immutable layout.

```swift
let matches = rendered.ranges(matching: "typography")  // [TextRange]
let rects = matches.first.map(rendered.selectionRects)  // highlight rectangles
let url = rendered.link(at: tapPoint)                   // URL? under a point
```

## Presets and themes

Presets and themes are public values that clients can define. Pass them to `RenderStyle`.

### Custom presets

Custom presets accept standard TOML through `TypographyPreset(id:name:toml:)`. Put overrides in `[profile]`, for example `hyphenation_language = "fr"` or `base_size = 18`. Malformed syntax and duplicate keys throw errors.

Profile files use `[meta]` for their name and `[anchor]` for a saved factory snapshot. Unrelated tables never contribute typography overrides. The reader currently offers built-in presets only.

### Custom themes

Load a custom light/dark theme with `try DocumentThemePair(contentsOf: url)` or `try DocumentThemePair(json: data)`, then pass its `.light` or `.dark` theme to `RenderStyle`.

[CustomTheme.json](../fixtures/CustomTheme.json) shows the version-1 format with `schema_version`, `id`, `name`, and `light`/`dark` palettes. Each palette accepts optional `document` and `syntax` color maps. Colors use `#RRGGBB`, `#RRGGBBAA`, or the bundled RGBA and system-color forms. Omitted document colors inherit Classic for the chosen appearance. Files are limited to 4 MiB, and loading leaves the built-in catalog intact.

`document.image_placeholder_background` colors the area behind the fallback text for unavailable block and inline images. The fallback text uses `document.secondary_text`.

## Language and punctuation

### Hyphenation language

Automatic hyphenation uses a supported front-matter `lang:` tag, then a bounded stopword vote over prose, then US English. The result is cached when parsing and exposed as `MarkdownDocument.automaticHyphenationLanguage`; an explicit preset language takes precedence.

English regional spelling is not guessed: use `en-GB` in front matter or `en-gb` in the profile for British patterns.

### Punctuation display

`punct_strategy = "fold"` displays the eight ASCII marks `, . ; : ! ? ( )` as full-width punctuation near Han text. `"spacing"` keeps the original marks and adds ⅛ em on each adjoining non-whitespace side. The default is `"faithful"`.

These display policies preserve original punctuation for library/reader copy, search and accessibility, and protect numbers, code, math, links and footnote markers. Paragraphs containing kana or Hangul stay literal. Han-only Japanese is ambiguous under this lightweight script heuristic.

## Command-line renderer

`KasumiRender` renders a file without launching the app:

```sh
swift run KasumiRender fixtures/Rendering.md out.png 800 --preset serif --theme mono-light
swift run KasumiRender fixtures/Rendering.md out.png 800 --theme-file fixtures/CustomTheme.json --dark
```

Both punctuation modes are available as `--punct-strategy fold` or `--punct-strategy spacing`. Run it with no arguments to print the full option list.
