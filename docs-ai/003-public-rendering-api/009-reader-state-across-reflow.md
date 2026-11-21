# 003.009 — Reader state across reflow and edits

- AppKit reports reading position from the layout it is displaying, even if a newer style layout is pending. Publication requires that the visible layout belong to the current document, not the current geometry generation. This extends the [teardown contract](008-reading-position-lifetime.md) to scrolling during reflow.
- UIKit and AppKit reuse the scoped remote image cache across edits at the same non-nil URL. A new layout can use cached intrinsic sizes and matching rasters immediately. A different document scope, provider, or image revision retires that cache. Hosts can bump the revision to reload an unchanged image URL.

Focused AppKit tests verified saving a scrolled position before a new style layout installed and preserving resolved image geometry on the first same-file layout. The UIKit reader suite on the iPhone 18 Pro simulator (iOS 27.2) passed the same image scenario. Both native tests verified that bumping the image revision requested the URL again.
