#include "CHyphenation.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static const char *tags[] = {
    "en-us", "en-gb", "de-1996", "fr", "es", "it", "pt", "nl",
    "sv", "da", "nb", "fi", "pl", "cs", "ru"
};

static void *load_dictionary(void *context) {
    const char *tag = context;
    /* Soft-hyphen precedence gives a known byte offset in every language. */
    const uint8_t word[] = "\xC3\xA9\xC2\xADx";
    size_t offset = SIZE_MAX;
    assert(kasumi_hyphenate(word, sizeof(word) - 1, (const uint8_t *)tag,
                           strlen(tag), &offset, 1) == 1);
    assert(offset == 2);
    return NULL;
}

int main(void) {
    /* Concurrent first loads exercise every embedded dictionary and cache. */
    pthread_t threads[30];
    for (size_t i = 0; i < 30; ++i)
        assert(pthread_create(&threads[i], NULL, load_dictionary,
                              (void *)tags[i % 15]) == 0);
    for (size_t i = 0; i < 30; ++i)
        assert(pthread_join(threads[i], NULL) == 0);

    const uint8_t word[] = "hyphenation";
    const uint8_t language[] = "en-us";
    size_t output[4] = {91, 92, 93, 94};
    assert(kasumi_hyphenate(word, 11, language, 5, NULL, 0) == 3);
    assert(kasumi_hyphenate(word, 11, language, 5, output, 2) == 3);
    assert(output[0] == 91 && output[1] == 92 && output[2] == 93 && output[3] == 94);
    assert(kasumi_hyphenate(word, 11, language, 5, output, 4) == 3);
    assert(output[0] == 2 && output[1] == 6 && output[2] == 7 && output[3] == 94);
    size_t uppercase[3];
    assert(kasumi_hyphenate((const uint8_t *)"HYPHENATION", 11,
                           (const uint8_t *)"EN-US", 5, uppercase, 3) == 3);
    assert(memcmp(output, uppercase, sizeof(uppercase)) == 0);

    /* Native French right minimum 2 must restore this final opportunity. */
    size_t french[2];
    assert(kasumi_hyphenate((const uint8_t *)"domino", 6,
                           (const uint8_t *)"fr", 2, french, 2) == 2);
    assert(french[0] == 2 && french[1] == 4);

    size_t preserved[4];
    memcpy(preserved, output, sizeof(output));
    const uint8_t malformed[] = {0xC0, 0xAF};
    assert(kasumi_hyphenate(malformed, 2, language, 5, output, 4) == SIZE_MAX);
    assert(kasumi_hyphenate(word, 11, malformed, 2, output, 4) == SIZE_MAX);
    assert(kasumi_hyphenate(word, 11, (const uint8_t *)"xx", 2, output, 4) == SIZE_MAX);
    assert(kasumi_hyphenate(NULL, 1, language, 5, output, 4) == SIZE_MAX);
    assert(kasumi_hyphenate(word, 11, NULL, 1, output, 4) == SIZE_MAX);
    assert(kasumi_hyphenate(word, SIZE_MAX, language, 5, output, 4) == SIZE_MAX);
    assert(kasumi_hyphenate(word, 11, NULL, 0, output, 4) == SIZE_MAX);
    assert(kasumi_hyphenate(NULL, 0, language, 5, output, 4) == 0);
    assert(memcmp(output, preserved, sizeof(output)) == 0);
    puts("C ABI checks passed; all 15 dictionaries loaded concurrently");
    return 0;
}
