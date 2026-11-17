<div align="center">
  <img src="docs/images/kasumi-icon.png" alt="Kasumi app icon" width="160" />

  <h1>Kasumi</h1>

  <p>A native iOS reader for Markdown, set with care.</p>

  <p>
    <img src="https://img.shields.io/badge/platform-iOS%20%C2%B7%20iPadOS%2027%2B-34C759" alt="iOS and iPadOS 27 or later" />
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License" />
  </p>
</div>

---

## Overview

Kasumi sets every page with its own typesetting engine: no web view, no `UITextView`. Paragraphs are justified with real hyphenation, punctuation hangs in the margin, and Latin and CJK text sit together with tuned spacing. Math and Mermaid diagrams are typeset natively alongside tables and footnotes, and the text stays selectable and searchable. It is built on **KasumiMarkdown**, a Swift package for parsing, layout and drawing.

## Features

### Typography

- Justified paragraphs with real hyphenation
- Hanging punctuation and ligatures
- Tuned spacing and punctuation for CJK text
- Seven typography presets and adjustable text size

### Themes

- Four light and dark pairs: Default, Mono, One and Solarized
- Follows the device appearance

### Content

- Tables, footnotes and images
- Math set in TeX Gyre Pagella Math or New Computer Modern
- Mermaid diagrams laid out natively: flowchart, sequence, state, class, ER, pie and mindmap

### Reading

- Opens `.md` and `.txt` files in place from Files and iCloud, or through the share sheet
- Outline, text selection, and Find in Page
- Remembers your reading position
- Works on iPhone and iPad

### Library

- The same engine is available headless as KasumiMarkdown
- PDF and PNG export, hit-testing and search

## Building

Needs Xcode 27, Swift 6.2+, and Rust (edition 2024) with the `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets.

```sh
make help        # list targets
make test        # swift test on macOS (FILTER=<name> to narrow)
make test-ios    # package tests on the iOS Simulator
make app         # build the iOS app for the simulator
make run-sim     # build and launch on an already booted simulator
make run-device  # build and run on a connected iPhone or iPad
```

## Using the library

KasumiMarkdown supports iOS 17 and macOS 13. It is not yet distributable by URL: it depends on locally built Rust XCFrameworks, and shipping prebuilt ones is on the roadmap. For now, work from a checkout.

```swift
import KasumiMarkdown

let document = MarkdownDocument(markdown: source)
let style = RenderStyle()  // default preset and theme
let rendered = RenderedDocument(document, width: 390, style: style)

rendered.draw(in: context, rect: visibleRect)  // any CGContext
let pdf = try DocumentExport.pdf(document, style: style)
let png = try DocumentExport.png(rendered, scale: 2)
```

`RenderedDocument` also answers hit-testing, selection rectangles, text search, outline positions and link lookups for one immutable layout. Presets and themes are public values that clients can define.

Custom presets accept standard TOML through `TypographyPreset(id:name:toml:)`.
Put overrides in `[profile]`, for example `hyphenation_language = "fr"` or
`base_size = 18`. Malformed syntax and duplicate keys throw errors. Profile
files use `[meta]` for their name and `[anchor]` for a saved factory snapshot;
unrelated tables never contribute typography overrides. The reader currently
offers built-in presets only.

Automatic hyphenation uses a supported front-matter `lang:` tag, then a bounded
stopword vote over prose, then US English. The result is cached when parsing and
exposed as `MarkdownDocument.automaticHyphenationLanguage`; an explicit preset
language takes precedence. English regional spelling is not guessed: use
`en-GB` in front matter or `en-gb` in the profile for British patterns.

`punct_strategy = "fold"` displays the eight ASCII marks `, . ; : ! ? ( )` as
full-width punctuation near Han text; `"spacing"` keeps the original marks and
adds ⅛ em on each adjoining non-whitespace side. The default is `"faithful"`.
These display policies preserve original punctuation for library/reader copy,
search and accessibility, and protect numbers, code, math, links and footnote
markers. Paragraphs containing kana or Hangul stay literal. Han-only Japanese
is ambiguous under this lightweight script heuristic. Both modes are available
in the CLI as `--punct-strategy fold` or `--punct-strategy spacing`.

Load a custom light/dark theme with `try DocumentThemePair(contentsOf: url)` or
`try DocumentThemePair(json: data)`, then pass its `.light` or `.dark` theme to
`RenderStyle`. [CustomTheme.json](fixtures/CustomTheme.json) shows the version-1
format: `schema_version`, `id`, `name`, and `light`/`dark` palettes containing
optional `document`, `chrome`, and `syntax` color maps. Colors use `#RRGGBB` or
`#RRGGBBAA`; the bundled RGBA/system-color forms are also accepted. Omitted
document colors inherit Classic for the chosen appearance. Files are limited
to 4 MiB; loading does not change the built-in catalog.

The `KasumiRender` command renders a file without launching the app:

```sh
swift run KasumiRender fixtures/Rendering.md out.png 800 --preset serif --theme mono-light
swift run KasumiRender fixtures/Rendering.md out.png 800 --theme-file fixtures/CustomTheme.json --dark
```

## Origins

Kasumi's approach to typography is inspired by [Telari](https://telari.app/), a macOS Markdown reader built for typography. Kasumi began as a study of it, and some rendering behaviors follow Telari's closely. We thank the Telari developers for the work that inspired this project.

## License

[MIT](LICENSE). The bundled fonts and Rust dependencies carry their own licenses; their notices are in `Sources/KasumiMarkdown/Bundled/` and `packages/*/Notices/`.
