# 008.002 — Export options

## Context and change

The maintainer requested more paper and margin presets, a runtime font-size
override, and code language captions proportional to exported text. The reader
offers A3, A4, A5, US Letter, US Legal and US Tabloid, and four uniform margin
presets. A4 and one-inch margins remain the defaults. PDF and image font sizes
start at the preset's print size and the current reading size respectively;
changes apply only to this export sheet. Captions scale with the chosen body size.

`PDFExportOptions.fontSize` is optional: nil retains the preset print size and
invalid explicit values fail geometry validation. `TypographyPreset.printFontSize`
lets clients present that default. The previous action record describes the
original options at the time it was written.

## Validation

`make test FILTER='Export|Pagination|PublicAPITests|CodeBlockPresentation'`
passed 28 tests on macOS, including PDF text-size and caption scaling checks.
`make app` built for iPhone 18 Pro / iOS 27.2. The app launched on that simulator,
but the export sheet and resulting output were not visually checked in this run.
No frozen reference measurements changed. Physical devices and printing were not checked.
