# 004.005 — Opening files handed to a running app

## Context

When Kasumi was already running, sharing a Markdown or text file to it from
another app brought Kasumi forward on the launch scene without opening the file.
Separately, the "Import into Kasumi" action ([004.004](004-import-action.md))
never opened its file on a cold launch; see the last row of the findings.
A cold launch with the same file opened it. A minimal `DocumentGroup` app with
no launch scene and no Kasumi code failed the same way on the iPhone 18 Pro
simulator, iOS 27.2. Its scene received the URL in `scene(_:openURLContexts:)`,
but SwiftUI never read or showed the document. So this is a SwiftUI
`DocumentGroup` failure on this runtime, not something specific to Kasumi's
setup.

iOS offers no public way to open a document in a `DocumentGroup` from code:
`openDocument` is unavailable on iOS, and a new scene session can't be given URL
contexts. The maintainer chose to keep every reader inside `DocumentGroup` and
accept relying on how SwiftUI builds its view-controller tree, provided the
cost stays low. If that tree changes, the feature breaks, but it wouldn't work
without the workaround either, and the file is still saved where the browser
shows it.

## Change

- `KasumiAppDelegate`, installed with `@UIApplicationDelegateAdaptor`, gives each
  window scene a `HandoffSceneDelegate`. SwiftUI forwards
  `scene(_:openURLContexts:)` and `sceneDidBecomeActive` to it, and still
  handles cold opens of files itself.
- Cold share-sheet copies (added 2026-11-18): the delegate also reads
  `scene(_:willConnectTo:options:)` and queues the connection's file copies
  (`openInPlace == false`) like a warm share. SwiftUI still opens the
  `Documents/Inbox/` copy first; once the scene is active, the copy is saved
  into `Imported` and `show` replaces that reader. Incoming copies are removed
  only after `show` returns, so SwiftUI's reader isn't left on a deleted file.
- The delegate also drains the "Import into Kasumi" inbox on every activation
  and opens the newest file. This replaces `LaunchStore.importSharedFiles()`
  and the launch scene's `scenePhase` hook.
- A share arrives while the scene is still inactive. File URLs are held until
  the scene becomes active. Share-sheet copies (`openInPlace == false`) move out
  of `Documents/Inbox/` into `Documents/Imported/`, with the same naming rules as
  the "Import into Kasumi" action. Files opened in place aren't copied. When
  several files arrive together, all are kept and the last one opens.
- `DocumentBrowser.show(_:in:)` opens a file in a given window. It closes that
  window's reader if one is showing, waits for the browser to be ready, then
  calls the browser delegate's pick method, as 004.002 already did.
  `ReaderScreen` registers its `dismiss` per window scene and reports
  `onDisappear`, which the close waits for.
- Paste Markdown, Open URL, the "Import into Kasumi" action, and the debug
  `-KasumiOpen` flag now all open through `show`. So they also close an open
  reader and wait for a ready browser.

## Findings that shaped it

| Observation | Consequence |
| --- | --- |
| `onOpenURL` in the launch scene's overlay never fires; SwiftUI logs "Cannot use Scene methods for URL, NSUserActivity, and other External Events without using SwiftUI Lifecycle". | The URL is taken from a scene delegate, the hook SwiftUI documents for UIKit scene callbacks. |
| While a document is shown, the browser is replaced in the tree by a placeholder container, so a pick has nothing to go to. | Close the reader first. The browser is usable once the reader's `onDisappear` fires; no polling. |
| Picking while the previous reader's close is still animating opens the new document, and the finishing close then removes it. | Wait for `onDisappear`, not for the browser to reappear in the tree. |
| At launch, a pick made while the browser is still being presented (`isBeingPresented`) or before the scene is active opens the document. When the presentation finishes, the document is removed and the window is left empty and black. | `show` waits until the scene is active and the browser isn't being presented, checking every 100 ms for up to 15 s. Before this change, `-KasumiOpen` on a fresh launch failed this way at `27b0aec`. |
| On the maintainer's iPhone, a cold "Import into Kasumi" from Bear showed SwiftUI's plain browser: system-font title, no Paste or Open URL, no background, and no document. It did the same at `27b0aec`. A file log showed the launch carried `kasumi://import` in its connection options. With any launch URL, SwiftUI roots the window in `DocumentViewController` rather than the `DocumentGroupsIntroRootViewHostingController` that hosts `DocumentGroupLaunchScene`, so Kasumi's launch overlay, which ran the import, never existed. Reproduced with `devicectl device process launch --payload-url kasumi://import`. | The import runs from the scene delegate, which exists in both layouts. A first guess, that SwiftUI lost a cold-launch file to the race above, was wrong; handling for it was written, never exercised, and removed. |

## Decisions

| Choice | Reason and alternative |
| --- | --- |
| Keep readers in `DocumentGroup` and drive its browser | Maintainer decision. A standalone reader for handed-over files would have needed no SwiftUI internals, but brings back the second presentation that 004.002 removed. Replacing `DocumentGroup` with a custom browser was too large for this one bug. |
| Scene delegate, not swizzling | Swizzling SwiftUI's own scene delegate also sees the callback, but replaces private behavior. The delegate class is supported API, and the cold open still works with it installed. |
| Readiness from public API only | A first version waited for UIKit's private `_UIWaitingForRemoteView…` placeholder to leave the browser. That missed a case where the placeholder was already gone but the browser was still being presented. `isBeingPresented` and the scene's activation state covered every case tried, so the private class name was dropped. |
| Wait for our own reader's `onDisappear` | It's an event in Kasumi's code. An earlier Codex prototype polled for the reader to close and for a new reader to appear. |
| Move share-sheet copies into `Imported` | Matches the "Import into Kasumi" action, so these documents get the Delete button and don't pile up in `Inbox`. |
| Accept the plain browser after a cold Import | SwiftUI picks the layout from the launch URL, and there's no public way to hide that URL from it or to rebuild the launch scene afterward. A cold file share opened by SwiftUI itself lands in the same layout once its reader closes. The launch scene returns on the next launch without a URL. |
| SwiftUI-Introspect not used | It has no document-browser target. Its `.viewController` lookup returns an ancestor `UIViewController`, the same tree walk done here, so it would add a dependency without removing any code. |

## Validation

iPhone 18 Pro simulator, iOS 27.2, `make run-sim`, driven with `sim-use`
(2026-11-16). Files were shared from a separate throwaway sender app through the
system share sheet, because Files didn't list folder contents on this simulator.
The sender and the probe apps aren't part of the repository.

- Warm share, launch scene showing (app running at least 15 s): the file moved
  to `Documents/Imported/` and opened in the reader with Delete.
- Warm share with a reader open: that reader closed and the new file opened.
  Passed three times across builds.
- Share 1 s after launch: opened, twice with the final code.
- Cold share: SwiftUI opened the file itself, in place from `Documents/Inbox/`.
  After the launch-time check (2026-11-18), the maintainer reported that a cold
  share moves into `Imported` and opens there.
- "Import into Kasumi" action while a reader was open: the imported file
  replaced the reader. Before this change that path would have waited for a
  browser that isn't present while a reader shows; that old behavior was
  inferred from the code, not run.
- `-KasumiOpen` on a fresh launch: opened three times. At `27b0aec` it left a
  black window twice out of two runs.
- Earlier, in a standalone probe app, the scene delegate received warm URLs, and
  cold opens still worked with it installed.

iPhone 16 Pro, `make run-device` (2026-11-16), "Import into Kasumi" from Bear's
Markdown export, reported by the maintainer: a cold launch opened the document,
and closing it returned to the plain browser; a warm launch opened it too.

Not verified: Paste Markdown (the simulator clipboard follows the Mac's, and
`simctl pbcopy` didn't change it, so the paste stopped before saving); Files
"open in place" handoffs, warm or cold; iPad, including several windows; a
warm share-sheet copy on a physical device.

## Open questions

- How long `isBeingPresented` stays true on a cold launch wasn't measured; the
  wait gives up after 15 s and logs.
- Whether the pick works for a file opened in place from outside Kasumi's
  container (for example iCloud Drive) is untested.

## Refs

- `apps/iOS/Kasumi/DocumentHandoff.swift` (new)
- `apps/iOS/Kasumi/LaunchActions.swift`
- `apps/iOS/Kasumi/ReaderScreen.swift`
- `apps/iOS/Kasumi/KasumiApp.swift`
