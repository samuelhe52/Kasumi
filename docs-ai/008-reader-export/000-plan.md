# 008 — Reader export: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-11-16 |
| Origin | Maintainer requested milestone 3 with performance in mind and PDF, long PNG, and long JPG. |
| Related | [Goal](../001-library-and-reader/goal.md), [public API](../003-public-rendering-api/000-plan.md) |

## Background

The library already exports PDF and PNG, but the reader has no export workflow.
Both file exporters currently build the complete encoded result in memory before
writing it. Long bitmap exports additionally require a full uncompressed image.

## Goals

- Export PDF, long PNG, and long JPG from the reader, plus print and system sharing.
- Keep expensive layout, drawing, and encoding off the main actor.
- Add public file export APIs with progress, cooperative cancellation, configurable
  bitmap limits, and transactional output; retain existing Data APIs.
- Preserve selectable PDF text and the chosen typography/theme. PDF uses print
  body size; image output uses the selected reading style and a configurable width/scale.
- Measure representative export time and peak memory, and record the limits of
  those measurements.

## Design / approach

Extend `DocumentExport.swift` and `DocumentExporter.swift` with JPEG support and
file-backed image/PDF destinations. Lay out once per job; scope transient PDF
objects per page. Bound bitmap allocation before creating a context and expose
useful errors. Check cancellation before/after layout, during drawing, and before
publishing output. Add `apps/iOS/Kasumi/ReaderExport.swift` for options,
job ownership, temporary file lifetime, system sharing, and printing. Wire it
from `ReaderScreen.swift`'s persistent actions control.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| File output for the app | Avoid retaining complete encoded Data alongside drawing resources. Data APIs remain for existing clients. |
| Explicit bitmap limits | ImageIO needs a complete source image; drawing in strips alone would not remove that allocation. Oversized requests should offer lower resolution or PDF. |
| Export-owned layout | Avoid holding the visible reader snapshot's Core Text lock throughout encoding; omit selection/search index construction. |
| Native print/share controllers | Preserve standard destinations, file saving, and printer UI on iPhone and iPad. |
| Cooperative cancellation | Core Text layout and ImageIO finalization are synchronous; cancellation takes effect at safe boundaries rather than promising immediate interruption. |

## Validation and acceptance criteria

Focused library tests cover file PDF text/pagination, both image encodings,
geometry, bitmap limits, cancellation, and output preservation. Build the iOS
app. Use the already booted iPhone simulator for export/share/print checks with
`sim-use`; ask before booting any other simulator. Inspect exported images/PDF
and measure representative CLI exports with elapsed time and maximum resident
memory. Physical-device memory/latency and actual printer delivery may remain
unverified and must be reported as such.

## Amendments

- Updated 2026-11-16: implemented; simulator checks were curtailed by the maintainer-requested reboot. See [action and validation limits](001-action.md).
- Updated 2026-11-17: added paper, margin and font-size choices and scaled export captions. See [export options](002-export-options.md).
- Updated 2026-11-27: shared visual export options, native Mac Export, and semantic plain-text copy — see [Mac export and copy](003-mac-export-and-copy.md).
