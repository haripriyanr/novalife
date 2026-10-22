/* Keyed placement.  Port of embed.py: _feistel_f, feistel_half_bits, placement_permute,
 * placement_map / _placement_map_impl (copy-major, scan-forward). */
#include <stdlib.h>
#include <string.h>

#include "hubcore/ascon.h"
#include "hubcore/embed.h"

/* PLACEMENT_DOMAIN = b"Novalife/placement/v2" */
static const uint8_t PLACEMENT_DOMAIN[21] = {'N', 'o', 'v', 'a', 'l', 'i', 'f', 'e', '/', 'p', 'l',
                                             'a', 'c', 'e', 'm', 'e', 'n', 't', '/', 'v', '2'};

int hc_feistel_half_bits(uint64_t m)
{
    /* max(1, ((m-1).bit_length() + 1) // 2) */
    uint64_t v = m ? m - 1 : 0;
    int bl = 0, h;
    while (v) {
        bl++;
        v >>= 1;
    }
    h = (bl + 1) / 2;
    return h < 1 ? 1 : h;
}

/* _feistel_f: first 4 bytes (big endian) of the Ascon tag of (key, zero nonce, empty pt,
 * ad = domain || round || right(4, big endian)), masked to hbits. */
static uint32_t feistel_f(const uint8_t key[16], int rnd, uint32_t right, int hbits)
{
    static const uint8_t nonce[16] = {0};
    uint8_t ad[26], tag[16];
    uint32_t v;
    memcpy(ad, PLACEMENT_DOMAIN, 21);
    ad[21] = (uint8_t)rnd;
    ad[22] = (uint8_t)(right >> 24);
    ad[23] = (uint8_t)(right >> 16);
    ad[24] = (uint8_t)(right >> 8);
    ad[25] = (uint8_t)right;
    hc_ascon_tag(key, nonce, ad, sizeof ad, tag);
    v = ((uint32_t)tag[0] << 24) | ((uint32_t)tag[1] << 16) | ((uint32_t)tag[2] << 8) | tag[3];
    return hbits >= 32 ? v : (v & ((1u << hbits) - 1u));
}

uint32_t hc_placement_permute(const uint8_t key[16], uint32_t m, uint32_t slot)
{
    int h = hc_feistel_half_bits(m), r;
    uint32_t mask = (h >= 32) ? 0xFFFFFFFFu : ((1u << h) - 1u);
    uint32_t x = slot;
    for (;;) {
        uint32_t left = x >> h, right = x & mask;
        for (r = 0; r < HC_EMB_PLACEMENT_ROUNDS; r++) {
            uint32_t nr = left ^ feistel_f(key, r, right, h);
            left = right;
            right = nr;
        }
        x = (left << h) | right;
        if (x < m)
            return x;
    }
}

void hc_perm_table_build(const uint8_t key[16], uint32_t m, uint32_t *tbl)
{
    uint32_t i;
    for (i = 0; i < m; i++)
        tbl[i] = hc_placement_permute(key, m, i);
}

int hc_placement_run(const uint8_t key[16], int nbh, int nbw, const uint8_t *blocked, int n,
                     int ncopies, int allow_erasures, const uint32_t *perm, int32_t *out,
                     int *copies_done)
{
    uint64_t m = (uint64_t)(nbh > 0 ? nbh : 0) * (uint64_t)(nbw > 0 ? nbw : 0);
    uint8_t *used;
    uint64_t stride, cstride;
    int c, i;
    if (m == 0 || n <= 0 || ncopies < 0 || m > 0x7FFFFFFFu)
        return HC_EMB_ARG;
    used = (uint8_t *)calloc((size_t)m, 1);
    if (!used)
        return HC_EMB_NOMEM;
    stride = m / (uint64_t)n;
    if (stride < 1)
        stride = 1;
    cstride = stride / HC_EMB_N_COPIES;
    if (cstride < 1)
        cstride = 1;
    *copies_done = 0;
    for (c = 0; c < ncopies; c++) {
        for (i = 0; i < n; i++) {
            uint64_t j = ((uint64_t)i * stride + (uint64_t)c * cstride) % m;
            uint64_t steps = 0;
            int found = 0;
            uint32_t idx = 0;
            while (steps < m) {
                idx = perm ? perm[j] : hc_placement_permute(key, (uint32_t)m, (uint32_t)j);
                if (!used[j] && !blocked[idx]) {
                    found = 1;
                    break;
                }
                j = (j + 1) % m; /* wrap: a copy fails only when the whole pool is spent */
                steps++;
            }
            if (!found) {
                if (allow_erasures) {
                    out[(size_t)c * n + i] = -1;
                    continue;
                }
                free(used);
                return HC_EMB_OK; /* encoder: copies [0, c) are complete */
            }
            used[j] = 1;
            out[(size_t)c * n + i] = (int32_t)idx;
        }
        *copies_done = c + 1;
    }
    free(used);
    return HC_EMB_OK;
}

int hc_placement_map(const uint8_t key[16], int nbh, int nbw, int region, const uint8_t *blocked,
                     int n, int allow_erasures, const uint32_t *perm, int32_t *out)
{
    int32_t *all;
    int done = 0, rc;
    if (region < 0 || n <= 0)
        return HC_EMB_ARG;
    all = (int32_t *)malloc(sizeof(int32_t) * (size_t)n * (size_t)(region + 1));
    if (!all)
        return HC_EMB_NOMEM;
    rc = hc_placement_run(key, nbh, nbw, blocked, n, region + 1, allow_erasures, perm, all,
                          &done);
    if (rc == HC_EMB_OK) {
        if (done < region + 1)
            rc = HC_EMB_CAPACITY;
        else
            memcpy(out, all + (size_t)region * n, sizeof(int32_t) * (size_t)n);
    }
    free(all);
    return rc;
}
