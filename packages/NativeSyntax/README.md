# Native reader syntax highlighting

Pinned Syntect 5.3.0 with two-face 0.5.2+bat-0.26.1's bat-curated grammar
bundle. The `syntect-fancy`/`regex-fancy` backend is pure Rust, so cross-compiling
needs no extra C regex library. Only grammars are loaded; Kasumi supplies colors.
The pure-Rust bundle excludes some grammar variants supported only by Oniguruma.

`make native` builds macOS arm64, iOS arm64, and iOS simulator arm64 static-library
XCFramework slices. No simulator is booted or used. `make test-syntax-native`
tests the host-side bridge; `make test FILTER=CodeSyntaxTests` checks integration
with the parser, themes, typography, text map, and raster drawing.

`Bridge/include/CSyntax.h` defines the C bridge. Swift uses the synchronous
visitor to copy sorted, non-overlapping UTF-16 spans with five palette roles
after one parser pass. Rust lends its span buffer for the duration of the
callback. The count/fill entry point remains available. Parser state
persists within a block. Immutable grammar data is initialized on first use,
and copied Swift tokens live with the parsed document.

Fence languages are case-insensitive; the first whitespace-delimited word is
used, with common aliases such as `py`, `js`, `ts`, `sh`, `c++`, `c#`, and `yml`.
There is no language detection. Unsupported/unlabeled/plain languages are plain.
Blocks above 256 KiB UTF-8, lines above 16 KiB excluding LF, language info above
128 bytes, invalid UTF-8, and parse failures also render plain. These are input
size guards, not a hard wall-clock timeout.

## Provenance and notices

- `Cargo.lock`: exact registry versions/checksums.
- `Notices/dependencies.json`: registry dependency license declarations and sources,
  including build-time dependencies.
- `Notices/CODE-LICENSES.txt`: corresponding crate license files.
- `Notices/GRAMMAR-LICENSES.md`: grammar licenses extracted from the pinned
  two-face crate. Regenerate with `make syntax-notices`; no network or mutable
  external grammar checkout is needed.

Registry sources are unmodified; the C ABI, palette mapping, aliases, and size
limits are Kasumi policy. No two-face theme assets are loaded by this bridge.
