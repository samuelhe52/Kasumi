# 003 — Public rendering API: Plan

| Field | Value |
| --- | --- |
| Status | Implemented (retrospective); native views shipped in [003.004](004-native-reader-views.md) |
| Anchor date | 2026-11-14 |
| Origin | Required by [001](../001-library-and-reader/000-plan.md): the app may use only the library's public API. Reconstructed on 2026-11-15 from Git history during the docs-ai migration; it did not precede the work. |
| Related | [002](../002-rendering-engine/000-plan.md), [004](../004-ios-reader/000-plan.md), [goal](../001-library-and-reader/goal.md) |

## Background

After the AppKit port (`ccf0bee`) every renderer type was reachable by the app.
A client-facing library needs a small, deliberate surface that the reader can be
built on without reaching into internals.

## Goals

- A headless API: parse, lay out at a width, draw, hit-test, select, search, and
  export.
- Layout that can run off the main thread and draw by rect for tiled views.
- Themes and presets as public values that clients can define.
- No app state in the library.

### Non-goals (for now)

- Ready-made UIKit/AppKit views and SwiftUI wrappers were outside the initial
  headless API. They are tracked in [003.004](004-native-reader-views.md).

## Design / approach

Public types (`d44143f`, `377d584`):

- `MarkdownDocument` parses Markdown, plain text, or raw file data and exposes the
  outline (`OutlineItem`).
- `RenderStyle` combines a `TypographyPreset` and a `DocumentTheme` chosen by the
  client; `DocumentThemePair` holds a light and dark theme. `CodeBlockStyle`
  controls background, radius, padding, and optional language captions.
- `RenderedDocument` is an immutable layout. It draws by rect, and handles hit
  testing, selection rects and text, search (`SearchOptions`), links, outline and
  anchor rects, reading anchors (`ReadingAnchor`), and immutable code-panel
  geometry/source (`RenderedCodeBlock`).
- `DocumentExport` returns PDF and PNG data.
- `FontAvailability` reports missing font families.

`DocumentReflowSession` adds a document/style-scoped actor that reuses
width-independent preparation while returning ordinary immutable snapshots.
Clients recreate the session when fonts or external resources change. See
[reflow preparation](../002-rendering-engine/013-reflow-preparation.md).
Its opt-in viewport overload measures nearby paragraphs and estimates offscreen
geometry. `hasEstimatedGeometry` and `needsLayout(in:)` expose that distinction;
clients request another snapshot when scrolling into unmeasured content. Semantic
text stays complete. The default constructor and full-session overload remain
exact. See [viewport layout](../002-rendering-engine/016-viewport-layout.md).

Everything else in `Sources/KasumiMarkdown/` is internal. Font roles resolve
through fallback chains. `Tests/KasumiMarkdownTests/PublicAPITests.swift` covers
the surface (`f26987c`).

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Immutable `RenderedDocument` instead of a mutable layout object | Lets the app lay out on a background task and draw tiles concurrently (`d44143f` message). |
| Stateless library | Product goal: the library holds no app state, and never downloads fonts ([005](../005-cjk-font-availability/000-plan.md)). |
| Theme pairs in the public API | The reader follows system light/dark (`377d584`); the pair is the unit a client selects. |
| Views later, not now | Extract them from a working reader rather than designing them in advance (status document at `fbb13cb`). |

## Evidence and recovered rationale

- Source documents: commit messages `d44143f`, `377d584`, `f26987c`; the status
  and goal documents at `fbb13cb`.
- Inference: none beyond the commit messages.

## Validation and acceptance criteria

`swift test --filter PublicAPITests` on macOS, and the same tests on the iOS
simulator through `make test-ios FILTER=PublicAPITests`.

## Amendments

- Updated 2026-11-17: Expose `RenderedDocument.codeBlocks` with immutable block,
  content and optional-caption bounds, raw language metadata, and complete parsed
  code literals. `RenderStyle.codeBlockStyle` selects presentation; button frames
  and control colors belong to the reader. See
  [002.008](../002-rendering-engine/008-code-block-style-boundary.md), which
  revises the initial API in [002.007](../002-rendering-engine/007-code-block-presentation.md).

- Updated 2026-11-17: Add stateless versioned JSON theme-pair loading and CLI
  selection; see [003.002](002-theme-files.md).

- Updated 2026-11-17: Expose the cached automatic hyphenation dictionary through
  `MarkdownDocument.automaticHyphenationLanguage`; typography profiles control
  display-only punctuation while semantic APIs preserve source marks. See
  [002.012](../002-rendering-engine/012-language-and-punctuation.md).

- Updated 2026-11-17: Added document-scoped reflow sessions — see [002.013](../002-rendering-engine/013-reflow-preparation.md).
- Updated 2026-11-17: Added opt-in viewport snapshots and coverage/semantic navigation queries — see [002.016](../002-rendering-engine/016-viewport-layout.md).
- Updated 2026-11-17: Added a metadata-only conservative vertical text-range query for viewport clients — see [007.004](../007-reader-interactions/004-viewport-find-highlights.md).
- Updated 2026-11-18. Use the theme background color for unavailable images and
  remove `chrome` from the theme API and file format. See [003.003](003-theme-palette-fields.md).
- Updated 2026-11-21: Approved native reader views, SwiftUI Find, and a
  reader-only image provider — see [003.004](004-native-reader-views.md).
- Updated 2026-11-22: Corrected reader focus, background image scheduling,
  link routing, pending Find, and code controls — see [003.005](005-reader-integration-fixes.md).
- Updated 2026-11-22: Share viewport image scheduling and tighten focus, document
  replacement, and section reporting — see [003.006](006-reader-host-lifecycle.md).
