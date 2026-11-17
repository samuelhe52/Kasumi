# 002.008 — Configurable code-block rendering and reader-owned controls

## Context and plan (2026-11-17)

Status: In progress; library complete, reader integration follows separately.
The maintainer approved a configurable rendering style rather than mandatory
reader chrome. This plan preceded the implementation in the combined worktree.

## Library implementation

`CodeBlockStyle` on `RenderStyle` controls background visibility and optional
color override, corner radius, padding, and optional language-caption dimensions,
insets and font size. Defaults use the existing themed background, square
corners, ordinary padding, and no caption/header reservation. Configuration is
per-render and does not alter the persisted typography-profile format.

`RenderedCodeBlock` exposes immutable block/content/optional-caption bounds,
original source, raw first fence-info word, and ID. Captions remain decorative
paint outside semantic text/search. Pagination keeps a caption with the first
code line and bottom padding with the last; long blocks may break between lines.
No Copy button geometry, clipboard state, or native control colors are exposed
by the library.

Key files: `Sources/KasumiMarkdown/CodeBlockStyle.swift`,
`Sources/KasumiMarkdown/CodeBlockLayout.swift`, `RenderStyle.swift` and
`RenderedDocument.swift` in the same source directory,
`Tests/KasumiMarkdownTests/CodeBlockPresentationTests.swift`.
The headless CLI accepts `--code-caption` and `--code-radius POINTS`.

## Reader integration to follow

The reader will explicitly select rounded panels, a caption row large enough
for native Copy controls, and its own button geometry/colors. Its document
exports will choose compact captions without control reservations.

## Validation criteria

Focused tests cover independent defaults and custom styles, optional captions,
background/corner/caption pixels, exact source and semantic invariance, generic
geometry and pagination. Validate the final combined worktree with API/theme/
paragraph/export regressions, headless light/dark/narrow PNG/PDF inspection,
and an unsigned generic-device app build. No simulator/device execution.
Final validation results will be recorded with the reader integration.
