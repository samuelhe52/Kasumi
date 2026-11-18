# 002.031 — Viewport image decoding

## Context

Reader layout needs oriented dimensions for block images, inline attachments,
and table columns. Holding decoded bitmaps in those attachments makes an open
pay for images well below the viewport and keeps their pixels alive as long as
the layout is retained.

## Plan

Keep image geometry and semantic text in the layout. Read source dimensions
during layout and schedule pixel decoding after the reader presents the
viewport. Track horizontal visibility in scrollable tables. Reuse fitted
rasters within a bounded reader cache and repaint affected tiles on completion
without rebuilding the layout. The reader's existing bounded remote preload
supplies dimensions and encoded data. PDF and image export continue through
the full-document path.

Check initial and scrolled image pixels, stable geometry and links, table
visibility, and export. Compare cold engine opening and peak process footprint
on the same SVG-heavy notes used for display-sized rasterization.

## Outcome

Reader layout uses ImageIO properties for orientation and dimensions. Common
SVGs use the root dimensions and viewBox, with SwiftDraw supplying dimensions
when the root uses other sizing syntax. Reader layout snapshots retain image
geometry, alt text and links. They share a 64 MiB decoded cache with the reflow
session. Fitted rasters target display scale and roughly four million pixels
per image.

The iOS reader schedules one decode at a time after publishing a viewport.
Work that leaves the viewport is cancelled cooperatively, and completed
bitmaps invalidate their tiles, including tiles in independently scrolling
tables. Fetched remote resources still supply geometry through the existing
whole-document preload. That preload retains encoded data and decodes pixels
only when the reader requests them. Export continues to use its full-document
layout and intrinsic SVG rasters.

## Validation

The focused image, HTML, reflow and viewport checks passed 50 tests. The
export filter passed 21 tests. Initial builds exposed a Core Foundation
sendability error and a synthesized equality error. Both were resolved before
the simulator build. The first cache-eviction check used a budget large enough
to hold both fixtures. The corrected budget exercises eviction and reload.

`make app-check-sim` and `make run-sim` passed. On one iPhone 18 Pro simulator
running iOS 27.2, the centered logo and badge appeared on the first screen, a
local PNG appeared on vertical scroll and on an outline jump, and a table
displayed the trailing image after horizontal scroll. A remote SVG badge also appeared. The reader's
PDF export rendered the same content across two pages, with a 640×320 PNG and
intrinsic SVG rasters on the second page.

`make benchmark-reader` completed all 46 quick-profile children. A separate
paired Release comparison used 402×874 pt at 3× and seven fresh macOS processes
per condition on an M1 Pro. The eager baseline already used fitted SVG rasters.
Opening includes read, parse, layout and first bitmap. Footprint is the OS
process peak in MiB.

| Chapter | First bitmap, ms | Peak footprint, MiB |
| --- | ---: | ---: |
| 2D Observation | 190 → 72 | 30.1 → 25.4 |
| CPU | 420 → 76 | 50.0 → 25.7 |
| Pipeline CPU | 306 → 65 | 32.5 → 25.9 |
| Memory Hierarchy | 313 → 66 | 31.3 → 24.9 |

These four chapters open on text. Their document heights matched and the
reader decoded zero opening rasters. The README fixture reached its first
bitmap in 34 ms, then its bitmap with both visible local SVGs in 41 ms. The
eager baseline reached its image-complete first bitmap in 40 ms. These
measurements cover the macOS engine. Physical-device latency and memory remain
unmeasured.
