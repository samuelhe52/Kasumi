# 003.003 — Missing-image backgrounds and theme palette fields

## Design

Use `document.image_placeholder_background` behind the existing fallback text
for unavailable images. Apply it as a text background so block and inline
images share the same paint path in reader layouts and exports. Preserve the
fallback label, alt text, link target, and layout geometry.

Remove the `chrome` map from the bundled catalog, JSON loader, and public
`DocumentTheme` API. The maintainer requested removal because the app has no
theme colors for its controls. Theme version 1 continues to use `document`
and `syntax` maps.

Verify the paint reaches an image export and that bundled palettes and custom
theme loading retain their existing document and syntax colors.

## Outcome and validation

The shared typography path applies the color to each fallback text run, and the
existing text background painter draws it. Theme decoding and resolution use
`document` and `syntax`. Legacy `chrome` keys follow the decoder's ordinary
handling of unknown JSON fields.

On macOS 27.2.1, the focused theme, image, reflow, and PDF-link tests passed
with the opt-in reflow timing test skipped. The image test samples placeholder
pixels for both block and inline images and checks semantic alt text. Headless
CLI exports also produced the configured colors in a light PNG and a dark PDF.
The unsigned generic iOS build passed. Runtime checks used macOS only. Frozen
reference measurements did not require updates.

Review reproduced placeholder paint behind adjacent Hebrew text in a
mixed-direction line. The Core Text fallback now draws background colors over
each visual span of the styled range. The extended PNG test failed before the
fix and passed afterward. All 13 focused image, paragraph drawing, highlight,
and PDF-link tests passed on macOS, and the unsigned generic iOS build passed.
