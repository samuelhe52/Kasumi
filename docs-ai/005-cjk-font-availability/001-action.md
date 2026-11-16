# 005 — CJK font availability on iOS: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-16 | Maintainer moved the font store ahead of Reader 2 and settled scope (Apple + open faces), placement (appearance sheet) and onboarding (offered, skippable, open faces as fallbacks). | discussion |
| 2026-11-16 | Library open substitutes, app font catalog, store, store screen and onboarding. | this change (uncommitted when written) |

## Outcome and current state (as of 2026-11-16)

- Library: `FontFamilyResolver.chain(for:role:)` and `openSubstitutes` map
  Songti SC/TC to Noto Serif SC/TC. `Typography.font` uses LXGW WenKai Lite
  (Regular, Medium for strong) for Kai emphasis when Apple's Kaiti is missing,
  and over the open Songti substitutes, with zero baseline trim.
- App catalog: six Apple packages (Songti SC, SimSong, Kaiti SC, STFangsong,
  STHeiti, Songti TC), all recommended. Three open packages: Noto Serif SC
  (23.7 MB), Noto Serif TC (16.2 MB), LXGW WenKai Lite (27.8 MB). They're pinned
  to Noto CJK tag `Serif2.003` and LXGW WenKai Lite `v1.530`, with byte counts
  and SHA-256 sums recorded on 2026-11-16.
- Store: open files live in `Application Support/Fonts` (excluded from backup)
  and are registered at launch. Apple packages requested once are re-requested
  at launch. Open packages can be removed by swiping; Apple packages can't.
- Onboarding: shown once from the launch scene or the reader, whichever
  appears first. Download Fonts or Not Now marks it offered. Its 宋 楷 仿 specimen
  shows each character in its face (or open fallback) once installed, and as a
  dimmed system-face placeholder before: Apple's faces can't be bundled.
- Choice: `RenderStyle.preferredOpenFamilies` reorders each Apple face and its
  open substitute; Kai emphasis follows "LXGW WenKai Lite". The store groups
  faces by role, shows In Use on the face the reader uses (Apple's, unless the
  user chose the open one or Apple's isn't installed), and Use on the other
  downloaded face. Supporting Apple faces say when they're unused because an
  open Simplified face is in use. The choice persists in `UserDefaults`.
- Debug builds accept `-KasumiFailAppleFonts YES` to exercise the fallbacks.

Key files: `Sources/KasumiMarkdown/FontFamilyResolver.swift`,
`Sources/KasumiMarkdown/CJKFontFace.swift`,
`Sources/KasumiMarkdown/Typography.swift`, `apps/iOS/Kasumi/FontCatalog.swift`,
`apps/iOS/Kasumi/FontStore.swift`, `apps/iOS/Kasumi/FontStoreView.swift`,
`apps/iOS/Kasumi/FontOnboarding.swift`, `apps/iOS/Kasumi/ReaderAppearance.swift`.

## Deviations from plan

- Fallback chains live in a resolver substitute map, not in presets.
- The 10 CJK library tests still skip on the simulator after the app downloaded
  the faces. Activation is per process, so the test runner doesn't see them, and
  having tests download would make them depend on the network.

## Validation

- `make test`: 172 tests passed (macOS), including the preferred-substitute
  chain order in `PublicAPITests`.
- `make test-ios` (iPhone 18 Pro, iOS 27.2): 172 passed, the same 10 skipped
  for missing Apple faces.
- `make app` / `make run-sim`: built without warnings.
- Simulator, iPhone 18 Pro, iOS 27.2, run by hand with `sim-use`:
  - Onboarding appeared on first launch. Download Fonts installed all six Apple
    packages; Kaiti SC took longest, roughly a minute.
  - After a relaunch, a document rendered body text in Songti, emphasis in
    Kaiti and bold in Songti Bold.
  - In the store, Noto Serif SC downloaded, passed verification and showed its
    sample.
  - With `-KasumiFailAppleFonts YES`, onboarding's Apple downloads failed and
    Noto Serif TC and LXGW WenKai Lite downloaded as fallbacks (Noto Serif SC was
    already present).
  - In the store, choosing Noto Serif SC and LXGW WenKai Lite swapped In Use
    and Use, and the open document re-rendered with Noto body text and WenKai
    emphasis.
  - Screenshots are local and not retained.

## Open questions

- Not verified: rendering with only the open faces (Songti is cached on the
  simulator, so the substitute chain was only checked by unit test); relaunching
  offline; iPad popover presentation of the store; a physical device.
- The simulator showed a system Apple Account verification prompt during the
  session; it's unclear whether the font download triggered it.
- The appearance sheet's toolbar buttons, Fonts included, don't appear in the
  accessibility outline `sim-use` reads.
