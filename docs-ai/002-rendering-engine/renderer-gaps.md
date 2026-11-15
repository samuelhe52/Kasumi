# Renderer gaps

Living list of known `KasumiMarkdown` limitations. Remove an item in the commit
that fixes it; add one when a limitation is found and not fixed.

- Text: right-to-left paragraphs fall back to Core Text (no bidi painting in
  the paragraph engine); `unicode-linebreak` differs from 59 of 7,654 Unicode 15
  test vectors; characters missing from every installed font have no defined
  fallback; hyphenation language is automatic only (US English for ASCII);
  hyphenation splits camelCase and brand names ("Kasum-iMarkdown", "ma-cOS").
- Fonts: the CJK faces the presets use aren't installed on iOS; see
  [005](../005-cjk-font-availability/000-plan.md).
- Profiles: punctuation strategy and subscript shift are stored but not
  applied. The profile file format is a nonstandard line format; moving to
  standard TOML is planned.
- Themes: no syntax highlighting, no custom theme files; chrome colors are kept
  but not fully applied. On iOS, the Classic theme's system colors resolve to
  UIKit's semantic colors, so it differs slightly from macOS.
- Math: limited LaTeX coverage beyond the tested cases.
- Diagrams: no rich HTML labels; syntax outside the tested corpus may be
  rejected; no links or selection inside diagrams.
- Export: pagination details, PDF links, footnote edge cases, HTML/SVG images.
- Drawing: tile drawing is serialized by a lock in `RenderedDocument`, because
  Core Text line objects are shared between tiles and Apple limits each to one
  thread at a time.
