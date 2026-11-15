# 003 — Public rendering API: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-14 | Public surface defined; internals made internal; off-main-thread layout and draw-by-rect | `d44143f` |
| 2026-11-14 | Public API tests | `f26987c` |
| 2026-11-15 | Theme pairs and preset default sizes | `377d584` |

## Outcome and current state (as of 2026-11-15)

The public types listed in the plan exist and are the only surface the iOS app
uses.

Key files:

- `Sources/KasumiMarkdown/MarkdownDocument.swift`
- `Sources/KasumiMarkdown/RenderStyle.swift`
- `Sources/KasumiMarkdown/RenderedDocument.swift`
- `Sources/KasumiMarkdown/DocumentThemePair.swift`
- `Sources/KasumiMarkdown/DocumentExport.swift`
- `Tests/KasumiMarkdownTests/PublicAPITests.swift`

## Deviations from plan

The plan is retrospective.

## Validation

Reconstructed from Git; nothing was rerun for this record.

## Open questions

- Ready-made views and SwiftUI wrappers are not built.
- Clients can't depend on the package by URL until the XCFrameworks are
  distributable ([001](../001-library-and-reader/001-action.md)).
