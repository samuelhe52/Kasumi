# 007 — Reader selection, find, and links: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-11-16 |
| Origin | Maintainer request to implement reader milestone 2. Written before implementation. |
| Related | [Reader shell](../004-ios-reader/000-plan.md), [public API](../003-public-rendering-api/000-plan.md), [roadmap](../roadmap.md) |

## Background

The tiled reader already exposes semantic hit testing, selection geometry, search,
and link targets through `RenderedDocument`, but has no UIKit selection adapter
or find controls. External links currently open immediately.

## Goals

- Native read-only UIKit text selection, adjustment handles, Select All, and Copy.
- An in-reader find bar with match count, previous/next navigation, wrapping,
  visible highlights, and Command-F access.
- Confirm external link opening while preserving internal heading and footnote jumps.
- Preserve tiled drawing, reading position, soft toolbar edges, and Reduce Motion.

### Non-goals

Editing, export, replacing the renderer with TextKit, or repairing existing
renderer shaping changes already present in the working tree.

## Design / approach

- Add a read-only `UITextInput` adapter to the rendered page, with
  `UITextInteraction(for: .nonEditable)` owning selection gestures and UI.
  Positions remain tied to their immutable rendered snapshot. Clear selection
  when replacing that snapshot, so no old geometry or positions survive reflow.
- Extend `Sources/KasumiMarkdown/RenderedDocument.swift` with checked UTF-16
  position arithmetic for UIKit tokenization; retain opaque layout ownership.
- Add proposed reader interaction source files under `apps/iOS/Kasumi/` for the
  UIKit adapter and find state/bar. Draw search highlights separately from tiles
  and scroll the active result into the visible viewport.
- `ReaderScreen.swift` owns find presentation and external-link confirmation.
  `ReadingSurface.swift` connects geometry, scrolling, and page lifetime.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| UIKit interaction over the existing rendered page | Retains Kasumi layout and native handles/menu. A hidden UITextView would have different line geometry. |
| Separate find highlights from selection | Navigating matches must not steal text-field focus or show selection handles. |
| Clear selection, recompute search on reflow | Layout-owned positions cannot safely be carried between snapshots. |
| Inline find bar | Keeps results visible while typing and navigating, unlike an outline-style search sheet. |

## Validation and acceptance criteria

- Focused public API tests for position arithmetic, foreign snapshot rejection,
  UTF-16 offsets, invalid offsets, and existing semantic geometry/search behavior.
- `make app` builds the complete iOS app.
- Use the already booted iPhone simulator through `sim-use` to inspect selection,
  Copy, find navigation/no results/dismissal, internal links, and external-link
  cancel/open confirmation. Do not boot another simulator without permission.
- Record runtime coverage and omissions explicitly in the action record. Frozen
  reference measurements should remain unchanged because drawing is unchanged.

## Amendments

- Completed 2026-11-16; see the [action record](001-action.md) for implementation and validation limits.
