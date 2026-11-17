# 003.002 — Custom JSON theme files

## Plan (2026-11-17, before implementation)

Add stateless public theme-pair loading from JSON data or a file URL, plus
`KasumiRender --theme-file FILE.json`. The reader continues to use bundled theme
pairs; no import/settings UI is added.

Use a versioned JSON object with `schema_version: 1`, nonempty `id` and `name`,
and required `light`/`dark` objects. Each palette has optional `document`,
`chrome` and `syntax` color maps. Reuse the bundled color grammar (hex strings,
explicit sRGB/genericRGB RGBA and semantic system colors) and range validation.
Unknown color keys remain extensible; missing document colors inherit Classic
for that appearance, as with programmatic themes. Files are limited to 4 MiB.

The CLI selects light by default and dark with `--dark`. Reject simultaneous
`--theme` and `--theme-file` rather than hide one selection behind the other.
Keep built-in themes immutable and loading free of global state.

Validate errors, appearance selection, sparse inheritance, syntax colors and
actual CLI image/PDF output. Compile the app without launching a simulator.

## Outcome and validation

Implemented `DocumentThemePair.init(json:)` and `init(contentsOf:)`, shared
bundled/file color decoding and identical Classic document-color inheritance
for public styles and CLI file selection. Added `fixtures/CustomTheme.json`
and README usage. The built-in catalog and reader controls remain unchanged.

On macOS, `make test FILTER='theme|builtinThemePairs|PublicAPITests|CodeSyntaxTests'`
passed all 25 tests. New coverage checks envelope/color/size rejection, native
color forms, inherited colors, syntax paint, catalog independence, actual CLI
PNG pixels for light/dark (both flag orders), and conflicting selector errors.
Initial test compilation exposed a raw-string delimiter collision with hex colors
and a wrong NSColor-to-CGColor call; both test errors were corrected before the
passing run.

`make app-check` passed for an unsigned generic iOS device; the existing
no-AppIntents-dependency metadata warning remains. No simulator/device launched.
`make test FILTER='CodeBlockPresentationTests|pagination|nativePagination|pdfPagesRetain|MathProfile'`
passed all 13 integration regressions with the final theme code.

`make render` produced 600 px light/dark PNGs of `fixtures/SyntaxHighlighting.md`
and a dark custom-theme PDF of a 150-line Rust block. Both complete PNGs and the
PDF's second-page Poppler render were inspected: custom paper/heading/syntax
colors are present, and continuation captions remain legible above code. These
QA outputs are local, not retained. `git diff --check` passed; no frozen reference
expectations changed.
