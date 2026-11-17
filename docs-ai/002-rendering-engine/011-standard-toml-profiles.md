# 002.011 — Standard TOML typography profiles

## Plan and decisions (2026-11-17, before implementation)

Replace the permissive line parser with a pinned Swift TOML parser. The maintainer
explicitly declined legacy compatibility. Profile values live only in `[profile]`,
factory snapshots in `[anchor]`, and the name in `[meta]`. Quoted/dotted keys,
literal/multiline strings, arrays and numeric syntax follow TOML. Duplicate keys
and malformed syntax fail instead of being silently recovered.

Retain schema normalization (numeric bounds, known choices, sparse inheritance).
Unknown keys/tables are not interpreted as typography. Imported source remains
unchanged until an edit; edits serialize canonical TOML, retaining unknown data
but not source formatting/comments. This replaces the legacy targeted line writer
rather than maintaining a second grammar alongside the standard parser.

Pin `dduan/TOMLDecoder` 0.4.5: a Swift-native, MIT-licensed parser compatible with
the package's deployment targets, without adding another native bridge. Strict
parsing must validate unknown values too, not only accessed typography keys.

Update authored fixtures/tests to the new contract; frozen renderer measurements
must stay unchanged. Validate spec syntax, rejection/atomicity, schema types,
unknown data retention and profile-library operations. This is library/CLI work;
the reader continues to use bundled JSON presets.

## Outcome and validation

Implemented strict parsing with exact-version SwiftPM pin and transactional
canonical writing. All TOML leaf types, including dates/times, nested tables and
mixed arrays, survive edits in unknown extension data. Sparse profile values
retain existing normalization and inheritance. Removed legacy-grammar tests and
converted `fixtures/NativeProfile.toml` to standard TOML; no frozen reference
measurements changed.

`make test FILTER='profile|HyphenationTests|PublicAPITests'` passed 46 tests on
macOS. They cover standard quoting/multiline/dotted/numeric syntax, malformed and
duplicate input (including unknown values), table isolation, schema validation,
all-field round trips, unknown extension data, failed-mutation atomicity,
public API raster/selection checks and dictionary propagation. An initial test
compared TOMLTable source-backed identities across reparsing; corrected it to
assert the retained semantic extension values.

`make render INPUT=fixtures/Profiles.md OUTPUT=<local PNG>` with
`360 --profile fixtures/NativeProfile.toml --hyphenation-language fr` succeeded.
The QA PNG is local, not retained. `make build` passed with the pinned parser.

`make app-check` passed for an unsigned generic iOS device, resolving the same
0.4.5 pin in the app lockfile. Xcode emitted the existing AppIntents metadata
warning; no simulator/device was launched. `git diff --check` passed.
