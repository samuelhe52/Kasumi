# 002.029 — Basic HTML, scripts, and SVG

## Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-11-18 |
| Origin | Maintainer-approved Basic HTML and SVG plan and implementation request |

README files use HTML for aligned headers, badges, and supplementary content.
Kasumi should render those constructs in the native reader and in exports.

- Parse inline HTML within each Markdown container. Convert HTML blocks into
  renderer blocks and carry alignment and details state across siblings. Use
  ordinary image runs and keep details expanded in the reader and exports.
- Protect Pandoc-style single-delimiter scripts before GFM parsing. Use the
  existing pre-pass and leave fenced code, inline code, HTML ranges and GFM
  strikethrough in their current parsing paths. Swift Markdown fixes the cmark
  options, and this feature does not require a fork.
- Use the footnote scale for scripts and the existing underline renderer for
  explicit underlines. Recognize only the HTML attributes that affect the
  supported constructs and drop tags such as script together with their content.
- Pin SwiftDraw 0.30.0 for iOS and macOS. Keep the image-store byte limit and
  check the 3× bitmap dimensions before allocation. Accept partial rendering.
  The same path serves local and remote SVGs and leaves PDF images rasterized.
- Verify parser, layout and image behavior in focused tests, run the release
  reader benchmark before and after, and inspect the README and PDF export on
  the approved iPhone simulator.

See [renderer gaps](renderer-gaps.md) for the remaining HTML and SVG scope.

## Outcome

`HTMLFragment.swift` uses the existing cmark entity decoder and emits native
blocks and runs. The block context keeps alignment and details across Markdown
siblings, including closing tags that cmark places inside a paragraph. HTML
headings participate in the outline. Image runs retain their alt text, link, and
dimensions. The iOS reader now preloads remote images through the existing
bounded image store and rebuilds its layout after new dimensions become available.
This wiring covers remote Markdown images as well. [Viewport image decoding](031-viewport-image-decoding.md)
later moved pixel loading to the visible region.

`MarkdownExtensions.swift` uses byte searches to skip its first Markdown parse
when ordinary prose contains no extension syntax. Closed script spans share
the math placeholder pass and respect code and HTML ranges. GFM still handles
double tildes and spaced strikethrough. Typography shares the footnote script
scale and superscript shift. Subscripts use a 0.15 em baseline drop. The
paragraph engine excludes both kinds of script runs from dictionary hyphenation.

`SVGImageDecoder.swift` rasterizes with SwiftDraw 0.30.0 after ImageIO fails.
The decoder checks the scaled bounds before allocating the bitmap. The app
bundles SwiftDraw's zlib notice.

## Validation

The focused run passed 15 tests. The macOS package suite completed with 276
reported tests and four opt-in performance tests skipped. An earlier concurrent
build and test run failed the remote image cache assertions. Both the focused
run and the full rerun without concurrent builds passed. The frozen reference
measurements required no updates. `make licenses`, `make app-check-sim`, and
`make run-sim` completed.

On the iPhone 18 Pro simulator with iOS 27.2, the reader showed a centered SVG
logo, both a local and a live shields.io badge, the expanded summary, the inline
HTML formatting, and both HTML and Markdown scripts. The HTML heading appeared
in Outline. A one-page A4 export opened in Preview. Its PDF contained three
raster images and annotations for the linked badge and the HTML text link.

### Performance

Both `make benchmark-reader` runs completed all 46 cases on an Apple M1 Pro.
The table uses the quick report's cold parse p50 with two fresh workers per
case. The paired columns use the separate parse-and-outline diagnostic on the
same files, with 15 fresh processes per version for cold and five processes
per version for warm. Values are milliseconds.

| Sample | Quick cold p50 before → after | Paired cold median before → after | Paired warm median before → after |
| --- | ---: | ---: | ---: |
| English 50k | 1.32 → 1.41 | 1.396 → 1.408 | 0.821 → 0.794 |
| Chinese 50k | 1.60 → 1.65 | 1.710 → 1.601 | 1.100 → 0.998 |
| Single Chinese paragraph 50k | 1.00 → 1.11 | 1.011 → 0.924 | 0.611 → 0.507 |
| Mixed 50k | 16.34 → 19.56 | 16.902 → 17.174 | 6.561 → 6.792 |
| Mixed 200k | 39.96 → 36.78 | 37.723 → 37.022 | 25.411 → 25.963 |

The paired runs show faster warm prose parsing and a 0.012 ms increase in the
cold English median within overlapping observed ranges. The mixed documents'
warm medians rose by 2–4%. The 64 KB HTML-heavy sample with 60 README copies
rose from 7.696 to 15.403 ms when its HTML gained structure. Its outline
grew from 60 to 120 headings. That sample runs as a parse diagnostic because
image-bearing documents fall outside the fixed corpus's idle-preparation
envelope. See [reader benchmark diagnostics](../../benchmarks/reader/README.md).

SVG decode medians were 12.190 ms cold and 1.514 ms warm for the badge, and
6.148 ms cold and 0.352 ms warm for the logo. Each asset used seven fresh
processes with 100 subsequent decodes per process. The measurements exclude
file reads, network, cache hits, and document layout.

The reader now rasterizes SVGs at their fitted display size. See
[002.030](030-reader-svg-raster-size.md) for the sizing policy and chapter benchmark.
