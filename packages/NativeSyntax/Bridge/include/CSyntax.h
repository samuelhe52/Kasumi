#ifndef KASUMI_C_SYNTAX_H
#define KASUMI_C_SYNTAX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    KASUMI_SYNTAX_KEYWORD = 1,
    KASUMI_SYNTAX_STRING = 2,
    KASUMI_SYNTAX_COMMENT = 3,
    KASUMI_SYNTAX_LITERAL = 4,
    KASUMI_SYNTAX_TYPE = 5
};

typedef struct {
    size_t location;
    size_t length;
    uint32_t role;
} KasumiSyntaxSpan;

/* Highlight one UTF-8 code block with pinned Syntect grammars. No detection.
 * Returns the required span count; ranges are sorted, disjoint UTF-16 offsets
 * in the unchanged source. Roles map to the constants above. Multiline parser
 * state belongs to this call; only immutable grammars are shared between calls.
 * Empty/plain/unknown languages return zero. Aliases are ASCII case-insensitive.
 *
 * NULL output queries the count. A non-NULL output is written only when
 * capacity >= the required count; otherwise it is unchanged. No ownership
 * crosses the interface. Calling again with identical inputs is deterministic.
 *
 * SIZE_MAX means invalid UTF-8/nulls, language >128 bytes, source >256 KiB,
 * any line >16 KiB, parsing failure, or a caught panic. Render plain on failure.
 * NULL input with zero length is an empty string. The caller supplies readable
 * inputs and aligned writable output disjoint from inputs, for the given sizes.
 */
size_t kasumi_syntax_highlight(const uint8_t *source, size_t source_length,
                              const uint8_t *language, size_t language_length,
                              KasumiSyntaxSpan *output, size_t capacity);

#ifdef __cplusplus
}
#endif
#endif
