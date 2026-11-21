# 003.007 — Reader commands, restoration, and image priority

The third integration review found three gaps in [003.006](006-reader-host-lifecycle.md): Kasumi's Command-F depended on first tapping the reader, the SwiftUI bridge ignored an explicit restore anchor when replacing a document at the same URL (including no URL), and queued image priority was stale when a scroll changed visibility but not the overscan membership.

- Kasumi's toolbar Find button owns Command-F without focusing the document during layout. A shortcut on the old overflow-menu item did not fire with the menu closed on iOS 27.2.
- The SwiftUI bridge consumes `initialAnchor` when the document identity or URL changes, not on updates to an already-installed document. A replacement with no explicit anchor still follows the native reader's position policy.
- Keep the latest viewport separate from overscan membership. Prioritize a queued image at dispatch time using the latest viewport; leave running requests and both concurrency bounds alone.

On an iPhone 18 Pro simulator (iOS 27.2), Command-F opened native Find immediately after the document opened, without a tap in the reader. `MarkdownReaderUIKitTests` verified that a mounted SwiftUI reader applied the replacement document's explicit anchor. The focused macOS scheduler test filled four remote slots and confirmed that the newly visible image got the next slot after a ten-point scroll with unchanged overscan membership.
