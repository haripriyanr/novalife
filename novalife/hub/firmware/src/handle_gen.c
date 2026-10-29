/* handle_gen.c -- see handle_gen.h. */
#include <string.h>

#include "handle_gen.h"
#include "hubcore/ascon.h"

#define HG_SALT_MAX 64

static const uint8_t HG_NONCE[16] = { 'N', 'o', 'v', 'a', 'L', 'i', 'f', 'e',
                                      '/', 'h', 'a', 'n', 'd', 'l', 'e', '1' };

static volatile uint32_t s_jitter = 0;
static volatile uint32_t s_jitter_n = 0;
static uint8_t s_chain[16];
static uint64_t s_counter = 0;

void hg_add_entropy(uint32_t sample)
{
    uint32_t a = s_jitter;
    s_jitter = ((a << 5) | (a >> 27)) ^ sample;
    s_jitter_n = s_jitter_n + 1u;
}

static size_t put_be(uint8_t *p, uint64_t v, unsigned nbytes)
{
    for (unsigned i = 0; i < nbytes; i++)
        p[i] = (uint8_t)(v >> (8u * (nbytes - 1u - i)));
    return nbytes;
}

uint64_t hg_next_handle(const uint8_t key[16], const char *salt, uint64_t now)
{
    uint8_t ad[16 + 8 + 8 + 4 + 4 + HG_SALT_MAX];
    size_t n = 0;

    memcpy(ad, s_chain, 16);
    n += 16;
    n += put_be(ad + n, s_counter++, 8);
    n += put_be(ad + n, now, 8);
    n += put_be(ad + n, s_jitter, 4);
    n += put_be(ad + n, s_jitter_n, 4);
    if (salt) {
        size_t sl = strlen(salt);
        if (sl > HG_SALT_MAX) sl = HG_SALT_MAX;
        memcpy(ad + n, salt, sl);
        n += sl;
    }

    uint8_t tag[16];
    hc_ascon_tag(key, HG_NONCE, ad, n, tag);
    memcpy(s_chain, tag, 16);

    uint64_t h = 0;
    for (int i = 0; i < 8; i++)
        h = (h << 8) | tag[i];
    return h ? h : 1u;   /* 0 means "not set" in image_job_t */
}
