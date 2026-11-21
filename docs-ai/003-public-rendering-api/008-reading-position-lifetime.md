# 003.008 — Reading position lifetime

The [host lifecycle decision](006-reader-host-lifecycle.md) requires same-file edits to preserve the semantic position. AppKit now captures the visible position before discarding the old snapshot when a replacement has the same non-nil URL. An explicit restore anchor still takes precedence.

SwiftUI teardown finishes the native view before draining the bridge's position report. It delivers the latest queued position on the next main-actor turn without retaining the coordinator or interrupting SwiftUI's update. Pending Find reports are discarded on teardown.

The focused AppKit test passed for both a same-file edit and an explicit override. The UIKit reader suite on an iPhone 18 Pro simulator (iOS 27.2) passed, including a nonanimated jump followed by teardown in the same main-actor turn and release of the coordinator before the callback.
