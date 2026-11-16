# Goal

Build a native iOS Markdown reader on a reusable rendering library.

## KasumiMarkdown (library)

A Swift package, usable by any iOS or macOS app, that parses Markdown and plain
text, lays it out with high-quality typography and draws it into any
`CGContext`. It supports measured paragraph layout and hyphenation, CJK
punctuation and spacing, native math, Mermaid diagrams, tables, footnotes,
images, themes and typography presets.
It exposes:

- a headless API: parse, lay out at a width, draw, hit-test and select;
- export to paginated PDF, PNG, and JPG;
- ready-made UIKit/AppKit views with SwiftUI wrappers.

Themes and presets are public values that clients can define. Native
dependencies ship inside the package, so adding it is the only setup step.
The library holds no app state.

## Kasumi (iOS app)

A universal iPhone and iPad app built only on the library's public API. It is
an upgrade to <https://tools.konakona.dev/markdown-viewer>: native, with better
typography and features that the library makes possible. The scope is open;
new features are welcome. The first version includes:

- opening documents in place from Files/iCloud, the share sheet, paste, URLs,
  and drag and drop on iPad;
- reading with selection, search, outline, saved reading position, themes and
  presets;
- a plain source editor with live preview, side by side on iPad;
- export to PDF, long PNG, long JPG, print and the share sheet.

## Done means

The library builds and its tests pass on macOS and the iOS simulator, and the
app runs end to end on the simulator.
