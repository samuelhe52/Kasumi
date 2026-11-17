# 002.028 — Missing-glyph fallback

## Context

Core Text provides fallback faces. Its final missing-character display has
platform-dependent advances and appearance.

## Design

Use a single hollow square for a grapheme with missing glyphs after Core Text
fallback. Make the substitution before paragraph and diagram layout so that
measurement and painting agree. Preserve original paragraph text in selection
and Find and verify that valid fallback characters still render.

## Outcome

Text keeps its selected face and normal system fallback when they yield
drawable glyphs. A grapheme that yields the system LastResort face or
a missing glyph for a visible scalar uses U+25A1 WHITE SQUARE. The check
skips ASCII-only material and scans selected font coverage before requesting
full shaping. The placeholder inherits the text style and contributes its
own advance to line breaking. Joiners and variation selectors do not trigger
replacement on their own.

Reader Copy and Find use the original grapheme, including in diagram labels.
The PDF paints and extracts the square. There is no additional reader alert.
The existing math-font diagnostics still govern missing glyphs inside native
TeX. Tests cover adjacent missing supplementary-plane characters, code,
diagram labels, normal Han and emoji fallback, and PDF output.

On the iPhone 18 Pro simulator running iOS 27.2, the reader displayed
hollow squares for U+10FFFF and U+0378, with adjacent Han text and emoji
using their normal glyphs.
