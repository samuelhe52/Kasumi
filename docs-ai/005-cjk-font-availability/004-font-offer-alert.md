# 005.004 — Missing-font alert

## Context

On a fresh simulator the onboarding specimen could not preview Apple's fonts
before download. The maintainer rejected decorative placeholders and the
separate onboarding sheet, and chose a simple missing-font alert that opens
font management.

## Change

`apps/iOS/Kasumi/FontOnboarding.swift` offers font management once when a
recommended Apple package is missing. Download Fonts opens `FontStoreView`;
Not Now dismisses the alert. Opening management does not start downloads.
Users choose and download individual packages there. The former bulk download,
automatic open-font fallback download, and onboarding specimen are removed.
The renderer still uses an installed open fallback when appropriate.

The launch-only debug override `-onboarding.fonts-offered NO` can preview the
alert even when the fonts are present. Without it, the offer depends on actual
Apple-font availability.

## Validation

- `make run-sim` built the alert-based implementation on iPhone 18 Pro, iOS 27.2.
- On the clean onboarding simulator, an ordinary launch with missing Apple faces
  showed the alert. Download Fonts opened the existing Fonts sheet with three
  System fallback roles; no Apple-font requests or open-font files were created.
- A previous attempt to exercise the abandoned progress screen generated open
  fallback downloads and Apple-request preferences under the test app. Those
  test-created files and preferences were removed before validating this alert.
- Onboarding was reset again for the maintainer to inspect; no download was
  started. No recordings were made.
