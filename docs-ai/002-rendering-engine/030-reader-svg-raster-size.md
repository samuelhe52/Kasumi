# 002.030 — Display-sized SVG rasters in the reader

## Context

SVG diagrams in real chapter-length documents establish why raster size matters.
A phone-width reader fits the image to its reading measure, but the original
decoder rasterizes the full intrinsic canvas at 3×. The layout retains those
bitmaps as attachments.

## Plan

The reader requests SVG pixels at the fitted document size times its display
scale. Use the existing attachment sizing rules for HTML dimensions and table
cells. Store reader variants by resource revision and pixel dimensions. Keep
the existing intrinsic 3× path for export and other full-document clients.
Remote reader preloading should make the bounded SVG source available for
layout without creating an intrinsic raster. Verify that reflow preserves image
geometry and that export still requests its own raster after a reader open.

Viewport-based scheduling of image resources is a separate reader decision.

## Outcome

The iOS reader supplies its display scale to `DocumentReflowSession`.
The image store shares the same fitting calculation with the attachment.
The store keys fitted SVG rasters by source revision and resulting pixel
dimensions. A bounded source cache lets the remote reader preload validate
and retain SVG bytes for layout. Full-document clients request the original
intrinsic 3× raster. Both paths retain the SVG byte and canvas limits.

## Validation

The focused image, HTML, reflow, and export checks passed 33 tests.
The full macOS suite reported 279 tests with four opt-in timing tests skipped.
The new tests check authored HTML sizes, fitted cache reuse, SVG preload,
and both raster resolutions using the same local and remote sources.
`make app-check-sim` and `make run-sim` passed. On the iPhone 18 Pro simulator
running iOS 27.2, the reader fixture displayed the centered logo and both badges.
A CLI export of the same fixture embedded the original 360×288, 264×60, and
234×60 SVG rasters and retained both link annotations.

Paired Release runs on an M1 Pro opened the original chapter files at
402×874 pt and 3×. Each median uses seven fresh processes per condition.
The measurement includes file read, parse, layout, and first viewport bitmap.
Peak footprint is the OS process measurement in MiB.

| Chapter | First bitmap, ms | Peak footprint, MiB |
| --- | ---: | ---: |
| 2D Observation | 249 → 207 | 40.4 → 30.3 |
| CPU | 638 → 442 | 65.0 → 50.1 |
| Pipeline CPU | 442 → 369 | 77.8 → 33.0 |
| Memory Hierarchy | 580 → 462 | 42.7 → 31.3 |

Both versions produced the same document heights in these runs. The figures
cover the macOS engine and exclude UIKit presentation and physical iPhone
latency. At this stage, attachment layout still rasterized offscreen images.
[Viewport image decoding](031-viewport-image-decoding.md) later moved pixel
loading out of reader layout.
