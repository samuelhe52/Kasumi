# 011.002 — Native Mac app icon

## Context

An ad-hoc-signed test build initially had no Mac app icon. Resizing
and bundling the iOS image supplied an icon resource but did not fix the Dock
placeholder on the test Mac. Replacing the Downloads bundle could preserve the
same top-level modification time while changing its contents. macOS returned
byte-identical old artwork at that path even after the embedded icon changed.

## Change

`KasumiMac` uses `AppIcon` in Debug and Release. Its Mac-only
[`AppIcon.icon`](../../apps/macOS/Kasumi/AppIcon.icon) uses one image layer with
light, dark, and tinted variants and no custom glass, specular, or shadow
effects. macOS still applies its own corner mask, edge lighting, and clear or
tinted treatment. The iOS catalog and bundle ID are unchanged.

[`design/icon/make_icon.py`](../../design/icon/make_icon.py) generates the SVG
sources. Its regeneration recipe renders each PNG once and copies the same bytes
into both targets. Icon Composer rendered symlinked layers as empty, so the Mac
package contains real files. Identical copies share Git blobs.

When replacing a local test copy in place, quit Kasumi, replace the whole bundle,
and refresh the new bundle directory's modification time (`touch -m` on the
installed `.app`) before re-registering and relaunching it. Resetting reader
preferences is separate from invalidating the stale icon.

## Validation

The generator reproduced all three iOS references with zero differing pixels.
The Mac inputs were byte-for-byte identical to those references. Rendering the
original SVG directly in Icon Composer was not equivalent: the default artwork
differed by as much as 41 channel levels.

Icon Composer rendered all six appearances for the macOS 26 and 27 design
generations. Maximum 8-bit sRGB channel difference in the central 768×768
pixels of the 1024×1024 render:

| macOS design | Default | Dark |
| --- | ---: | ---: |
| 26 | 3 | 2 |
| 27 | 1 | 2 |

The crop excludes the corner mask and edge lighting. The iOS tinted PNG is
input to system tinting, not a pixel reference for the tinted preview.

`make app-mac CONFIGURATION=Release` compiled the package with Xcode 27.2 and
a macOS 26 deployment target. The bundle contained `Assets.car` and
`AppIcon.icns`, declared `AppIcon`, and passed `codesign --verify --deep --strict`.
During the earlier cache diagnosis on macOS 27.2.1, updating the installed
bundle timestamp and registration refreshed the artwork returned by
`NSWorkspace` and the running app. The physical Dock tile was not rechecked.
