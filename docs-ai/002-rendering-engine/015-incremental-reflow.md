# 002.015 — Incremental reflow and publication

## Context

Large mixed documents repeat offscreen preparation and measurement on viewport
requests. Moving reading anchors can also invalidate every completed request.
The maintainer authorized autonomous optimization on 2026-11-17, with Mac-only
validation and no simulator runs.

## Change

- Separate request validity from whether its target anchor has moved. Publish
  compatible results only when the current visible region is measured, and
  recheck that coverage after prepainting. Preserve the current semantic anchor.
- Cache immutable paragraph geometry and table widths at a fixed width. Recreate
  snapshot-local Core Text lines and fragment stores from geometry; do not share
  mutable layout objects between independently locked snapshots.
- Defer shaping until exact layout needs it. Use lightweight semantic storage
  and cheap height estimates for eligible offscreen text; retain the exact path
  for attachment-dependent storage and unsupported cases.
- Measure first viewport, fixed-width refinement and width changes for 50k/200k
  mixed documents. Keep full layout/export exact and preserve search, anchors,
  selection, pixels, resource invalidation and concurrent snapshot ownership.

## Decisions

Retaining existing CTLine-bearing paragraphs under independent snapshot locks
would violate their ownership contract. Cache geometry instead. Removing anchor
validation without checking coverage could publish a stale or blank viewport;
coverage is part of publication validity. Estimated offscreen text is never
painted as if exact.

## Validation criteria

Extend the existing scheduler, viewport and preparation suites with moving
anchors, cache reuse, cold deferred preparation, concurrent retained snapshots,
and exact visible output. Run focused Release tests and the packaged native Mac
harness. External diagnostics remain optional local investigation tools, outside
build/test dependencies. No frozen measurement changes are intended.

## Current state

Implemented in the live-reflow worktree on 2026-11-17. Full
layout/export retain their exact path. Viewport layout now measures nearby tables
as a unit and keeps resource-dependent images/diagram fallbacks exact. The last
measured window seeds the next request, without accumulating every visited
paragraph into the working set. Complete document metadata is built only for the
final placement pass.

The reader refills when the expanded query reaches unmeasured geometry while
three quarters of a screen of spare measured content remain. Merely increasing
the layout buffer while retaining the old late refill threshold did not eliminate
coverage gaps. Previously measured table column widths also remain stable when
the table becomes offscreen again.

Key sources: `Sources/KasumiMarkdown/ParagraphLayoutGeometry.swift`,
`Sources/KasumiMarkdown/DocumentReflowSession.swift`,
`Sources/KasumiMarkdown/ViewportLayout.swift`, `Sources/KasumiMarkdown/DocumentLayout.swift`,
`Sources/KasumiMarkdown/ReflowSemanticContent.swift`, `Sources/KasumiMarkdown/MathAttachment.swift`,
`Sources/KasumiMarkdown/MarkdownExtensions.swift`,
`apps/iOS/Kasumi/ReaderReflowState.swift`, `apps/iOS/Kasumi/ReadingSurface.swift`, and
`tools/ReflowLab/`. The geometry cache excludes hyphenated/legacy lines; recreated
logical lines and fragment stores belong to the new snapshot.

Cold parsing skips unnecessary extension passes and regex work, reuses the first
AST when footnote rewriting is absent, and maps math source lines by binary search
instead of rescanning the source prefix for every expression. ASCII delimiter
checks use UTF-8 bytes rather than grapheme-aware substring searches. Semantic maps
assemble Foundation substrings in UTF-16 and transcode once to contiguous UTF-8;
an intermediate warm CPU trace attributed approximately 70% of sampled work to
the previous semantic-map path. Reading-key hex formatting preserves the existing
SHA-256 representation without per-byte Foundation formatting.

## Boundary lookup decision

Inspection during implementation found that the complete grapheme-boundary array
is used only to obtain text length and snap an individual hit-test offset. Replace
that eager document-wide array with UTF-16 length and a local composed-character
query, checked against Swift Character boundaries on Unicode examples. This
avoids deferring a whole-document scan into the first interaction.

## Validation and measured outcome

Apple M1 Pro, macOS 27.2.1. No simulator was booted or used. The full Release
library run passed **243 tests in 18 suites**, including frozen geometry and
parser expectations, concurrent snapshots, visible pixel comparisons, source
line ranges, local Unicode snapping, metadata offset changes and scheduler
publication. No frozen expectations changed.

Commands: `make test SWIFT_CONFIGURATION=release`, `make check-reflow-lab`,
`make benchmark-reflow-lab`, and `make check-reflow-scrolling`. The packaged Mac
smoke check passed. Two consecutive final scrolling runs each sampled 201 points
per size, with **zero unmeasured viewports across 804 samples** and 41 useful
installations per case. This is offscreen AppKit coverage metadata from 80-point
steps requested every 16 ms, not per-frame pixel evidence, inertial trackpad
behavior, UIKit runtime validation or FPS.

Same-protocol, statically linked before/after Mac probes used the exact lab
samples, 1179 × 701 pt viewport, 18 pt text and no width limit. Timings below
exclude painting, publication and snapshot disposal. Parsing is separate. Warm
medians use 12 requests. Font/OS caches were not reset.

| Mixed case | Parse before → after | First snapshot before → after | Warm width median before → after | Repeated fixed-width median after |
| --- | --- | --- | --- | --- |
| 50k nominal | 17–19 → 7.9 ms | 196–205 → 22.1 ms | 13–17 → 6.7 ms | 2.2 ms |
| 200k nominal | 69–75 → 26.7 ms | 730–784 → 31.3 ms | 44–45 → 8.8 ms | 3.7 ms |

A final baseline 50k cold run spiked to 355 ms; it is an outlier, not the basis of
the improvement claim. Moving-anchor medians improved from roughly 17–18/47–56 ms
to 11.4/13.7 ms for 50k/200k. Plain Chinese 50k warm width changes rose slightly
(from roughly 4.5–5.7 to 6.3 ms) with the larger measured buffer; fixed-width reuse
and cold layout improved. The four-case probe peak process footprint fell from
about 70.5 MB to 35.7 MB; this is one workload's measurement, not a memory cap.

The integrated Mac benchmark, which interleaves width changes, scrolling and
painting, recorded mixed first snapshots of 29.6/31.2 ms. SDR 2× viewport painting
still cost about 14–15 ms. Timings have scheduling tails: one Chinese moving-anchor
sample reached 183 ms during an earlier run. Do not infer stable frame delivery
from medians or coverage metadata.

Intermediate validation caught and corrected two behavioral regressions: list
markers accidentally used lightweight styling before measurement, and local
Foundation grapheme queries separated CRLF where Swift Character does not.
The final tests preserve both cases. Earlier scrolling runs still showed short
gaps (up to about 76 ms); only the final earlier-refill policy produced two
consecutive zero-gap captures. Local logs/traces and JSON are not retained as
repository evidence; the observed outcomes are recorded here.

## Remaining work

- Complete opening includes parsing, drawing, installation and display. The first
  viewport construction now avoids whole-document shaping, but parsing and
  placement/semantic assembly still scale with document size.
- A persistent block-height/placement index, idle warming, paint reuse and
  snapshot-retirement tails remain possible follow-ups. Native bitmap painting
  remains a substantial cost. The broader pipeline has not demonstrated stable
  120 Hz presentation.
- Images, diagrams, enormous individual paragraphs, and a very large visible
  table retain their existing worst cases. No iOS runtime check is part of this work.

The Release UIKit app also compiled successfully for `generic/platform=iOS` with
code signing disabled, using a temporary local Makefile and isolated derived
data. No device installation or simulator operation was performed. The packaged
Mac app passed strict signature verification, and its final offscreen scroll
capture was visually inspected with text present throughout the captured view.
