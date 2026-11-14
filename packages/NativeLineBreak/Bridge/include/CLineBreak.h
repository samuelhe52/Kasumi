#ifndef KASUMI_C_LINE_BREAK_H
#define KASUMI_C_LINE_BREAK_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KasumiLineBreak {
    size_t offset;
    uint8_t mandatory;
} KasumiLineBreak;

/*
 * Returns the required record count. Offsets are byte offsets in the original
 * UTF-8 input, immediately after each break opportunity. Mandatory is 0 or 1.
 *
 * Pass NULL for out to query the count. When out is non-NULL, records are
 * written only if capacity >= the required count; otherwise out is unchanged.
 * No allocation or ownership crosses this interface.
 *
 * Returns SIZE_MAX for invalid UTF-8, NULL utf8 with nonzero length, an input
 * length above PTRDIFF_MAX, or an internal panic. NULL utf8 with length zero
 * represents an empty string.
 *
 * The caller must provide readable input bytes and, when a sufficient output
 * buffer is supplied, properly aligned storage for capacity records. Input and
 * output must not overlap. Keep the input unchanged throughout the call.
 */
size_t kasumi_linebreaks(const uint8_t *utf8, size_t length,
                        KasumiLineBreak *out, size_t capacity);

#ifdef __cplusplus
}
#endif

#endif
