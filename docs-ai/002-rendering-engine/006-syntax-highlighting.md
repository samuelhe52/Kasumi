# 002.006 — Reader code-block syntax highlighting

## Context and plan (2026-11-17)

Status: Implemented. The plan below was written before implementation. The maintainer selected
Syntect after comparing maturity and community adoption and requested an isolated
worktree, rendering-only validation, and no simulator use.

Reader code blocks retain their language but currently use a single foreground
color. The bundled document themes already provide keyword, string, comment,
literal, and type colors.

## Intended change

- Add pinned Syntect behind the existing Rust static-library/XCFramework pipeline.
  Package: `packages/NativeSyntax`; Swift adapter:
  `Sources/KasumiMarkdown/CodeSyntax.swift`.
- Return theme-independent UTF-16 token ranges through a caller-owned C interface;
  preserve source bytes and apply only foreground colors to Kasumi's attributed
  code text before layout. Keep Kasumi's fonts and paragraph metadata.
- Highlight only reader code blocks with an explicit supported language. Normalize
  common fence aliases; leave unlabeled, unknown, and explicitly plain-text blocks
  unchanged. Preserve Mermaid rendering and its plain fallback.
- Use bundled grammars and existing syntax palette roles. Keep parsing state across
  lines for multiline strings/comments, but never across separate blocks. Reuse
  immutable grammar data; retain tokens only on the parsed document, with no
  process-wide source cache.
- Include dependency licenses/notices and retain reproducible lockfiles.

## Decisions

| Choice | Reason and alternatives |
| --- | --- |
| Syntect | Explicit maintainer choice; mature code-display adoption and Kasumi already builds Rust dependencies. |
| Reader only | Editor highlighting and incremental editor parsing are outside the requested scope; Tree-sitter's editor capabilities do not justify its grammar integration here. |
| Token categories, existing theme colors | Theme changes must recolor without changing fonts, text, selection, or export semantics. Importing a separate Syntect theme would bypass Kasumi's document palette. |
| Bat-curated two-face grammars, pure-Rust regex backend | Syntect defaults omit Swift and TypeScript; the pinned extra grammar bundle covers them. Pure Rust avoids an additional native regex library in cross-platform builds. Some Oniguruma-only variants remain unsupported. |
| Explicit language, plain fallback | Avoid unreliable guessing for short snippets and keep unknown languages readable. |

## Acceptance criteria

Focused native/Swift checks cover multiple languages, aliases and fallback,
multiline state, Unicode/UTF-16 offsets, independent blocks, theme colors reaching
the raster, and preserved text/layout semantics. Build macOS/iOS device/iOS
simulator library slices without running a simulator. Render an authored code
fixture in light and dark themes and inspect the images. Run relevant existing
parser, theme, paragraph, and export regressions. State actual validation and any
limits below after implementation. Frozen reference expectations change only if a
covered behavior deliberately changes.

## Outcome (2026-11-17)

Implemented on `feat/syntect-highlighting`.

- `packages/NativeSyntax` pins Syntect 5.3.0 and two-face 0.5.2+bat-0.26.1, uses
  the pure-Rust fancy-regex backend, and preserves registry and grammar notices.
  `scripts/build-native` and `Package.swift` include the new XCFramework/C target.
- `Sources/KasumiMarkdown/CodeSyntax.swift` converts the caller-owned C spans to
  validated UTF-16 tokens and applies the five existing syntax foreground roles.
  `Document.swift` tokenizes labeled code blocks during parsing; `DocumentLayout.swift`
  paints them before paragraph layout. Parsed documents retain their tokens across
  reflow, theme changes, and exports. No global source/token cache was added.
- Explicit languages use their first whitespace-delimited word, case-insensitive,
  with common aliases. Inline code, indented/unlabeled code, raw HTML, unknown/plain
  languages, and Mermaid fallback remain unhighlighted. Panel chrome and Copy
  controls are implemented in [002.007](007-code-block-presentation.md).
- Source above 256 KiB UTF-8, a line above 16 KiB excluding LF, language info above
  128 bytes, parsing errors, or caught panics fall back to plain text. These input
  guards are not a hard execution-time timeout.
- `fixtures/SyntaxHighlighting.md` covers Swift, aliased Python, TypeScript, Rust,
  multiline strings/comments, Unicode, wrapping, and plain fallback. No frozen
  reference expectations were changed.

## Validation

Performed on macOS 27.2.1, arm64; no simulator or device was launched or driven.

- `make native` (through `make test`) built macOS arm64, iOS device arm64, and
  iOS simulator arm64 static libraries and assembled the syntax XCFramework.
- `make test-syntax-native`: two host Rust tests passed, covering common bundled
  languages and C ABI invalid inputs, required-count queries, insufficient-capacity
  preservation, and successful writes.
- `make test FILTER=CodeSyntaxTests`: six Swift tests passed, including nine
  language cases and two raster cases. Covers aliases/fallback/size guards,
  multiline parser state and block isolation, CRLF/CJK/emoji/combining-mark UTF-16
  offsets, every bundled theme's colors, unchanged text/search/font/line ranges,
  and actual One Light/One Dark pixel colors.
- A focused `make test FILTER=...` selection of the new suite, named tests from
  `DocumentTests.swift`, `ThemeTests.swift`, `ProfileRenderingTests.swift`,
  `ParagraphTests.swift`, and `ExportTests.swift`, plus `PublicAPITests` and
  `ExportFileTests`, passed all 47 tests with no skips. After correcting raster
  test theme IDs, the affected `CodeSyntaxTests` suite passed again.
- `make render INPUT=fixtures/SyntaxHighlighting.md OUTPUT=<local output>`:
  rendered PNGs at 800 px with `--theme one-light` / `--theme one-dark`, plus
  a 360 px One Dark PNG, and a two-page One Light PDF. Inspected all three PNGs
  and both PDF pages rendered headlessly with PDFKit. Highlight colors survive
  wrapping; unlabeled/unknown blocks remain plain. Five PDF text-extraction
  checks passed, including `struct Greeting`, `let message: String`, and
  `interface Reader`. These images, PDF, and logs are local and not retained.
- `make syntax-notices` extracted the pinned grammar licenses; registry license
  texts and checksums for 33 dependencies were preserved. `git diff --check` passed.

## Corrections during validation

The initial native grammar inventory failed because Syntect defaults omit Swift;
this prompted the pinned bat-curated bundle. Initial Swift checks caught an overly
broad `storage.type` selector that colored Rust `let` as a type; type matching now
uses specific type scopes and declaration keywords retain keyword paint. An alias
check initially used a stale macOS slice while native sources were still changing;
all slices were rebuilt together before the passing checks.

The first CLI renders used nonexistent `atom-one-*` theme IDs. Corrected them to
`one-*` and made the raster test assert that the requested theme ID actually
resolved, preventing a Classic fallback from making this check pass incorrectly.
All intended renders and affected tests subsequently passed.

## Validation limits

No iOS Swift/app build or device/simulator runtime verification was performed.
Native iOS slices compiled, but runtime measurements and arbitrary-language
highlighting quality are not established. The fancy-regex grammar bundle excludes
some Oniguruma-only variants; unsupported languages remain plain. App-wide license
notice bundling is tracked on the roadmap.
