# 003.004 — Native reader views

Status: Implemented 2026-11-22. The maintainer approved the plan on 2026-11-21. Three integration reviews on 2026-11-22 found regressions in real hosts; their fixes are folded into the sections below.

## Boundary

`KasumiMarkdownUI` is a separate, opt-in SwiftPM product with the same iOS 15 and arm64 macOS 13 floors. `KasumiMarkdown` stays headless. The reader view owns scrolling, layout and reflow, painting, wide tables, selection, Find, and other transient state. The host owns files, toolbar and outline controls, saving the reading position, appearance, opening external links, and export.

Kasumi and [ReflowLab](../../tools/ReflowLab) both use the public view. ReflowLab's viewport coverage probes now measure the public AppKit reader instead of a separate harness.

## Find

- The system panel is `UIFindInteraction` on iOS 16+ and `NSTextFinder` on macOS. The SwiftUI binding mirrors its visibility. The Find button belongs to the host.
- Programmatic Find (query, next or previous match, clear, and a result callback) works on every supported version, including iOS 15. The library ships no panel of its own.
- Only one search is active at a time. Setting a query closes the system panel, and opening the panel clears the query.
- A Find request made while a document is opening or the reader is inactive waits for the first laid-out screen. Explicit dismissal cancels it.
- On iOS 15, selection uses the responder edit menu.

## Focus

- The UIKit reader becomes first responder only for a tap, a selection, or an explicit Find request, never for layout or activation. Otherwise it would take focus from a host text field during the first layout.
- When Find closes, the reader takes focus back only if no other view in the key window has it. In the UIKit test, a nil-targeted responder action did not detect a focused host field, so the reader walks the window's view hierarchy instead.
- Kasumi's Command-F shortcut is on the toolbar Find button. On iOS 27.2, the same shortcut on an overflow-menu item did not fire while the menu was closed.

## Links

The reader follows fragment-only links and fragment links that resolve to the current file, with the same path, host, port, credentials, and query. Every other link goes to the host, including relative links such as `chapter.md#intro`.

## Reading position

- Replacing the document at the same non-nil URL keeps the reading position. AppKit captures the visible anchor before it discards the old layout. A new document without a URL starts at the top. An explicit anchor always wins.
- The SwiftUI wrapper applies `initialAnchor` only when the document identity or URL changes, not on ordinary updates.
- Position reports come from the layout on screen, even while a newer style layout is pending, as long as that layout belongs to the current document.
- The current section comes from the snapshot's anchor position index, with no glyph or semantic lookup. Before this, AppKit scanned paragraphs for every outline entry on each install.
- When SwiftUI tears the reader down, it finishes the native view first and delivers the last queued position on the next main-actor turn, without retaining the coordinator. Pending Find reports are dropped.

## Remote images

- Remote images load only through a provider the host supplies. Without one, the reader makes no network requests. A provider returns intrinsic dimensions and a rasterizer that takes a bounded pixel size. `MarkdownRemoteImages.http` uses the library's downloader and decoder.
- A declined or failed image shows the placeholder. The reader never falls back to another loader. Drawing never fetches or decodes. Local and embedded images keep their existing path.
- The provider affects only the reader views. Headless export and its explicit preload are unchanged.
- The image cache is scoped to the file URL, the provider's identity, and a host-supplied revision. Edits at the same URL reuse known sizes and rasters, so the first layout after an edit already has the final geometry. Any other change retires the cache. Remote sizes are fixed for a reflow generation, so text preparation never mixes geometry from before and after an image resolves.
- Both platforms share one scheduler: one slot for local and embedded decoding and four for remote work. Visible images start before overscan. Priority is computed when a slot opens, from the latest viewport, so an image that scrolls into view moves ahead even if the overscan set is unchanged. Work stops when its image leaves the overscan area or the session is replaced.

## Reasons

These were not recorded when the plan was approved. The following are inferred from the code and from the earlier contracts in this topic:

- No network access by default: a downloaded document shouldn't make requests the host didn't opt into.
- A reader-only provider: it leaves the headless export contract of [003](000-plan.md) unchanged.
- No library Find panel for iOS 15: the host owns the toolbar, and the programmatic API lets it build a search field in its own style.

## Validation

- **macOS 27.2.1 (arm64):** the focused reader, search, reflow, table, and image tests passed, with the opt-in reflow timing test skipped. Headless export and image parity tests passed. Later tests covered:
  - embedded images completing while a remote provider was suspended
  - local decoding while all four remote slots were busy
  - a newly visible image taking the next slot after a ten-point scroll
  - the active section after jumping to heading 778 of 1,000
  - fragment-link routing
  - pending Find with and without dismissal
  - same-file reload, with and without an explicit anchor
  - position reports during a pending reflow
  - image-cache reuse, and a reload after bumping the revision
- **iPhone 18 Pro simulator (iOS 27.2):** the app opened `ReaderInteractions` and native Find found three matches for "needle", advanced to the second, and closed. Long press offered Copy and Select All. Source and Preview both opened, and the saved position was restored on relaunch. Command-F opened Find right after the document opened, without a tap in the reader. `MarkdownReaderUIKitTests` covered:
  - host field focus during the first layout and after Find
  - replacement with and without a shared URL
  - an explicit anchor on a mounted SwiftUI reader
  - code control replacement with and without an ID
  - teardown right after a non-animated jump
  - image-cache reuse
- **ReflowLab:** the smoke check, ordinary and fast traversal, and the interaction check passed. The interaction check confirmed native Find still worked after a failed open. The ordinary 50k and 200k runs had no uncovered samples. In the first fast run, the 200k document was still being measured when traversal began, and 673 of its 688 samples were uncovered; the settled viewport was covered. A repeat with both snapshots ready first had no uncovered samples (177 at 50k, 697 at 200k). Idle preparation plus the first viewport install took 334 ms and 1,421 ms. These probes measure coverage, not display frame rate.
- **Deployment floors:** a separate iOS consumer built and linked with `minos 15.0`, including the guarded Find. A separate macOS 13 SwiftPM consumer ran the SwiftUI wrapper, with live matching and the Find binding round trip.

## Not verified

There was no iOS 15 or macOS 13 runtime, no physical device, and no VoiceOver session. An Xcode command-line build of the macOS 13 consumer failed with duplicate Rust archive symbols, but the SwiftPM build of the same consumer linked and ran. This was not investigated further.
