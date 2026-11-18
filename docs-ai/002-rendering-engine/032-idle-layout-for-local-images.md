# 002.032 — Idle layout for documents with local images

## Context

A warm image raster cache does not eliminate viewport refinement. Repeated
passes through an image-heavy chapter at 942 × 709 pt rebuilt 10–13 snapshots
per pass, taking 35 ms median for layout, with zero raster decodes after the
first pass. A separate full snapshot probe on the same chapter took about
170 ms and added 11–12 MiB of process footprint on macOS after one viewport
paint. Image pixels remained deferred in both conditions.

## Plan

Extend reusable, width-specific idle layout to reader sessions that explicitly
enable local image preparation. Retain the existing text, table and diagram
limits. Check image sources for local files or embedded data with known
dimensions and bound their occurrence count. Late remote dimensions can
invalidate geometry, so remote images stay on the viewport layout path.

Apply the reader's metadata-only image policy to the intermediate batches
and the final snapshot. Reuse the existing idle scheduler and width epoch.
Enable the path in Reflow Lab and expose a launch environment switch for iOS
validation. Measure the actual batched path, resident footprint and
same-width reuse before changing the iOS default.

Validate equivalence with a full layout, width invalidation, deferred pixels,
local and embedded eligibility, and remote/eager-session exclusions.

## Adjustment during implementation

The representative CPU chapter has a 96-cell control-signal table. The
first candidate returned without preparing geometry because it kept the
existing 64-cell eligibility limit. The opt-in path now allows up to 128
cells per table and 512 across tables when the document contains eligible
images. The text-only envelope retains its existing limit.

## Outcome

`DocumentReflowSession` checks the local image sources when the host requests
idle preparation. Intermediate batches and the complete snapshot use the
session's reader image policy. The complete snapshot is reused at the same
width and rebuilt after resizing. Raster variants still enter the decoded
cache on viewport demand. Reopening the document starts a new session for
replaced local assets.

Reflow Lab enables local image preparation. On iOS the validation launch
environment enables it explicitly: on the booted simulator, run
`SIMCTL_CHILD_KASUMI_READER_IMAGE_IDLE_PREPARATION=1 make run-sim`, and use the
same prefix with `make launch-sim` to repeat the launch without rebuilding.
The reader's optional scroll diagnostics
record whether the current snapshot has complete geometry.

## Validation

The focused idle tests passed, followed by 46 image, viewport, and reflow
tests. They cover a 96-cell table, local SVG and PNG, an embedded PNG,
remote and missing image exclusions, same-width snapshot identity, and
width invalidation. No reader raster results existed after preparing the
test document. `make check-reflow-lab` and `make run-sim` passed. Reflow Lab
reported **Entire document measured** with the CPU chapter open.

The Reflow Lab smoke check also opens an embedded SVG and waits for idle
installation without scrolling. It reproduced the stale image queue before
the fix. The idle install now refreshes visible-image requests after restoring
the scroll position, and the smoke check verifies the queue's snapshot identity.

On an iPhone 18 Pro simulator running iOS 27.2, an opt-in Debug launch
displayed SVG diagrams after an outline jump and forward and return scrolls.
All 305 sampled moving callbacks after complete geometry had measured
viewports. These are coverage samples.

A same-binary Release replay on an M1 Pro used seven alternating process
pairs per geometry on the CPU chapter. The time excludes the host's
200 ms idle delay. The current footprint was sampled at the preparation
boundary before raster requests. Lifetime peak includes the replay. The
return count covers five repeated passes through the selected section.

| Viewport | Idle work, ms | Return layout rebuilds, control → prepared | Footprint at preparation boundary, MiB | Lifetime peak, MiB |
| --- | ---: | ---: | ---: | ---: |
| 942 × 709 pt, 2× | 989 | 59 → 0 | 17.0 → 28.5 | 74.9 → 65.8 |
| 402 × 874 pt, 3× | 921 | 58 → 0 | 16.9 → 28.8 | 46.2 → 34.3 |

The complete snapshot was reused in every opt-in trial. At preparation
completion no reader raster results existed. During the first traversal the
two conditions loaded the same five rasters at 2× and four at 3×. Physical
iPhone memory and frame delivery remain unmeasured.
