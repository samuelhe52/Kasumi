# 002 — Native rendering engine: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-14 | Paragraph typesetting foundation | `5d3478f` |
| 2026-11-14 | Footnotes and math source preservation; native math with bundled font metrics | `9ad1e61`, `fcb5351` |
| 2026-11-14 | Images and document export | `8f7fe94` |
| 2026-11-14 | Plain-text parsing and legacy text decoding | `b128aca` |
| 2026-11-14 | Reading sessions and document change tracking | `2b8b991` |
| 2026-11-14 | Pinned Dagre bridge; Mermaid diagrams across eight families | `5f77eee`, `b285445` |
| 2026-11-14 | Pinned TOML bridge, then typography presets and eight document themes (121 tests per the commit message) | `7c17639`, `2199837` |
| 2026-11-14 | Profile files in the line format; TOML bridge removed (143 tests per the commit message) | `80d8a99` |
| 2026-11-14 | Math profiles, punctuation faces, PDF body size; heading and code size rounding | `09ddbfd`, `ecedbdd` |
| 2026-11-14 | Pinned Unicode line-break and hyphenation bridges; measured paragraph layout and hyphenation | `bdb5dea`, `3914150` |
| 2026-11-14 | Ported off AppKit | `ccf0bee` |

## Outcome and current state (as of 2026-11-15)

The engine described in the plan exists in `Sources/KasumiMarkdown/` and is
reached only through the public API in
[003](../003-public-rendering-api/000-plan.md). Known limitations are the living
[renderer-gaps.md](renderer-gaps.md).

Key files: see the plan's Design section; tests in `Tests/KasumiMarkdownTests/`,
reference data in `fixtures/reference/`.

## Deviations from plan

The plan is retrospective. The macOS app these commits were built in was removed
in `55b03b8`; reading sessions moved to the iOS app's per-file reading position.

## Validation

Reconstructed from Git; nothing was rerun for this record. See
[001](../001-library-and-reader/001-action.md) for the last recorded test totals.

## Open questions

- 10 tests that pin Apple CJK faces skip on iOS because the faces aren't
  installed; see [005](../005-cjk-font-availability/000-plan.md).
