# 004.009 — Preserve scroll momentum during reader reflow

## Context

On 2026-11-18, the maintainer reported that an ordinary vertical swipe in the
reader coasted for roughly half a second after finger lift and then stopped
abruptly. The report used Paste Markdown with the text from
`Pasted 2026-11-18 at 21.30.04.textClipping`, a 281-line
Markdown document starting with `# 存储器层次结构`. It contains Chinese prose,
math, tables, and a Mermaid diagram. For the simulator reproduction, open the
clipping's exact plain text as a UTF-8 `.md` file, then make several vertical
swipes about 430 points long over 0.30 seconds. Let each swipe settle and test
both directions away from the document edges.

## Cause and change

Installing a refined viewport snapshot restores the current semantic reading
anchor. `ReaderScrollView` used `setContentOffset(_:animated:)` with
`animated: false` for that restore. On iOS 27.2, the scroll view was still
decelerating after its content size update and stopped immediately after the
offset call, even when the old and requested offsets were equal.

Snapshot installation now assigns UIKit's `contentOffset` property directly.
This applies the anchor correction while preserving the running deceleration.
Explicit navigation continues to use `setContentOffset(_:animated:)`.
Skipping same-position writes alone left a reverse swipe that stopped when
refinement needed a larger offset correction. A probe confirmed that the
property setter applied an approximately 82-point correction and kept the
scroll view decelerating.

## Verification

On an iPhone 18 Pro simulator running iOS 27.2, six baseline swipes away from the
edges stopped immediately after a sampled movement of about 11–23 points. All
seven interior swipes on the final build slowed gradually in both directions,
reaching a one-pixel step before stopping. Two further swipes on the final build
exercised the top edge. These measurements came from the reader's display-link
diagnostics and describe sampled scroll offsets. Physical-device scrolling and
the clipboard import flow were outside the runtime check.

`make app` succeeded. `make test FILTER=ReaderReflowTests` passed all eight tests.

## Refs

- [Reader snapshot installation and offset restoration](../../apps/iOS/Kasumi/ReadingSurface.swift)
- [Reader scroll diagnostics](../../apps/iOS/Kasumi/ReaderScrollDiagnostics.swift)
- [Related viewport snapshot work](../002-rendering-engine/022-incremental-reflow.md)
