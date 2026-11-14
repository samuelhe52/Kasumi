#ifndef KASUMI_C_HYPHENATION_H
#define KASUMI_C_HYPHENATION_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Hyphenates one word using unmodified hyphenation 0.8.4 Standard semantics.
 * Supported BCP 47 tags (ASCII case-insensitive): en-us, en-gb, de-1996, fr,
 * es, it, pt, nl, sv, da, nb, fi, pl, cs, ru. No language detection is performed.
 *
 * Returns the required count of byte offsets, unchanged from Standard::hyphenate.
 * The library intends these as offsets in the original word, including its
 * special realignment for capital dotted I. No extra case-map correction is
 * applied here; callers requiring their own source mapping should lowercase
 * and map offsets explicitly (Standard does not realign capital sharp S).
 * Case folding, byte realignment, and soft-hyphen precedence are supplied by
 * Standard::hyphenate. Before caching, dictionary minima are set to left 2;
 * right 3 for en-us/en-gb/pt/cs, right 2 otherwise. This is native wrapper policy
 * and changes upstream's French right minimum from 3 to 2. A soft-hyphen offset
 * identifies the start of U+00AD; no characters are removed or replaced.
 *
 * NULL output queries the count. A non-NULL output is written only when
 * capacity >= the required count; otherwise it remains unchanged. No ownership
 * crosses the interface. Dictionaries are embedded and loaded lazily once per
 * language into an immutable, thread-safe cache.
 *
 * Returns SIZE_MAX for invalid UTF-8, unsupported/empty language, NULL input
 * with nonzero length, length above PTRDIFF_MAX, dictionary load failure, or
 * internal panic. NULL word with zero length represents an empty word.
 *
 * The caller supplies readable input buffers and sufficient aligned writable
 * output storage. Inputs must remain unchanged and must not overlap output.
 */
size_t kasumi_hyphenate(const uint8_t *word, size_t word_length,
                       const uint8_t *language, size_t language_length,
                       size_t *output, size_t capacity);

#ifdef __cplusplus
}
#endif

#endif
