# 011.011 — Let Stage Manager finish before switching tabs

## Context

Opening a file while Kasumi was in the Stage Manager strip made the window jump
into its final position. macOS activates the app and starts sliding its selected
tab's window about 40 ms before delivering the open event. Each native tab is its
own `NSWindow`, so selecting another one replaces the moving window with one that
is already at its final frame.

A minimal AppKit probe reproduced this without Kasumi code. In three runs per case
on macOS 27.2.1, these were the widths just before the switch to a 1,000-point
window:

| Probe | New file | Existing inactive tab |
| --- | --- | --- |
| Plain windows as native tabs | 490 | 131–210 |
| `NSDocument` with native tabs | 571–610 | 152–283 |
| Same, shown 100 ms later | 852 | 646–712 |
| Same, after the width settles | 1,001 | 999 |
| One window with replaced content | No switch | No switch |

## Change

WindowServer reports the changing bounds during the slide, while AppKit reports
the final frame. `MacDocumentWindowController` waits while their widths differ by
more than two points before replacing the key window with another native tab,
checking about once per frame with a 750 ms limit. Missing geometry lets
presentation proceed. One task runs this wait after the layout wait in
[010](010-first-reader-frame.md).

## Alternatives

- Selecting the tab earlier, setting `selectedWindow`, or disabling the window's
  animation still jumped. A fixed delay only moves the jump later, or delays
  opens that need no wait.
- A single window with custom tabs has no jump, but replaces native tabs.
- A search of Apple's documentation, SDK headers and other native-tab apps found no
  public notification for the end of the slide and no way to carry it across a tab
  switch. An earlier raw Apple event handler was not tried.

## Validation

The Release build was sampled in Stage Manager over three runs each for a new
file, an existing inactive tab and an empty file, opened with `open -a` on macOS
27.2.1. The outgoing window was 999–1,001 points wide at every switch. Nothing was
screen-captured. Finder double-click, multiple displays and macOS 26 were not
checked.
