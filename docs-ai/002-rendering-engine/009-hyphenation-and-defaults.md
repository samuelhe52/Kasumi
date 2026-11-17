# 002.009 — Hyphenation selection and font-driven subscripts

## Plan and decisions (2026-11-17, before implementation)

Expose the existing dictionary selector through `hyphenation_language` in
typography profiles and `--hyphenation-language` in the CLI. Keep `auto` as the
default: US English patterns on ASCII words. Accept the fifteen existing
dictionary tags; document that `auto` is not language detection. No reader
controls are added in this slice.

The maintainer chose Liang's case-insensitive pattern matching without special
mixed-case or brand-name exclusions. Kasumi already implements that policy;
camelCase splitting is no longer classified as an outstanding defect. This is
not a claim of exact TeX frontend parity (TeX also has uppercase-word controls).

Remove the unused `subscript_shift` profile field. The maintainer chose to trust
math-font metrics and clearance rules rather than offer an override. Formula
layout stays unchanged; unsupported customization is not a renderer gap.

Validate public preset-to-layout language propagation, CLI parsing, supported
dictionary choices and case-insensitive behavior. Extend existing tests, retain
frozen measurements unchanged, and run focused package tests. Update the living
gap list, roadmap and development guide with the implementation.

## Outcome and validation

Implemented profile and CLI selection for `auto` and all fifteen dictionary tags.
The CLI flag overrides a selected preset/profile regardless of flag ordering.
Removed `subscript_shift` from the schema and generated templates; math layout
still uses its font constants. No reader UI or frozen reference files changed.

`make test FILTER='HyphenationTests|profileFactories|profileSchemaDefaults|profileNumericInput'`
passed all 8 tests on macOS. This includes public preset-to-layout propagation,
semantic-text invariance, CLI success/rejection, existing fifteen-dictionary
observations and schema/range checks. No simulator or device was launched.
