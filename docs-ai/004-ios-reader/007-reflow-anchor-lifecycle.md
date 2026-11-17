# 004.007 — Reflow anchor lifecycle corrections

## Context and intended change (2026-11-17)

The frozen reading anchor introduced in `a3bdfb9` survives content revisions without
rebasing, so successive edits can remove all original hashes and restore an
unrelated paragraph. Keyboard-inset handling also scrolls to an active Find
result while the layout adjustment guard suppresses the scroll delegate, leaving
persistence and subsequent reflows anchored at the prior viewport.

- Keep anchor freezing for repeated widths and typography/font changes of the
  same content revision. Rebase after a different content revision is actually
  installed, using that snapshot and the actual clamped viewport top. Carry the
  installed snapshot's revision through the asynchronous pipeline; the latest
  requested revision is not necessarily the installed one.
- Explicitly record and report the actual viewport after keyboard-driven Find
  scrolling, even while incidental layout scroll callbacks are suppressed.
- Use the same clamped-target tracking for outline, Find, and fragment navigation;
  nonanimated navigation records the actual top after setting the offset.
- Put the lifecycle policy beside `ReaderReflowState` so the existing test-target
  symlink compiles the app's actual policy for headless regression tests.

## Validation plan

Reproduce A→B→C edits where the stale A anchor restores block 4 instead of target
7, then verify rebasing on B preserves target 7 on C. Verify intervening width
and style layouts preserve the frozen anchor. Check suppressed programmatic
scroll tracking, including a clamped target. Run focused package checks and
compile the app without a simulator run. Frozen fixtures remain unchanged.

## Implementation and validation

`ReaderReflowAnchorState` keeps the semantic anchor across installs of the same
content revision, including width and font/style changes. A different content
revision refreshes the paragraph keys from the displayed snapshot and clamped
top. The pipeline captures that revision alongside its render session before
awaiting the worker, so it cannot label an older result with a newer revision.
`ReadingSurface.setTop` explicitly tracks navigation when requested; layout
restoration leaves the frozen anchor intact. Keyboard-inset Find scrolling also
reports the resulting position for persistence.

- `make test SWIFT_CONFIGURATION=release FILTER='ReaderReflowTests|reading|ReadingPosition|liveReflowRetainsOriginalAnchor'`:
  11 tests passed, including two new regressions covering successive edits,
  same-content width/style stability, and explicit clamped scroll tracking.
- `make app CONFIGURATION=Release`: passed after the final navigation change.
- No simulator or device runtime verification was performed.

The tests compile the app's actual anchor policy through the existing source
symlink. They do not exercise UIKit callbacks, animation or native display behavior.
