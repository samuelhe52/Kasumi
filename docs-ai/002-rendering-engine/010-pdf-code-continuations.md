# 002.010 — Repeated PDF code captions

## Plan (2026-11-17, before implementation)

Repeat an enabled code caption on continuation pages of a long block. Reserve
its caption row and top padding during pagination, then paint the original
caption decoration above the continued code. Reuse the block's style and label;
do not insert decoration into semantic text or modify onscreen/image layout.

Page capacity must account for the repeated header before choosing a cut, and
oversized indivisible content must still scale to fit. Caption-free exports
retain existing pagination. Validate content preservation and caption occurrence
on every code-bearing PDF page, plus geometry around short pages and neighboring
blocks. Inspect headless PDF page renders without launching a simulator.

## Outcome and validation

Implemented per-page continuation-header reservation and separate clipped header/
body painting. Oversized header-plus-line content scales together on short pages.
Caption-free pagination and ordinary snapshot/image layout retain their behavior.

`make test FILTER='CodeBlockPresentationTests|nativePagination|paginationNever|pdfPagesRetain'`
passed all 9 tests on macOS, including 50/100/200 pt PDF page heights, exact-once
source lines, repeated captions, distinct adjacent languages and non-overlapping
caption/code geometry. Frozen pagination atom checks passed unchanged.

The first test build used the wrong PDFKit selection overload; corrected to
PDFDocument text search. Subsequent tests caught duplicate caption painting and
an oversized-header progress error; both were fixed before the final passing run.

`make render` generated a four-page, 150-line captioned Rust PDF with the One
Light theme and 10 pt code corners. Poppler page 2/page 4 renders and a close view
of page 4's caption were inspected: the repeated label is legible above continued
code, and the final block ends cleanly before the following paragraph. QA files
are local, not retained. No simulator/device or frozen fixture updates.
