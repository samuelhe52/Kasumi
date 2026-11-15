# 003 — Public rendering API: Plan

| Field | Value |
| --- | --- |
| Status | Implemented (retrospective); ready-made views planned |
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

- Ready-made UIKit/AppKit views and SwiftUI wrappers. They will be extracted from
  the reader once its views settle ([roadmap](../roadmap.md)).

## Design / approach

Public types (`d44143f`, `377d584`):

- `MarkdownDocument` parses Markdown, plain text, or raw file data and exposes the
  outline (`OutlineItem`).
- `RenderStyle` combines a `TypographyPreset` and a `DocumentTheme` chosen by the
  client; `DocumentThemePair` holds a light and dark theme.
- `RenderedDocument` is an immutable layout. It draws by rect, and handles hit
  testing, selection rects and text, search (`SearchOptions`), links, outline and
  anchor rects, and reading anchors (`ReadingAnchor`).
- `DocumentExport` returns PDF and PNG data.
- `FontAvailability` reports missing font families.

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

None yet.
