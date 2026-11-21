# 003.006 — Reader scheduling and host lifecycle

## Context

A second integration review found that AppKit still serialized image requests, UIKit could reclaim focus from a host field after Find, and distinct URL-less documents were treated as successive revisions of one file. AppKit also resolved every outline entry through a paragraph scan on each install, and a ReflowLab open error left the old reader suspended.

## Decisions

- Share the viewport image scheduler between AppKit and UIKit. Local and embedded images have their own slot, remote images use four slots, and each lane starts visible requests before overscan. Retire work on viewport or session replacement; a geometry update restarts layout with the scoped resource cache intact.
- Restore UIKit reader focus after Find only when no other responder took it. Keep the semantic reading position during reflow of the same document or an edit at the same non-nil URL. A new URL-less document starts at the top unless the host supplies a reading anchor.
- Read section tops from the snapshot's existing anchor position index. Reporting the current section does not need semantic-anchor relocation or glyph bounds.
- In ReflowLab, keep the old reader and source URL active until a replacement is parsed successfully. Report open errors without disabling the displayed document.

## Verification

- Focused macOS tests covered embedded image completion while a remote provider was suspended, independent raster lanes, and active section reporting after jumping to heading 778 in a 1,000-heading document.
- On an iPhone 18 Pro simulator (iOS 27.2), `MarkdownReaderUIKitTests` passed, including host focus after Find dismissal, restoring Command-F when no other view took focus, and replacement with and without a shared URL. A nil-target responder action did not detect the focused host field in this test; the implementation checks the key window's view hierarchy instead.
- ReflowLab's interaction check showed native Find still worked after a failed open. Its smoke check verified the image queue still tracked the current viewport after idle layout.
