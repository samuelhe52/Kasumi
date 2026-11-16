# 002.006 — Reflow preparation and break selection

## Context and intended changes (2026-11-17)

The reader's serialized resize queue still reconstructs every paragraph. Mac
profiling found repeated break-candidate span scans and per-character Han
attribute mutations dominate Chinese layouts; English also scales poorly with
length. This follow-up implements the first renderer optimizations before a
larger viewport/estimated-height redesign.

- Accumulate each active predecessor's item totals incrementally as break
  candidates advance. Keep the original Float addition order, tie ordering,
  emergency policy, and frozen geometry; avoid prefix subtraction, whose rounding
  can change marginal break decisions. Reuse candidate scratch arrays.
- Apply identical adjacent Han font/baseline attributes as ranges rather than
  mutating attributed storage once per character. Preserve punctuation faces,
  supplementary characters, and inline-run metadata.
- Add a document/style-scoped actor (`Sources/KasumiMarkdown/DocumentReflowSession.swift`) that
  retains width-independent attributed text and measured paragraph input between
  widths. Recreate it on content, style, or font revision changes. Images and
  other width-dependent attachments must rebuild; each snapshot continues owning
  its own Core Text layout objects and interaction indices.
- Keep ordinary `RenderedDocument` construction and export behavior available.
  No reference executable or machine-local tooling becomes a build dependency.

## Validation plan

Run frozen paragraph/shaping/typography tests, compare cached and fresh snapshots
across widths and attachment/table cases, and repeat optimized headless English
and Chinese workloads with drawing measured separately. Compile the app without
launching a simulator. Report measured speedups and remaining whole-document cost;
these changes alone do not establish interactive frame-rate parity.

## Outcome (2026-11-17)

Implemented on 2026-11-17 in the live-text-reflow worktree.

- `Sources/KasumiMarkdown/ParagraphEngine.swift` retains accumulated Float totals
  on each active predecessor and extends them to the next legal candidate in the
  original addition order. Candidate buffers are reused; fitness/tie ordering and
  rescue behavior stay unchanged. No frozen expectations were modified.
- `Sources/KasumiMarkdown/Typography.swift` batches adjacent identical Han font
  and baseline assignments, retaining separate punctuation faces and original
  UTF-16 grapheme ranges.
- `Sources/KasumiMarkdown/DocumentReflowSession.swift` provides the public actor
  and its internal document-bounded preparation cache. Attribute entries use
  block/call-slot identity and validate their run/style arguments; paragraph
  entries retain normalized text and measured clusters/fonts, with size/verbatim
  checks. Entries do not accumulate per width. Each render has an autorelease
  pool, so temporary Foundation objects drain before returning the snapshot.
- `DocumentLayout.swift`, `Typography.swift`, and
  `MeasuredParagraphTypesetter.swift` consume optional preparation. Ordinary
  `RenderedDocument` construction and exports still work without a session.
- `apps/iOS/Kasumi/ReadingSurface.swift` replaces the session on content, style,
  or font revisions and reuses it on width changes. Shutdown releases its session.
- Image paragraphs rebuild because their attachment sizes/resources can change.
  Math paragraphs also rebuild: math attachments can own CTLine objects, which
  cannot be shared between snapshots protected by different locks. Verbatim and
  RTL paths retain their existing breaking policy; leading RTL text does not
  acquire an unnecessary shaping pass.

## Validation

- `make test SWIFT_CONFIGURATION=release
  FILTER='ParagraphEngineTests|DocumentReflowTests|ReaderReflowTests|liveReflowRetainsOriginalAnchor|paragraph|ShapedClusterIntegrityTests|typography|PunctuationFont|DocumentFont|TableLayoutTests|PublicAPITests|Underline'`:
  reported 57 tests passing; the opt-in timing test was skipped. This includes all
  782 frozen paragraph cases, shaped-cluster integrity, drawing/underline behavior,
  public API/export/table coverage, scheduler tests, and anchor checks.
- The capitalized font terms above do not select the standalone lowercase test
  names. `make test SWIFT_CONFIGURATION=release
  FILTER='punctuation|documentFont|bundledDocument'` separately passed 10 tests,
  covering punctuation font/baseline assignment, whole graphemes, inline metadata,
  and concurrent font registration.
- `DocumentReflowTests` verifies preparation is actually reused across widths,
  cached/fresh paragraph geometry and interaction geometry agree, pixels match,
  previous snapshots remain unchanged, and new style sessions change geometry.
  The 100 pt case forces the 32 px image to resize; math objects are explicitly
  checked for distinct ownership across snapshots.
- `make app CONFIGURATION=Release`: succeeded after the final source changes.
  Xcode emitted its existing no-AppIntents metadata-extraction warning. This was
  compilation only; no simulator was launched or used for this optimization.
- `git diff --check`: passed. Reference fixtures were not changed. No external
  application or analysis tooling is required by these tests/builds.

### Release timing

Apple M1 Pro, macOS 27.2.1. The same English/Chinese sources as the reproduction:
500-character paragraphs, fixed 16 pt text, no width cap, parsed once, warmed at
600 pt, then measured at 800, 500, 400, 700, and 440 pt. Each row is the median and
maximum of those five widths. Before values were refreshed using the retained
unoptimized probe. After values are from the repository's opt-in
`KASUMI_REFLOW_TIMING=1 make test SWIFT_CONFIGURATION=release
FILTER=macReflowTimings` on the final code. They include the session/actor call and
its local autorelease-pool drain, but exclude parsing, cold preparation, drawing,
Find, and UIKit installation. Languages differ in glyph widths and line counts.

| Text / characters | Before median / max (ms) | After repeat median / max (ms) |
| --- | --- | --- |
| English / 2,000 | 5.58 / 6.93 | 2.55 / 2.72 |
| Chinese / 2,000 | 22.62 / 40.05 | 5.37 / 6.74 |
| English / 10,000 | 19.90 / 26.58 | 11.94 / 13.22 |
| Chinese / 10,000 | 111.30 / 190.36 | 26.55 / 32.41 |
| English / 50,000 | 102.11 / 128.36 | 57.53 / 60.02 |
| Chinese / 50,000 | 543.49 / 938.91 | 130.46 / 159.53 |

The first final-code timing run was slower: English medians 3.20 / 14.87 / 63.96
ms and Chinese medians 6.14 / 30.48 / 146.98 ms. Its 50k Chinese maximum was
431.14 ms. The cause of that outlier is unverified; the repeat above was performed
because of it. These are local samples, not a tail-latency guarantee.

An isolated 5,000-character Chinese engine pass using pre-shaped input fell from
28.05 ms median in the earlier phase probe to 5.29 ms (10 samples) after the break
optimization. A warm session's complete 5,000-character Chinese paragraph
snapshot measured 16.33 ms median / 21.65 ms max (10 samples), versus 55.49 ms
median in the earlier cold-preparation full-layout phase probe. A Time Profiler
recording after the algorithm/cache changes showed attributed construction and
shaping had mostly left the repeated-width path; break selection and Core Text
line construction remain substantial. That trace preceded the final local-pool
and RTL preparation adjustment. Local probe/trace artifacts are not retained as
repository dependencies.

## Remaining work

The warm Chinese workload is about four times faster, and English improves too.
A 50k document still needs a full layout and immutable indices before publication;
130 ms plus painting/installation is too slow for continuous frame-rate resizing.
Viewport-first block measurement with indexed estimated heights remains the next
architectural step. Interactive smoothness, memory peaks, and on-device behavior
were not measured. This slice does not establish parity with another app.

The next exact optimization slice is recorded in [007 — metadata reuse](007-reflow-metadata.md).
