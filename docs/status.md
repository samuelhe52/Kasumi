# Status

## Current state (2026-11-14)

Working:

- `KasumiMarkdown` builds for macOS and the iOS simulator. All 160 tests pass
  on macOS (`make test`). On the iOS simulator (`make test-ios`) 150 pass and
  10 that pin Apple CJK faces are skipped, because those faces aren't
  installed (see Fonts below).
- A deliberate public API; everything else is internal. `MarkdownDocument`
  parses Markdown, plain text or raw file data and exposes the outline.
  `RenderStyle` combines a `TypographyPreset` and a `DocumentTheme` chosen by
  the client. `RenderedDocument` is an immutable layout that can be built off
  the main thread; it draws by rect for tiling and handles hit testing,
  selection rects and text, search, links, outline and anchor rects, and
  reading anchors. `DocumentExport` returns PDF and PNG data.
  `FontAvailability` reports missing families.
- The Rust dependencies build as XCFrameworks for macOS, iOS and the iOS
  simulator (arm64 only).
- The iOS app is a `DocumentGroup` reader built on the public API only. The
  launch screen has Paste Markdown (a text sheet; pasting there through the
  edit menu needs no pasteboard permission) and Open URL, and on first launch it copies
  `Welcome.md` into the app's Documents folder. The reading view keeps the
  paper color edge to edge, lays out on a background task, draws with
  `CATiledLayer`, follows system light/dark through theme pairs, hides its
  bars on scroll, and has an appearance sheet (preset, size, theme) and an
  outline (sheet on iPhone, sidebar on iPad). Reading position is saved per
  file. Memory stays at 55–70 MB on the Welcome document through scrolling,
  rotation, dark mode and style changes.

Not yet:

- No ready-made UIKit/AppKit views or SwiftUI wrappers; the reader's views
  will be extracted into the library once they settle.
- Tile drawing is serialized by a lock, because Core Text line objects are
  shared between tiles and Apple limits each to one thread at a time.
- The XCFrameworks are generated, not committed, so depending on this
  repository by URL doesn't work yet.
- License notices aren't bundled into the app.

## Next

Known issues in the reader (milestone 1):

- In the iOS 27.2 simulator the document browser and the Files app show the
  Kasumi folder as empty although it holds `Welcome.md`, also on a freshly
  created simulator and with every file type accepted. Document Manager logs
  `failed to get a cached domain for FILocalAppContainerNode<Kasumi>` before
  enumerating, which points to the simulator's File Provider, not app
  configuration. Needs a check on a physical device.
- Not verified: opening a file in place (blocked by the issue above), Open URL, iPad layout, reading
  position restore, link and footnote taps.
- Launch in the simulator stalls a few seconds while UIKit loads accessibility
  bundles; this comes from simulator automation, not the app.

Reader milestones, in order:

1. Document app shell (`DocumentGroup`: Files/iCloud, in place, recents,
   windows, iPad drag and drop; paste and URLs open as untitled documents) and
   a reading view with edge-to-edge paper, system light/dark, outline (sheet on
   iPhone, sidebar on iPad) and per-file reading position.
2. Selection through UIKit text interaction, find bar with match navigation,
   links.
3. Export: PDF, long PNG, print, share sheet.
4. Source editor with live preview; side by side on iPad.
5. Settings: font store and download screen, default preset, theme and size.

## Fonts

iOS doesn't ship the CJK faces the presets use (Songti SC, SimSong, Kaiti,
Fangsong, Heiti), so CJK text falls back to PingFang or the system font. These
faces are licensed by Apple and can't be redistributed; on iOS they are only
available through Core Text's on-demand system font download.

Plan:

- The library stays stateless and never downloads. It resolves each font role
  through a fallback chain; today the chain is fixed per role (Han: the
  preset's family, Songti SC, PingFang SC, Songti TC), and should move into
  presets (e.g. Songti SC, then an open serif CJK face, then the system font).
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
