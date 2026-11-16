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

The `KasumiRender` command renders a file without launching the app:

```sh
swift run KasumiRender fixtures/Rendering.md out.png 800 --preset serif --theme mono-light
```

## Origins

Kasumi's approach to typography is inspired by [Telari](https://telari.app/), a macOS Markdown reader built for typography. Kasumi began as a study of it, and some rendering behaviors follow Telari's closely. We thank the Telari developers for the work that inspired this project.

## License

[MIT](LICENSE). The bundled fonts and Rust dependencies carry their own licenses; their notices are in `Sources/KasumiMarkdown/Bundled/` and `packages/*/Notices/`.
