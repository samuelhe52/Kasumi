# 004.010 — iOS 18 app compatibility

## Context

The maintainer approved lowering the app to iOS 18 after lowering the library to iOS 15. The iOS 18 build identified iOS 27 document APIs and toolbar placement, plus iOS 26 scroll-edge and keyboard accessory effects.

## Approach

Retain the iOS 27 document scene and add an editable `ReferenceFileDocument` scene for iOS 18–26. Both use the same reader model for source bytes, live preview, and undo. Select the scene at the app entry point because SwiftUI's scene builder rejects an availability-based `if`/`else`. Keep the shared launch scene and file handoff.

Use the available toolbar placement, scroll edges, and keyboard material on each OS. Verify compilation at the lower deployment target and exercise opening, editing, autosave, and handoff on iOS 18 when the runtime is available.

## Implementation

- `KasumiMain` starts the existing SwiftUI app on iOS 27+ and the compatibility app on iOS 18–26. Both share `DocumentGroupLaunchScene` and the handoff delegate.
- `ModernReaderDocument` retains coordinated, URL-based reads and writes. `LegacyReaderDocument` reads a `FileWrapper`, uses the scene's file URL for relative images and reading position, and respects its editability flag. Each edit updates an immutable save snapshot behind a lock before notifying SwiftUI. The synchronous save callback can read that snapshot independently of the preview and UI.
- iOS 26+ keeps the soft edge and glass keyboard accessory. iOS 18 uses the system edge and a blurred accessory. The iOS 18 reader puts its title, Back button, and action menu in an inset bar. The same bar hosts undo, redo, the preview toggle, and Done when editing. The legacy document scene hides its system navigation bar at the reader root so it stays hidden when the app returns to the foreground.
- The legacy document creates its reader model with the initial file URL and starts the first parse when SwiftUI supplies the document. Later configuration changes update the existing model. The iOS 18 close action unregisters the reader because the system can retain it after dismissal. Programmatic opening waits for the browser to be attached and its transition to finish.

## Validation

- The first simulator build exposed a missing `UTType` import and an ambiguous trailing closure in the adapters. The adapters now use an explicit import and callback label.
- `make app-check` and `make app-check-sim` passed. All four app and extension bundles declare iOS 18.0.
- `make test FILTER=DocumentSourceTests` passed all three tests. A separate macOS probe built against the legacy adapter and checked read-only behavior, byte preservation, saving before preview refresh from a background task, and undo/redo.
- On the iPhone 16 simulator with iOS 18.0, the launcher opened and the system browser displayed its Create Document tile. The iOS 18 title card covered the background wordmark, so the older launcher now supplies the app name as the card title. The signed simulator build displayed it on a fresh launch.
- The initial Create Document attempt wrote `Untitled.md` and reached `ReaderScreen` without showing it. Samples showed repeated SwiftUI toolbar layout. A simpler SwiftUI toolbar still stalled. The inset bar let the reader appear and showed that the initial legacy parse had not started. Starting the parse from the supplied configuration resolved the loading screen.
- On the same iPhone 16 running iOS 18.0, the signed app opened and rendered existing Markdown from Browse and Recents. Paste Markdown and Open URL both saved byte-identical copies of the fixture and opened them after another reader had closed.
- A document opened through Open URL kept a single reader header when Kasumi returned to the foreground from the Home Screen and Files.
- Create Document opened `Untitled 2.md`. Editing, keyboard undo and redo, live preview, autosave while open, and reopening the edited file all passed. The Back button worked from the original reader and after reopening.
- Import into Kasumi opened byte-identical files while the app was already showing a reader and on a cold launch from Files. iPad layouts, relative-image rendering on iOS 18, and iOS 26 and 27 runtime behavior remain unverified.
