# Using KasumiMarkdown

KasumiMarkdown is the Swift package behind the Kasumi reader. It parses Markdown, lays it out with Kasumi's typesetting engine, and draws it into any `CGContext`. This guide covers installation, the rendering API, customization, and the command-line renderer. For a quick start, see the [README](../README.md#using-the-library).

## Requirements and installation

KasumiMarkdown requires Swift 6.2 or later and supports arm64 macOS 13+, iOS 15+, and iOS Simulator. Tagged releases include a prebuilt Rust XCFramework.

Set compatible deployment targets in your package manifest, such as `platforms: [.macOS(.v13), .iOS(.v15)]`.

You can use local native builds. Clone the repository, run `make native-local`, and add the checkout as a local Swift package. Building needs Rust with the `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets; see the [README](../README.md#building).

A tagged checkout can also use local binaries with `make native-local`. This changes its `Package.swift` locally. Run `make native-release` to select its published binaries again.

## Embedding a native reader

The `KasumiMarkdownUI` product adds a scrolling reader view for UIKit, AppKit, and SwiftUI, with selection, links, Find, wide tables, and VoiceOver. It has the same iOS 15 and arm64 macOS 13 minimums as `KasumiMarkdown`. If you only render or export, you don't need it.

```swift
.product(name: "KasumiMarkdownUI", package: "Kasumi")
```

### SwiftUI

```swift
import KasumiMarkdown
import KasumiMarkdownUI
import SwiftUI

@available(iOS 16, *)
struct DocumentView: View {
    let document: MarkdownDocument
    let fileURL: URL
    @State private var showFind = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        MarkdownReaderScope { reader in
            MarkdownReader(document: document, documentURL: fileURL)
                .markdownFindNavigator(isPresented: $showFind)
                .onMarkdownLink { url in openURL(url) }
                .toolbar {
                    Menu("Outline") {
                        ForEach(document.outline) { item in
                            Button(item.title) { reader.scroll(toAnchorID: item.id) }
                        }
                    }
                    Button("Find") { showFind = true }
                        .keyboardShortcut("f", modifiers: .command)
                }
        }
    }
}
```

`MarkdownReader` scrolls by itself; give it the space it should fill and don't put it inside another scroll view. Pass the file's URL as `documentURL`. The reader resolves relative images against it, follows links to headings in the same file, and uses it to recognize an edited version of the same document.

The reader follows links to headings and footnotes within the document. Every other link goes to `.onMarkdownLink`; without that callback, it does nothing. The reader has no toolbar of its own, so Find, outline, and appearance controls belong to your app.

`markdownFindNavigator(isPresented:)` shows the system Find panel on iOS 16 and later and on macOS, which is why the example is marked iOS 16. The binding also turns false when the user closes the panel. On iOS 15, or to use your own search field anywhere, drive Find through the scope's proxy: `setFindQuery(_:options:)`, `moveToFindMatch(.next)` or `.previous`, and `clearFind()`. `.onMarkdownFindResultChange` reports the match count and the zero-based index of the current match. Only one search is active at a time: setting a query closes the system panel, and opening the panel clears your query.

The proxy also scrolls: `scroll(toAnchorID:)` takes an `OutlineItem.id`, and `scroll(to:)` takes a saved `ReadingAnchor`. A proxy controls the one `MarkdownReader` inside its `MarkdownReaderScope`.

### Saving the reading position

`.onMarkdownPositionChange { anchor, sectionID in … }` reports where the reader is as the user scrolls. `anchor` is a `ReadingAnchor`, which is `Codable` and survives changes to fonts, window size, and small edits. `sectionID` is the `OutlineItem.id` of the current heading, or `nil` before the first one. To restore a position, pass the saved anchor as `initialAnchor`.

`initialAnchor` applies when the reader first shows a document and whenever `document` or `documentURL` changes. Later updates ignore it, so use the proxy to move within a document already on screen. If you replace the document and keep the same `documentURL`, as after an edit, the reader keeps the user's place. A new document with no URL starts at the top unless you pass an anchor.

The last position change can arrive just after the reader leaves the view hierarchy. Save it to your model rather than to the view.

### Other reader options

- `isActive: false` pauses background layout and input, for example while the reader is hidden behind another pane, and keeps its scroll position. On iOS it also fades the reader out.
- Change `layoutRevision` when something the reader can't see has changed, such as a font that finished downloading. The reader then lays the document out again.
- `.markdownCodeBlockControl(id:_:)` (iOS) adds your own control, such as a Copy button, to code blocks. The factory receives each `RenderedCodeBlock` and returns a `UIControl` with a frame in document coordinates, or `nil` to skip that block. Without an `id`, the reader rebuilds the controls on every SwiftUI update, which resets any state they hold. Pass an `id` that changes only when the factory's output would change, such as its tint color.

### UIKit and AppKit

Both platforms have a view named `MarkdownReaderView`. Create one with `MarkdownReaderView(frame: .zero)`, constrain it to the space it should fill, set its `style`, and call `setDocument(_:url:restoring:)`. The `url` and `restoring` arguments behave like `documentURL` and `initialAnchor` above, except that `restoring` always applies.

| SwiftUI | UIKit and AppKit view |
| --- | --- |
| `.onMarkdownLink` | `onOpenLink` |
| `.onMarkdownPositionChange` | `onPositionChange` |
| `.onMarkdownFindResultChange` | `onFindResultChange` |
| `.markdownFindNavigator(isPresented:)` | `presentFind()`, `dismissFind()`, `isFindPresented`, `onFindPresentationChange` |
| proxy commands | the same methods on the view |
| `isActive`, `layoutRevision` | `isActive`, `invalidateLayout()` |
| `.markdownRemoteImages(_:revision:)` | `setRemoteImages(_:revision:)` |
| `.markdownCodeBlockControl(id:_:)` | `codeBlockControl` (UIKit) |
| `.markdownScroller(_:)` | `scrollerClass` (AppKit) |

Enable a Find button only when `canPresentFind` is true. `presentFind()` called while a document is still opening shows the panel as soon as the first screen is laid out.

### Reader images

The reader shows local and embedded images. It doesn't load HTTP(S) images unless you opt in. `.markdownRemoteImages(.http)` (or `setRemoteImages(.http)`) downloads them with the library's size-limited downloader. To serve images from your own cache or an authenticated loader, write a provider:

```swift
let images = MarkdownRemoteImages { url in
    guard let bytes = try await myCache.imageData(for: url) else { return nil }
    return try MarkdownImageResource(encodedData: bytes)
}
```

Create the configuration once and keep it, for example in your model. Each `MarkdownRemoteImages` value has its own identity, and passing a new one clears the reader's image cache. Creating one inside `body` would clear it on every update.

Return `nil` to leave an image out; the reader then shows the placeholder and doesn't try another loader. A thrown error does the same. To draw the pixels yourself, return `MarkdownImageResource(intrinsicSize:rasterize:)`. `intrinsicSize` is in points. The reader calls `rasterize` in the background with a target size in pixels, and it may call it again at another size.

Edits that keep the same `documentURL` reuse images already loaded. To load the same URLs again, increase the `revision` argument of `.markdownRemoteImages(_:revision:)` or `setRemoteImages(_:revision:)`. The provider is used only by the reader views. `DocumentExport` keeps its own explicit preload.

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
