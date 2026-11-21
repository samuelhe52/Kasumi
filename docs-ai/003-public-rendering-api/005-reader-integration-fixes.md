# 003.005 — Native reader integration fixes

The post-implementation review of [003.004](004-native-reader-views.md) identified six regressions in real hosts: a slow remote image blocked the viewport queue, layout stole UIKit focus, AppKit swallowed relative links with fragments, suspension lost pending native Find, SwiftUI retained outdated code-block controls, and Kasumi exposed identical VoiceOver Copy actions.

- Give UIKit local decode its own lane and cap remote work. Start visible requests before overscan requests; cancel work that leaves the viewport or belongs to an obsolete generation.
- UIKit takes focus for a tap, selection, or explicit Find, not for layout or activation. AppKit routes only a fragment-only or confirmed same-file fragment internally. A queued Find request survives temporary suspension; explicit dismissal cancels it.
- An unkeyed SwiftUI control factory refreshes installed controls on update. Hosts can use a stable configuration ID to avoid replacing live controls on unrelated updates. Kasumi uses that form to preserve Copy feedback and gives each action a distinct name.

Regression coverage exercises an already-focused UIKit host field during first layout, a responsive remote request while the first provider is suspended, local rasterization while all remote raster slots are occupied, SwiftUI control replacement and removal with and without an ID, AppKit link forwarding, and pending AppKit Find with and without explicit dismissal.
