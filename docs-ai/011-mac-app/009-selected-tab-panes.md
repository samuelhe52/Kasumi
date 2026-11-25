# 011.009 — Animate panes only in the selected tab

## Context

With five native document tabs, a toolbar toggle animated five window splits. Each SwiftUI reader screen observed the same two pane preferences. In a Release probe with five copies of the root `AGENTS.md`, the four unselected readers installed 20–24 layouts per Outline toggle and 12–24 per Navigator toggle in aggregate. During native window-edge drags those same readers installed none. Changing the renderer's resize budget would not remove the unwanted work.

## Change

`MacNavigatorSplit` handles both toolbar and View menu toggles. The existing `mac.navigator-visible` and `mac.outline-visible` defaults stay shared. The initiating split animates unless Reduce Motion is enabled. A selected tab in another window adopts the preference without animation; an unselected tab leaves its split alone. When AppKit changes `tabGroup.selectedWindow`, the newly selected split reads the latest defaults without replaying transitions. `NSWindow.isVisible` is not a selection test: it was true for the background tabs in the probe.

The preference reads are direct. A retained `@AppStorage` outside SwiftUI returned a stale value when another tab wrote the same key. The reader's layout and window-drag policy are unchanged.

## Validation

`make app-mac CONFIGURATION=Release` and a native five-tab regression probe passed on Apple Silicon, macOS 27.2.1. The probe used five copies of the root `AGENTS.md` and counted installed reader layouts per window:

- Each of six toolbar or menu transitions installed 14–16 layouts in the selected tab and zero across its four siblings. The largest gap between selected reader layout callbacks was 18–50 ms per transition; these are not display frame timings.
- Switching to a tab with both panes out of date applied the current state without a slide. Switching back after changing both preferences in the second tab restored the new state, not the first tab's last state. Tab selection can change the window size as well as either pane, so one catch-up need not mean just one reader layout.
- Resizing the selected window and reversing an Outline slide twice produced no background installs. Detaching a stale tab into a separate window caught it up; toggling Navigator there updated both selected windows and none of the three remaining background tabs.

Not run on macOS 26. No change to frozen renderer measurements.
