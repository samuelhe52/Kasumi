# 002.025 — One-pass native syntax spans

## Context and plan (2026-11-18, before implementation)

Status: Implemented. The maintainer requested profiling and fixes for the remaining
highlighting regressions after the non-code parsing work. The existing Swift
adapter queries the native span count and then fills a buffer. Both calls run
Syntect and allocate a span vector; only immutable grammars are cached.

## Design

Add a synchronous borrowed-span visitor to the private C bridge. The native call
tokenizes once and invokes the visitor exactly once on success, including empty
results. The span pointer is read-only and valid only during the callback. Swift
validates and copies directly into its retained document tokens. Rust destroys
the temporary vector after the callback returns. No buffer ownership, source
cache, parser state, or callback lifetime crosses the call boundary.

Keep the count/fill ABI for compatibility and use it as a token-equivalence
reference in native tests. Preserve the pinned grammars, palette roles, limits,
plain fallbacks, independent block state, and UTF-16 coordinates.

| Alternative | Decision |
| --- | --- |
| Allocate the maximum possible Swift span buffer | Reject: a short code block needs little space, while the input limit permits a roughly 6 MiB speculative buffer. |
| Add a process-wide token cache | Reject: source retention, invalidation and a new memory allowance are unnecessary to remove repeated work within one request. |
| Return an owned native result handle | Reject for this synchronous consumer: requires release/error-path ownership rules that a borrowed visitor avoids. |
| Borrow spans during one callback | Choose: one native parse and one Swift token buffer, with explicit bounded lifetime and no persistent cache. |

## Validation planned

- Native tests compare visitor spans exactly with the existing ABI, assert a
  single parser pass, and cover invalid callbacks/inputs and empty fallbacks.
- Existing Swift syntax tests check language aliases, Unicode ranges, multiline
  state, independent blocks, fonts/text/layout, and raster colors.
- Build all existing native slices without booting a simulator.
- Compare frozen before/after Release binaries on mixed 50k/200k and an English
  control. Separate cold initialization, warm parsing, first bitmap and memory;
  use equivalent worker profiles and preserve raw measurements. Profiling
  overhead is excluded from latency comparisons.
- Reference observations change only if a covered behavior deliberately changes;
  no such rendering change is intended here.

## Outcome

`CodeSyntax.swift` now calls `kasumi_syntax_highlight_visit` and copies the
validated spans directly into the document's tokens. The legacy entry point
still performs the count/fill contract. Both entry points share input validation
and the same Syntect tokenization function.

On an Apple M1 Pro running macOS 27.2.1, 12 fresh Release workers per variant
and phase used matching resources for the two highlighting builds. Warm parse
medians fell from 8.23 to 7.00 ms for mixed 50k and from 32.57 to 27.23 ms for
mixed 200k. Historical renderer medians were 6.83 and 26.75 ms. English 50k
paired parse medians moved by less than 2%. Time Profiler attributed 2.45 s
before and 1.27 s after to highlighting across 1,000 mixed 50k parses per trace.

Cold parsing remained about 9–10 ms above the historical renderer. A separate
native probe with 20 fresh processes per mode measured 8.70 ms and a 6.43 MB
physical footprint increase for the first short Swift highlight. Initializing
the syntax set through an unknown-language lookup cost 0.89 ms, followed by
7.74 ms for the first Swift block. This points to the Swift grammar's lazy
initialization and regex setup as the main remaining cold cost. End-to-end cold
opening still lagged the historical renderer in both mixed samples.

Matched full-traversal memory medians after one second idle were 50.83 to
51.31 MB for mixed 50k and 142.75 to 142.69 MB for mixed 200k. The sampled
ranges overlap with four processes per variant. The historical renderer still
had a lower footprint. The probe and traversal measurements cover macOS.

`make test-syntax-native` passed four tests, including exact legacy span
comparisons and a single-pass assertion. `make test FILTER='CodeSyntaxTests|CodeBlockPresentationTests'`
passed 13 tests, including Unicode offsets, preserved layout and raster colors.
All three native slices and the Release benchmark compiled. Frozen reference
expectations needed no edits. Traces and worker results are local build output.
