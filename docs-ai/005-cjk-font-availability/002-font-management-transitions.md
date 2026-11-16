# 005.002 — Font management and transitions

The catalog-first layout and per-row controls described here were replaced by
[005.003 — Role-first font management](003-role-first-layout.md). The reader
transition and persistent-opacity findings remain applicable.

## Context

The maintainer reported that font switching animations still fail and the font
management screen needs repair. The referenced Claude Code thread
`0b622e9b-497e-49f4-8424-9732b35cb66b` establishes that Apple fonts must not be
removable and removing an open download must leave its catalog row available.
That thread reported a collection-view crash from destructive swipe actions;
this follow-up does not restore swipe-to-delete.

A baseline screen recording on iPhone 18 Pro, iOS 27.2 shows selection controls
snapping between Use and In Use. The source changes control types and status
text within animated list rows. The reader replaces its tiled page immediately,
before new tiles paint; only its first layout has an explicit fade.

## Change

- Catalog rows retain their geometry through selection and download changes.
  Each phase shares one button with persistent opacity layers rather than
  insertion/removal transitions. Recordings of an intermediate implementation
  still showed snapping despite row-level `.animation`; animating the label
  layers themselves produced intermediate frames. Selection uses a checkmark
  instead of changing between a button and a differently sized In Use badge.
- Source and download size remain visible; a full-width specimen is always
  present, dimmed while unavailable. Its placeholder and installed face
  crossfade. `@ScaledMetric` supplies the size once, with `.custom(fixedSize:)`
  avoiding a second Dynamic Type scale.
- Selection and management have separate, aligned touch targets. Open packages
  have a persistent menu with the license link and, when installed, Remove
  Download. Removal requires confirmation naming the fallback. Rows remain
  available for re-download. Apple faces have no removal action. Supporting
  faces live in a disclosure and report availability rather than claiming every
  preset uses them.
- The reader prepares a viewport-sized raster off-main before replacing its
  tiled page. The raster seeds the new page while asynchronous tiles paint;
  a viewport snapshot of the previous page fades away over 0.22 seconds.
  No full-document bitmap is allocated. Superseded painting is cancelled and
  generation-checked, like layout. The latest semantic anchor is restored.
  Reduce Motion disables the fades.
- `FontStore.use` ignores unavailable faces and already-active selections,
  avoiding unnecessary preference writes and reader rebuilds.

Key files: `apps/iOS/Kasumi/FontStoreView.swift`,
`apps/iOS/Kasumi/FontStore.swift`, `apps/iOS/Kasumi/ReadingSurface.swift`.
No library behavior or frozen reference measurements changed.

## Validation

- `make run-sim` built and installed each refinement, including the final
  persistent-layer implementation. Xcode emitted its supported-platform
  destination diagnostic; builds completed. No package test suite was run:
  these changes are app UI, exercised on the actual surface.
- iPhone 18 Pro, iOS 27.2, driven with `sim-use`:
  - Switched Songti SC ↔ Noto Serif SC and Kaiti SC ↔ LXGW WenKai Lite.
    Selection controls, names, and rows kept their positions.
  - Removed and re-downloaded Noto Serif SC, with maintainer approval for the
    simulator's font files. The row changed to Get, Apple became active, the
    download completed, and the saved open preference became active again.
    No app crash was observed.
  - Observed the download's progress ring and its named Cancel control.
  - Expanded Supporting Faces and checked the downloaded Apple indicators.
  - Checked standard and accessibility-large Dynamic Type. The first large-type
    pass exposed double-scaled custom specimens; the corrected pass displayed
    complete specimens. Restored the original text-size category afterward.
  - Changed reader size, preset and theme; also changed size while scrolled to
    Chinese faces / Mathematics. The same reading passage stayed at the top.
    Restored the original reader appearance and font choices afterward.
- Captured 60-fps recordings and inspected cropped frame sequences and pixel
  changes, not only settled screenshots. Final selection and specimen
  removal/completion show intermediate opacity frames over approximately
  0.22 seconds. Reader size and theme changes dissolve without exposing a blank
  viewport, including at the scrolled anchor. Recordings and screenshots are
  local verification artifacts, not retained in version control.
- Automation failures: one batch tapped the confirmation before presentation
  settled, causing subsequent selector misses and a 90-second command timeout.
  Completing the visible confirmation recovered the flow. A later cancellation
  attempt raced download completion; the font was already installed when the
  following Get lookup ran. Neither attempt demonstrated cancellation.

## Not verified

Active-transfer cancellation, offline/error recovery, Reduce Motion at runtime,
iPad presentation, and physical-device animation performance. The download
backend and its cancellation semantics are unchanged.
