# Native Unicode line breaks

`kasumi-linebreak` builds a static library around the unmodified registry crate
`unicode-linebreak = 0.1.5`. The application imports the C header as `CLineBreak`.
Cargo.lock pins the complete dependency graph. License texts and provenance are
in `Notices/`.

`kasumi_linebreaks` first counts opportunities. A null output queries the required
count; a sufficiently large caller buffer receives the records on a second
iteration. An undersized buffer receives no writes. Records preserve UTF-8 byte
offsets and distinguish mandatory breaks. See the header for the pointer contract
and error sentinel.

Build and run the standalone C ABI check on macOS from the repository root:

```sh
cargo build --locked --release --manifest-path packages/NativeLineBreak/Cargo.toml --target-dir .build/linebreak-check
cc packages/NativeLineBreak/tests/bridge.c -Ipackages/NativeLineBreak/Bridge/include .build/linebreak-check/release/libkasumi_linebreak.a -o .build/linebreak-check/bridge-check
.build/linebreak-check/bridge-check
```

The C check exercises byte offsets across multibyte UTF-8 and CRLF, mandatory
flags, count queries, buffer boundaries, and invalid-input nonmutation. It does
not establish parity of the application's surrounding paragraph item builder.

Validation against the official Unicode 15.0 `LineBreakTest.txt` compared all
7,654 cases through the compiled C ABI: 7,595 had identical break offsets and
59 differed. This pins the published crate's behavior; it is not a claim of
complete default UAX #14 conformance. The test data SHA-256 was
`371bde4052aa593b108684ae292d8ea2dbb93c19990e0cdf416fa7239557aac3`.
Test data: <https://www.unicode.org/Public/15.0.0/ucd/auxiliary/LineBreakTest.txt>.
