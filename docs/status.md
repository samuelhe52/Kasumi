# Status

## Current state (2026-11-14)

Working:

- `KasumiMarkdown` builds for macOS; all 149 tests pass.
- The Rust dependencies build as XCFrameworks for macOS, iOS and the iOS
  simulator (arm64 only).
- The iOS app shell builds, installs and launches on the iPhone 18 Pro
  simulator and shows a placeholder screen. It has its icon.

Not yet:

- The library doesn't compile for iOS: 21 files import AppKit, so the app
  references the package but doesn't link it.
- The public API is the internal one (`NSColor`/`NSFont` in public
  declarations). No designed headless, view or export API exists.
- The XCFrameworks are generated, not committed, so depending on this
  repository by URL doesn't work yet.
- License notices aren't bundled into the app.

## Next

1. Port the core off AppKit and run the tests on the iOS simulator.
2. Design the public API: headless layout, drawing, hit testing and selection;
   PDF/PNG export; UIKit/AppKit views with SwiftUI wrappers; public themes and
   presets.
3. Build the reader described in [goal.md](goal.md).

## Renderer gaps

- Text: right-to-left paragraphs fall back to Core Text (no bidi painting in
  the paragraph engine); `unicode-linebreak` differs from 59 of 7,654 Unicode 15
  test vectors; characters missing from every installed font have no defined
  fallback; hyphenation language is automatic only (US English for ASCII).
- Profiles: punctuation strategy and subscript shift are stored but not
  applied. The profile file format is a nonstandard line format; moving to
  standard TOML is planned.
- Themes: no syntax highlighting, no custom theme files; chrome colors are kept
  but not fully applied.
- Math: limited LaTeX coverage beyond the tested cases.
- Diagrams: no rich HTML labels; syntax outside the tested corpus may be
  rejected; no links or selection inside diagrams.
- Export: pagination details, PDF links, footnote edge cases, HTML/SVG images.
