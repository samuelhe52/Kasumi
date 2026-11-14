# Status

## Current state (2026-11-14)

Working:

- `KasumiMarkdown` builds for macOS and the iOS simulator. All 160 tests pass
  on macOS (`make test`). On the iOS simulator (`make test-ios`) 150 pass and
  10 that pin Apple CJK faces are skipped, because those faces aren't
  installed (see Fonts below).
- The Rust dependencies build as XCFrameworks for macOS, iOS and the iOS
  simulator (arm64 only).
- The iOS app links the library and renders a bundled sample document (text,
  math, a Mermaid diagram, a table) on the iPhone 18 Pro simulator.

Not yet:

- The public API is the internal one, now typed with `PlatformColor` and
  `PlatformFont` aliases (`NSColor`/`UIColor`, `NSFont`/`UIFont`). No designed
  headless, view or export API exists.
- The XCFrameworks are generated, not committed, so depending on this
  repository by URL doesn't work yet.
- License notices aren't bundled into the app.

## Next

1. Design the public API: headless layout, drawing, hit testing and selection;
   PDF/PNG export; UIKit/AppKit views with SwiftUI wrappers; public themes and
   presets; fonts by name or descriptor with per-preset fallback chains.
2. Build the reader described in [goal.md](goal.md), including the font
   download screen in Settings.

## Fonts

iOS doesn't ship the CJK faces the presets use (Songti SC, SimSong, Kaiti,
Fangsong, Heiti), so CJK text falls back to PingFang or the system font. These
faces are licensed by Apple and can't be redistributed; on iOS they are only
available through Core Text's on-demand system font download.

Plan:

- The library stays stateless and never downloads. It resolves fonts by name
  or descriptor, and presets carry a fallback chain (e.g. Songti SC, then an
  open serif CJK face, then the system font).
- The app owns a font store with a download screen in Settings. It requests
  Apple's faces through the system download and fetches openly licensed fonts
  (e.g. Source Han, Noto CJK, LXGW WenKai) into its container, registering
  them for the process with `CTFontManagerRegisterFontURLs`.
- Onboarding should later offer the same downloads; onboarding itself is out
  of scope for the first version.

## Renderer gaps

- Text: right-to-left paragraphs fall back to Core Text (no bidi painting in
  the paragraph engine); `unicode-linebreak` differs from 59 of 7,654 Unicode 15
  test vectors; characters missing from every installed font have no defined
  fallback; hyphenation language is automatic only (US English for ASCII);
  hyphenation splits camelCase and brand names ("Kasum-iMarkdown", "ma-cOS").
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
