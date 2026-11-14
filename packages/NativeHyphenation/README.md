# Native hyphenation

The static library `kasumi_hyphenation` wraps unmodified registry dependency
`hyphenation = 0.8.4`, with optional embedding, dictionary rebuilding, and Unicode
normalization features disabled. It embeds only the 15 selected upstream
Standard dictionaries. The application imports the header as `CHyphenation`.
Cargo.lock pins the complete dependency graph; `dictionaries/manifest.json`
records the exact upstream dictionary byte hashes.

Code and pattern data carry separate licenses. Full notices are in `Notices/`;
`Notices/SourcePatterns/` preserves the selected unmodified pattern and exception inputs,
their original master sources, applicable licenses, and source provenance.
In particular, Czech data is GPL version 2 or later, and Dutch, Swedish, and
Russian data use LPPL terms. This does not assert a license for the whole app.

The C API accepts one UTF-8 word and an explicit supported BCP 47 tag. It does
not detect a language. A null output queries the required count; an undersized
output buffer remains unchanged. Results preserve Standard's case-insensitive
hyphenation, byte-offset realignment, dictionary exceptions, and
soft-hyphen precedence. Results are byte offsets, rather than Unicode scalar or
UTF-16 positions, returned unchanged from Standard. Its special case-map
realignment handles capital dotted I; it does not correct every case mapping
that changes UTF-8 length. For example, direct `STRAẞENBAHN` gives `[4, 8]`,
retaining the upstream behavior despite capital sharp S shrinking when folded.
Callers that lowercase before this interface must maintain their own mapping
back to the source. See `Bridge/include/CHyphenation.h` for the pointer and error
contracts.

Each dictionary is validated against its expected language while deserializing
from embedded bytes, then cached immutably with a per-language `OnceLock`.
Before caching, the bridge applies these minima: left
2 for every language; right 3 for `en-us`, `en-gb`, `pt`, and `cs`; right 2 for
the others. This changes upstream's French right minimum from 3 to 2. The
algorithm and dictionary bytes remain unmodified.
No filesystem reads participate in application runtime.

Run the C ABI check from the repository root on macOS:

```sh
cargo build --locked --release --manifest-path packages/NativeHyphenation/Cargo.toml --target-dir .build/hyphenation-check
cc packages/NativeHyphenation/tests/bridge.c -Ipackages/NativeHyphenation/Bridge/include .build/hyphenation-check/release/libkasumi_hyphenation.a -pthread -o .build/hyphenation-check/bridge-check
.build/hyphenation-check/bridge-check
```

This verifies concurrent first loads of all 15 dictionaries, original-byte
offsets across multibyte UTF-8, soft-hyphen precedence, case handling, buffer
boundaries, invalid-input nonmutation, and count queries. Language selection
and word boundaries are the caller's responsibility.
