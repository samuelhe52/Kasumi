# 002 — Native rendering engine: Plan

| Field | Value |
| --- | --- |
| Status | Implemented (retrospective); known gaps tracked in [renderer-gaps.md](renderer-gaps.md) |
| Anchor date | 2026-11-14 |
| Origin | Built on 2026-11-14, before the refocus in [001](../001-library-and-reader/000-plan.md). Reconstructed on 2026-11-15 from Git history during the docs-ai migration; it did not precede the work. |
| Related | [Renderer gaps](renderer-gaps.md) (living), [003](../003-public-rendering-api/000-plan.md), `fixtures/reference/` |

## Background

Kasumi's reason to exist is typography that a web Markdown viewer can't match
([goal](../001-library-and-reader/goal.md)). That needs control over line
breaking, hyphenation, CJK punctuation and spacing, math, and diagrams, beyond what
an attributed string laid out by Core Text alone provides.

## Goals

- A paragraph engine that measures, breaks, hyphenates, shapes, and draws lines
  itself, falling back to Core Text where it has no implementation.
- Native math and Mermaid rendering, footnotes, tables, images, plain-text
  documents with legacy encodings, typography presets and profiles, document
  themes, and paginated PDF / PNG export.
- Layout behavior pinned by frozen measurements so changes are deliberate.

## Design / approach

- Paragraphs: `ParagraphEngine.swift`, `ParagraphBreaker.swift`,
  `ParagraphHyphenation.swift`, `ParagraphShaping.swift`,
  `ParagraphGlyphDrawing.swift`, and `MeasuredParagraphTypesetter.swift`.
  Unicode line breaking and hyphenation come from pinned Rust crates behind small C
  interfaces in `packages/NativeLineBreak` and `packages/NativeHyphenation`
  (`bdb5dea`, `3914150`).
- Math: `MathParser.swift`, `MathLayout.swift`, `MathFont.swift` with bundled math
  font metrics (`fcb5351`, `9ad1e61`).
- Diagrams: eight Mermaid families (`Mermaid*.swift`), with graph layout from the
  pinned Dagre bridge in `packages/NativeDagre` (`5f77eee`, `b285445`).
- Profiles and presets: `TypographyProfile.swift`, `ProfileFileDocument.swift`,
  `ProfileLibrary.swift`; themes in `DocumentTheme.swift` (`2199837`, `80d8a99`,
  `09ddbfd`).
- Plain text: `PlainTextParser.swift`, `DocumentDecoding.swift` (`b128aca`).
- Export: `DocumentExporter.swift`, `DocumentPagination.swift` (`8f7fe94`).
- Regression data: `fixtures/*.md` documents and `fixtures/reference/*.json`
  measurements, compared by the tests in `Tests/KasumiMarkdownTests/`.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Own paragraph engine instead of Core Text framesetting alone | The measured layout and hyphenation targets need per-line control (`3914150`). Right-to-left paragraphs still fall back to Core Text. |
| Rust crates behind C bridges for line breaking, hyphenation, and graph layout | Pinned, tested implementations instead of reimplementing Unicode line breaking, hyphenation patterns, and Dagre. Reason inferred from the commits; the original discussion isn't recorded. |
| Profile files in a nonstandard line format, not TOML | `80d8a99` replaced a strict TOML bridge with a parser/writer for an existing line format, for compatibility with that format. Recalled discussion (2026-11-14): the maintainer prefers moving to standard TOML for UX; implemented with standard TOML on 2026-11-17; see [002.011](011-standard-toml-profiles.md). |
| Frozen reference measurements as tests | Keeps layout changes deliberate. `AGENTS.md` requires updating the expectation in the same commit when a change alters covered behavior. |

## Evidence and recovered rationale

- Source documents: the commit messages listed above; the renderer docs written
  in `910384a` and deleted in `69877d1` (available in Git history).
- Recalled discussion: the TOML preference above.
- Inference: the reason for using Rust bridges.

## Validation and acceptance criteria

Library tests pass on macOS and the iOS simulator, including comparisons against
`fixtures/reference/`.

## Amendments

- Updated 2026-11-17: Implement adaptive table columns and independent reader scrolling
  — see [005-table-layout.md](005-table-layout.md).

- Updated 2026-11-14: Ported off AppKit to Core Graphics and Core Text with
  platform color and font aliases (`ccf0bee`); recorded in
  [001](../001-library-and-reader/001-action.md).
- Updated 2026-11-16: Preserve shaped ligature spans and complete Han-mark
  advances — see [002-shaped-cluster-integrity.md](002-shaped-cluster-integrity.md).
- Updated 2026-11-16: Replace native link underlines with muted, baseline-relative
  document decorations — see [003-link-decoration.md](003-link-decoration.md).
- Updated 2026-11-16: Unify ordinary and link underline rendering, including
  glyph-outline descender clearance — see [004-underline-clearance.md](004-underline-clearance.md).

- Updated 2026-11-17: Implement reader code-block highlighting with Syntect
  — see [006-syntax-highlighting.md](006-syntax-highlighting.md).

- Updated 2026-11-17: Implement rounded code blocks, language captions, and native copying
  — see [007-code-block-presentation.md](007-code-block-presentation.md).

- Updated 2026-11-17: Implement configurable code-block styles and reader-owned controls
  — see [008-code-block-style-boundary.md](008-code-block-style-boundary.md).

- Updated 2026-11-17: Expose dictionary selection, retain Liang mixed-case matching,
  and remove unsupported subscript-shift customization; see
  [002.009](009-hyphenation-and-defaults.md).

- Updated 2026-11-17: Repeat enabled PDF code captions with reserved page space;
  see [002.010](010-pdf-code-continuations.md).

- Updated 2026-11-17: Replace legacy profile parsing/writing with strict TOML,
  without a compatibility path; see [002.011](011-standard-toml-profiles.md).

- Updated 2026-11-17: Add bounded, cached automatic hyphenation language selection
  and opt-in display punctuation policies; see
  [002.012](012-language-and-punctuation.md).

- Updated 2026-11-17: Retain reflow preparation and remove repeated break scans — see [013-reflow-preparation.md](013-reflow-preparation.md).
- Updated 2026-11-17: Reuse semantic and item preparation and skip absent decorations — see [014-reflow-metadata.md](014-reflow-metadata.md).
- Updated 2026-11-17: Defer snapshot-local offscreen fragment materialization — see [015-lazy-fragments.md](015-lazy-fragments.md).
- Updated 2026-11-17: Measure viewport paragraphs with indexed offscreen height estimates — see [016-viewport-layout.md](016-viewport-layout.md).
- Updated 2026-11-17: Reuse immutable source-range glyph paint values across reflows — see [017-glyph-paint-reuse.md](017-glyph-paint-reuse.md).
- Updated 2026-11-17: Keep surrounding text viewport-based in mixed documents and defer unadorned lines in linked paragraphs — see [018-mixed-viewport-coverage.md](018-mixed-viewport-coverage.md).
- Updated 2026-11-17: Seek directly into semantic spans and source intervals for selection geometry — see [019-selection-range-indexing.md](019-selection-range-indexing.md).
- Updated 2026-11-17: Paint warm glyph records without constructing fragment caret objects — see [020-paint-without-caret-materialization.md](020-paint-without-caret-materialization.md).
- Updated 2026-11-17: Note the external first-screen diagnostic command and its purpose — see [021-telari-open-report.md](021-telari-open-report.md).

- Updated 2026-11-17: Reduce cold preparation and reuse immutable geometry during viewport refinement — see [022-incremental-reflow.md](022-incremental-reflow.md).

- Updated 2026-11-17: Prepare bounded documents during idle time to cover rapid scrolling — see [023-fast-scroll-coverage.md](023-fast-scroll-coverage.md).

- Updated 2026-11-17: Compact prepared geometry, release reusable break items, and bound paint retention — see [024-compact-idle-preparation.md](024-compact-idle-preparation.md).

- Updated 2026-11-18: Deliver native highlighting spans with one parser pass — see [025-one-pass-syntax-spans.md](025-one-pass-syntax-spans.md).
- Updated 2026-11-18: Preserve clickable links through PDF pagination. See [026-pdf-links.md](026-pdf-links.md).
- Updated 2026-11-18: Expose diagram label selection and node links. See [027-diagram-interactions.md](027-diagram-interactions.md).
- Updated 2026-11-18: Paint a hollow square when font fallback is exhausted. See [028-missing-glyphs.md](028-missing-glyphs.md).
