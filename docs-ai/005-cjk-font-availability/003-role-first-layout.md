# 005.003 — Role-first font management

## Context

The maintainer rejected the layout delivered in 005.002. Animation repairs did
not fix the information hierarchy: the first screen still mixed all installed
and downloadable faces, repeated role headings and specimens, and exposed
management controls beside every selection.

## Change

The Fonts screen shows three compact navigation rows: Simplified Chinese,
Emphasis, and Traditional Chinese. Each shows its selected face and a glyph
preview. Supporting Apple fonts have a separate destination. Changing a role
costs one extra tap; all current choices fit in the overview.

The first navigation revision retained the rejected choice rows. The maintainer
identified those rows, not just the overview, as the primary problem. The final
choice screen uses two matching tappable cards:

- The same title, metadata, specimen, and trailing indicator alignment.
- One common preview phrase per role, rather than different font-name specimens.
- Equal padding and height at the same text size; a consistent gap between cards.
- A per-font usage description sits between source metadata and specimen;
  open alternatives describe the same reading role as their Apple counterpart.
- No Use text, per-row ellipsis, invisible reserved action columns, or section
  explanation footers. The whole card, including its padding, is tappable.
- Open-font removal and license access live in the toolbar menu. Remove Download
  acts immediately, without a confirmation. Apple fonts remain non-removable.
- Downloads use a plain `ProgressView` throughout, without an overlaid X or a
  switch to a determinate ring. Tapping the downloading card still cancels.
- License entries have an external-link icon and open the upstream license file
  pinned to the downloaded font release, rather than the generic OFL homepage.

`FontPackageRow` supplies the same whole-row interaction to supporting fonts and
onboarding. Persistent indicator/specimen layers preserve the opacity animation
fix from [005.002](002-font-management-transitions.md). The reader rendering
pipeline and download backend are unchanged in this follow-up.

Key file: `apps/iOS/Kasumi/FontStoreView.swift`.

## Validation

- `make run-sim` passed for the final implementation. Xcode printed its existing
  supported-platform destination diagnostic; compilation and installation
  completed. No package tests were run for this app-only layout change.
- iPhone 18 Pro, iOS 27.2:
  - Visually checked the exact Traditional Chinese screen identified by the
    maintainer. Before the usage-description refinement, both cards measured
    362 × 124 points, with a 12-point gap, before and after selection.
  - Selected Noto Serif TC by tapping the lower-left card padding, not the
    indicator; selected Songti TC again and restored the original preference.
    Both expose button and selected accessibility traits.
  - Checked that the overview updates after changing a font.
  - In the earlier confirmation-based iteration, opened the toolbar's named
    removal action and dismissed its confirmation without deleting the download.
  - Navigated to Supporting Fonts. No font screen retained a section footer.
  - Checked accessibility-large Dynamic Type visually, then restored the
    original text-size category.
- Captured 60-fps video and inspected intermediate frames: selection indicators
  and card borders interpolate without moving the cards or text. Screenshots
  and recordings are local artifacts, not version-controlled evidence.
- Not rechecked: the onboarding download phase, iPad, and physical-device
  performance.

## Follow-up verification — 2026-11-16

- Added usage text in the previously empty metadata-to-specimen gap, shortened
  Remove Download and removed its confirmation, and replaced the progress/X/ring
  sequence with a single native spinner, as requested by the maintainer.
- `make run-sim` passed after the UI changes and again after the license-link
  and debug-preview changes. The same Xcode destination diagnostic appeared.
- iPhone 18 Pro, iOS 27.2: visually checked all three supporting-font usage
  descriptions. Removed Noto Serif SC immediately from its menu, observed the
  retained card's download action, re-downloaded it, inspected the spinner, and
  verified the original selected open preference returned on completion.
- Verified the license menu's external-link icon and opened Noto's pinned
  license text in Safari. Also fetched both pinned upstream license files to
  confirm the catalog destinations.
- Debug launches explicitly passing `-onboarding.fonts-offered NO` now show the
  offer even when every recommended face is cached. Normal first-run and release
  eligibility are unchanged; the preview does not force Apple download failures.
- Opened onboarding with that launch-only reset and left the simulator on the
  offer for maintainer inspection. No screen recordings were made for this
  follow-up.
