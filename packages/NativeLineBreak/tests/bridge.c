#include "CLineBreak.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    /* Byte offsets distinguish this ABI from scalar or UTF-16 offsets. */
    const uint8_t text[] = "a \xE4\xB8\xAD\r\nb";
    KasumiLineBreak output[4];
    memset(output, 0xA5, sizeof(output));
    unsigned char before[sizeof(output)];
    memcpy(before, output, sizeof(output));
    assert(kasumi_linebreaks(text, sizeof(text) - 1, NULL, 0) == 3);
    assert(kasumi_linebreaks(text, sizeof(text) - 1, output, 2) == 3);
    assert(memcmp(before, output, sizeof(output)) == 0);
    assert(kasumi_linebreaks(text, sizeof(text) - 1, output, 4) == 3);
    assert(output[0].offset == 2 && output[0].mandatory == 0);
    assert(output[1].offset == 7 && output[1].mandatory == 1);
    assert(output[2].offset == 8 && output[2].mandatory == 1);
    assert(memcmp(before + 3 * sizeof(*output), &output[3], sizeof(*output)) == 0);

    /* Invalid inputs must not write even when output capacity is sufficient. */
    const uint8_t malformed[] = {0xC0, 0xAF};
    memcpy(before, output, sizeof(output));
    assert(kasumi_linebreaks(malformed, sizeof(malformed), output, 4) == SIZE_MAX);
    assert(kasumi_linebreaks(NULL, 1, output, 4) == SIZE_MAX);
    assert(kasumi_linebreaks(text, SIZE_MAX, output, 4) == SIZE_MAX);
    assert(memcmp(before, output, sizeof(output)) == 0);
    assert(kasumi_linebreaks(NULL, 0, NULL, 0) != SIZE_MAX);
    printf("C ABI checks passed (record size %zu, empty count %zu)\n",
           sizeof(KasumiLineBreak), kasumi_linebreaks(NULL, 0, NULL, 0));
    return 0;
}
