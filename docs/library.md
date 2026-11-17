# Using KasumiMarkdown

KasumiMarkdown is the Swift package behind the Kasumi reader. It parses Markdown, lays it out with Kasumi's typesetting engine, and draws it into any `CGContext`. This guide covers installation, the rendering API, customization, and the command-line renderer. For a quick start, see the [README](../README.md#using-the-library).

## Requirements and installation

KasumiMarkdown supports arm64 macOS 13, iOS 17 and iOS Simulator. It needs Swift 6.2 or later. Release tags use prebuilt Rust XCFrameworks, so adding the package needs no Rust toolchain.

You can use local native builds. Clone the repository, run `make native-local`, and add the checkout as a local Swift package. Building needs Rust with the `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets; see [development.md](development.md#setup).

A tagged checkout can also use local binaries with `make native-local`. This changes its `Package.swift` locally. Run `make native-release` to select its published binaries again.

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

[CustomTheme.json](../fixtures/CustomTheme.json) shows the version-1 format: `schema_version`, `id`, `name`, and `light`/`dark` palettes containing optional `document`, `chrome`, and `syntax` color maps. Colors use `#RRGGBB` or `#RRGGBBAA`; the bundled RGBA/system-color forms are also accepted. Omitted document colors inherit Classic for the chosen appearance. Files are limited to 4 MiB; loading does not change the built-in catalog.

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
