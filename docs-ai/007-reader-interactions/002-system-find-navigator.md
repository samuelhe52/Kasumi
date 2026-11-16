# 007.002 — System find navigator

## Context

The maintainer rejected the custom top find bar in `f247bfd`: search should float
above the keyboard. This follow-up replaces the presentation and session adapter
within Reader 2; native selection and link handling remain in the same entry.
Design written before implementation on 2026-11-16; implemented and checked on the same date.

## Design

- Use UIKit's `UIFindInteraction` with a read-only `UIFindSession` for the custom
  tiled reader. The system owns the find field, keyboard attachment, count,
  previous/next controls, dismissal, and keyboard shortcuts.
- Remove `ReaderFindBar`, its SwiftUI focus/keyboard handlers, and the measured
  top inset. Keep a presentation request from Reader Actions into the UIKit view.
- Bridge session results to the existing semantic UTF-16 positions and page
  highlights. Recompute results on reflow without keeping old-layout positions.
- Honor the native match options rather than exposing unsupported menu choices.
  Preserve wrapping navigation and keep the active match unobscured.

## Alternatives and decisions

- SwiftUI's `findNavigator(isPresented:)` requires a `TextEditor`; the reader
  paints a custom layout. UIKit explicitly supports custom searchable views.
- iOS 26's toolbar search presentation and `safeAreaBar` can position custom
  search UI, but would leave Kasumi responsible for a parallel find interface.
  Prefer the system find navigator for document text search.
- `UIKeyboardLayoutGuide` is available if result scrolling needs to account for
  keyboard occlusion; avoid keyboard-height notification calculations.

References: [UIFindInteraction](https://developer.apple.com/documentation/uikit/uifindinteraction),
[UIFindSession](https://developer.apple.com/documentation/uikit/uifindsession),
[SwiftUI findNavigator](https://developer.apple.com/documentation/swiftui/view/findnavigator(ispresented:)).
`UIFindInteraction` and the iOS SwiftUI find modifier date to iOS 16; their native
presentation adopts the current OS design. They are not newly introduced iOS 27 APIs.

## Validation plan

Build with `make app`, then use the already booted iPhone through `sim-use` to
inspect the actual software keyboard and find panel together. Check first/last
results, next/previous wrapping, native search options, clear/no results,
dismiss/reopen, keyboard shortcuts, rotation/reflow, and selection after ending
find. Record any remaining device/iPad coverage limits. Do not boot another
simulator without permission.

## Implementation and backing correction

`apps/iOS/Kasumi/ReaderFind.swift` now supplies a read-only `UIFindSession`.
`ReadingSurface.swift` installs `UIFindInteraction` and sends result decorations
to the existing rendered page. The custom SwiftUI field, count/navigation row,
focus handlers, and top-bar height tracking were removed. The system controls
own matching options, shortcuts, and keyboard attachment.

The maintainer's software-keyboard screenshot exposed a second issue: SwiftUI
shrunk the reader to 475 pt while the find controls occupied y=513–560 and the
keyboard began at y=590. The blank paper between the page and keyboard looked
like an opaque find background. `ReaderScreen.swift` now ignores both container
and keyboard safe areas, letting the document continue behind the glass.
A layout guide constrained to `UIKeyboardLayoutGuide.topAnchor` supplies the
bottom scrolling/indicator inset, after subtracting automatic safe-area insets.
This lets the final result scroll clear of the panel and keyboard without
clipping the page to that boundary.

UIKit requests the initial highlight after `performSearch`; the adapter now
leaves its result index unset until that request, avoiding a jump to result 2.
Ending a session restores the reader's first-responder chain after UIKit has
resigned the field, so Command-F can reopen Find. Snapshot replacement reruns
search and discards the old snapshot's ranges.

## Validation

- `make app`: passed with the iOS 27.2 SDK, including the final responder repair.
  No library code changed in this follow-up, and no package suite was rerun.
- iPhone 18 Pro simulator, iOS 27.2, driven with `sim-use` 0.16.0. The maintainer
  enabled the software keyboard after a host-menu investigation. It was visible
  during the final checks (`keyboard-state` returned `soft`).
- Verified page content behind the floating controls with the keyboard visible;
  the reader retained its full 874 pt height. Verified the last of three results
  could move above the controls and keyboard instead of remaining hidden.
- New searches started at `1 of 3`; previous wrapped to `3 of 3`. Command-G and
  Shift-Command-G changed the active result in the expected directions.
- Native Whole Words: `needle` returned 3 results, `need` returned 0, and turning
  the option off restored 3. Native Match Case: uppercase `NEEDLE` returned 3
  with matching disabled and 0 with it enabled; disabling restored 3.
- Clear removed results. Close dismissed the panel and keyboard; Command-F
  reopened the query with `1 of 3`. Native selection handles and Copy/Select All
  appeared after ending Find, and Command-F also reopened Find from selection.
- Rotation to landscape recomputed the layout and retained `1 of 3`. The
  software keyboard was partly offscreen after this simulator rotation, so this
  is not evidence of correct landscape keyboard presentation. Restored portrait
  and repeated the final checks there.
- One automation overlap caused `make run-sim` to restart a process launched
  before the build finished; `sim-use` reported a process-change alert. The two
  launch outputs identified the intentional restart. Reset the baseline and used
  sequential build/install/launch commands thereafter; no application crash was
  observed in the subsequent checks.
- `git diff --check`: passed. Screenshots are local, not repository evidence.
  No frozen reference measurements changed. Included in this follow-up commit.

## Remaining coverage

No iPad or physical-device run was performed, and Reduce Motion was not retested.
Landscape software-keyboard presentation needs a separate check; its clipping was
observed, but the cause was not established. Portrait keyboard attachment,
background underlap, and result visibility were visually checked in the final build.
