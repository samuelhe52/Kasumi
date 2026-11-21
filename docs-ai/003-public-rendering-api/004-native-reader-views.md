# 003.004 — Native reader views

Status: Implemented. The maintainer approved implementation on 2026-11-21 after reviewing a local plan and a separate Opus review.

## Public boundary

Add the opt-in `KasumiMarkdownUI` SwiftPM product. `KasumiMarkdown` remains the headless renderer. Native `MarkdownReaderView` and its SwiftUI wrapper own a viewport, immutable snapshots, reflow, clipped painting, wide-table scrolling, and transient interaction state. Host apps own files, outline controls, persisted reading position, appearance choices, external URL opening, and export. Kasumi supplies its own code-block Copy control and preserves Preview suspension, font invalidation, and the current scroll behavior. ReflowLab uses the public AppKit view for its real window and its coverage probes, not a second scheduler.

Native Find uses UIKit on iOS 16+ and AppKit on macOS 13+. The SwiftUI binding mirrors native panel visibility; a toolbar button belongs to the host. Programmatic search, match navigation and highlights work independently of the panel, including on iOS 15. No second panel ships with the library. Native and programmatic Find do not compete for the same viewport. Selection uses renderer geometry and the iOS 15 responder edit menu when the modern menu is unavailable.

The view takes an opt-in remote image provider. Resolution yields dimensions and a bounded size-aware rasterizer; cached encoded data can use the library decoder. The view tracks unresolved occurrences near the viewport, scopes its display cache to the provider and revision, rejects stale completions, and preserves the reading anchor when geometry changes. Drawing never fetches or decodes. No provider, decline, and failure never trigger fallback networking. Local and embedded images keep their existing path. The provider is reader-only; headless export and explicit export preload retain their existing contract.

## Validation

Compile a separate consumer at the iOS 15 floor, including guarded Find. Exercise selection, copy, links, scrolling, and custom search on iOS 15 if a runtime is available; report compile-only coverage otherwise. On a newer iOS runtime exercise the app cutover, native Find, and its binding. Run ReflowLab window and coverage probes, focused renderer and image-policy checks, and exercise both native forms and the SwiftUI wrapper without raising the package deployment floors.

## Outcome (2026-11-22)

- `5468506055`: Added scoped remote image resolution, placeholders, size-aware drawing, and accessibility link geometry. Headless preload and export keep their existing paths.
- `d14a041d56`: Added [KasumiMarkdownUI](../../Sources/KasumiMarkdownUI), migrated Kasumi and [ReflowLab](../../tools/ReflowLab), and published [integration examples](../../docs/library.md#embedding-a-native-reader). The lab's public view is also the subject of its existing viewport coverage probes.

## Results

- macOS 27.2.1 arm64: 22 focused native reader, search, reflow, table, and image tests passed (one timing test skipped). Four headless export and image parity tests passed.
- iPhone 18 Pro simulator, iOS 27.2: the app built; two Find tests and four scoped-image tests passed. The app opened `ReaderInteractions`, found three matches for “needle,” advanced to the second match, and dismissed the native panel. Long press exposed Copy and Select All; the Copy action dismissed the menu. Source and Preview both opened, and the app restored the saved position on relaunch. An iOS 15 consumer built and linked with `minos 15.0`; no iOS 15 runtime was installed.
- ReflowLab smoke, ordinary and fast traversal, and ordered-window interaction checks completed. The ordinary 50k and 200k runs had no uncovered samples. The first fast run had zero at 50k and 673 of 688 at 200k, which was not fully measured before traversal. The settled viewport was covered in both cases. These probes measure coverage, not display FPS.
- An isolated repeat of the fast traversal recorded zero uncovered samples out of 177 at 50k and 697 at 200k. Both snapshots were ready before traversal; idle preparation plus first viewport install took 334 ms and 1,421 ms. A separate repeat with a 45-second command limit timed out; the successful repeat took 58 seconds in total.
- A separate macOS 13-targeted SwiftPM consumer ran the SwiftUI wrapper and confirmed live matching and the native Find binding round-trip. An initial Xcode CLI build of that macOS probe hit duplicate Rust archive symbols; the SwiftPM build linked and ran.

Initial verification also caught duplicate Swift source basenames in Xcode string extraction, an AppKit accessibility setter compile error, unavailable clock APIs in the iOS package test graph, and a floating-point geometry comparison in an image test. The final focused builds and tests passed after these fixes. A parallel macOS test run stalled in the system font service; the focused tests completed serially.

No iOS 15 or macOS 13 runtime check, physical-device test, or VoiceOver session was run.
