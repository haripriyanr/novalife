/* Unit goldens for the embedder: every integer function against embed.py. */
#include <math.h>

#include "embed_gold.h"
#include "hubcore/embed.h"

static long n_checks = 0, n_fail = 0;
#define CHECK(cond, ...)                                                                          \
    do {                                                                                          \
        n_checks++;                                                                               \
        if (!(cond)) {                                                                            \
            if (n_fail++ < 20) {                                                                  \
                fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);                              \
                fprintf(stderr, __VA_ARGS__);                                                     \
                fprintf(stderr, "\n");                                                            \
            }                                                                                     \
        }                                                                                         \
    } while (0)

static int same_bytes(const uint8_t *a, const uint8_t *b, size_t n)
{
    return memcmp(a, b, n) == 0;
}
static int same_double(double a, double b)
{
    return memcmp(&a, &b, sizeof a) == 0;
}

int main(void)
{
    gold_t g;
    int64_t cnt, k, j;
    gold_open(&g, "tests/golden/embed_unit.bin");

    /* A: roi_cut */
    gold_magic(&g, 0xA1);
    cnt = gold_i(&g);
    for (k = 0; k < cnt; k++) {
        uint64_t n = (uint64_t)gold_i(&g), s = (uint64_t)gold_i(&g), q = (uint64_t)gold_i(&g);
        int64_t e = gold_i(&g);
        int got = hc_roi_cut(n, s, q);
        CHECK(got == e, "roi_cut(%llu,%llu,%llu)=%d expected %lld", (unsigned long long)n,
              (unsigned long long)s, (unsigned long long)q, got, (long long)e);
    }
    printf("roi_cut: %lld cases\n", (long long)cnt);

    /* B: images */
    gold_magic(&g, 0xB1);
    cnt = gold_i(&g);
    for (k = 0; k < cnt; k++) {
        int h = (int)gold_i(&g), w = (int)gold_i(&g), lh = (int)gold_i(&g), lw = (int)gold_i(&g);
        int has_valid = (int)gold_i(&g);
        size_t px = (size_t)h * w, rl = (size_t)(h / 2) * (w / 2);
        size_t nb = (size_t)(lh / 4) * (lw / 4);
        uint8_t *img = gold_alloc(px), *valid = NULL;
        uint8_t *e_roi = gold_alloc(px), *e_floor = gold_alloc(px), *e_rb = gold_alloc(nb),
                *e_rl = gold_alloc(rl), *e_clip = gold_alloc(nb), *e_pl = gold_alloc(nb),
                *e_bl = gold_alloc(nb), *e_un = gold_alloc(nb);
        uint8_t *o_roi = gold_alloc(px), *o_floor = gold_alloc(px), *o_rb = gold_alloc(nb),
                *o_rl = gold_alloc(rl), *o_clip = gold_alloc(nb), *o_pl = gold_alloc(nb),
                *o_bl = gold_alloc(nb), *o_un = gold_alloc(nb);
        int rc;
        gold_bytes(&g, img, px);
        if (has_valid) {
            valid = gold_alloc(px);
            gold_bytes(&g, valid, px);
        }
        gold_bytes(&g, e_roi, px);
        gold_bytes(&g, e_floor, px);
        gold_bytes(&g, e_rb, nb);
        gold_bytes(&g, e_rl, rl);
        gold_bytes(&g, e_clip, nb);
        gold_bytes(&g, e_pl, nb);
        gold_bytes(&g, e_bl, nb);
        if (has_valid)
            gold_bytes(&g, e_un, nb);

        rc = hc_roi_from_image(img, h, w, valid, o_roi);
        CHECK(rc == 0 && same_bytes(o_roi, e_roi, px), "roi_from_image case %lld", (long long)k);
        rc = hc_floor_background(img, h, w, o_floor);
        CHECK(rc == 0 && same_bytes(o_floor, e_floor, px), "floor_background case %lld",
              (long long)k);
        { /* in place */
            uint8_t *cp = gold_alloc(px);
            memcpy(cp, img, px);
            rc = hc_floor_background(cp, h, w, cp);
            CHECK(rc == 0 && same_bytes(cp, e_floor, px), "floor_background in place %lld",
                  (long long)k);
            free(cp);
        }
        rc = hc_roi_masks(lh, lw, img, h, w, valid, o_rb, o_rl);
        CHECK(rc == 0 && same_bytes(o_rb, e_rb, nb), "roi_blocks case %lld", (long long)k);
        CHECK(same_bytes(o_rl, e_rl, rl), "roi_ll case %lld", (long long)k);
        hc_clipped_blocks(lh, lw, img, h, w, o_clip);
        CHECK(same_bytes(o_clip, e_clip, nb), "clipped_blocks case %lld", (long long)k);
        rc = hc_placement_blocks(lh, lw, img, h, w, valid, o_pl);
        CHECK(rc == 0 && same_bytes(o_pl, e_pl, nb), "placement_blocks case %lld", (long long)k);
        rc = hc_blocked_blocks(lh, lw, img, h, w, valid, o_bl);
        CHECK(rc == 0 && same_bytes(o_bl, e_bl, nb), "blocked_blocks case %lld", (long long)k);
        if (has_valid) {
            hc_undercovered_blocks(lh, lw, valid, h, w, o_un);
            CHECK(same_bytes(o_un, e_un, nb), "undercovered_blocks case %lld", (long long)k);
        }
        free(img);
        free(valid);
        free(e_roi); free(e_floor); free(e_rb); free(e_rl); free(e_clip); free(e_pl); free(e_bl);
        free(e_un); free(o_roi); free(o_floor); free(o_rb); free(o_rl); free(o_clip); free(o_pl);
        free(o_bl); free(o_un);
    }
    printf("image masks: %lld cases (roi, floor, roi_masks, clipped, placement, blocked, undercovered)\n",
           (long long)cnt);

    /* C: capacities */
    gold_magic(&g, 0xC1);
    cnt = gold_i(&g);
    for (k = 0; k < cnt; k++) {
        int nbh = (int)gold_i(&g), nbw = (int)gold_i(&g);
        size_t nb = (size_t)nbh * nbw;
        uint8_t *bl = gold_alloc(nb);
        int32_t got[4];
        gold_bytes(&g, bl, nb);
        hc_region_capacities(bl, nbh, nbw, got);
        for (j = 0; j < 4; j++) {
            int64_t e = gold_i(&g);
            CHECK(got[j] == e, "capacity %lld copy %lld: %d vs %lld", (long long)k, (long long)j,
                  got[j], (long long)e);
        }
        free(bl);
    }
    printf("region_capacities: %lld cases\n", (long long)cnt);

    /* D: placement_permute */
    gold_magic(&g, 0xD1);
    cnt = gold_i(&g);
    {
        long nperm = 0;
        for (k = 0; k < cnt; k++) {
            uint8_t key[16];
            int64_t m, ns;
            uint32_t *tbl = NULL;
            gold_bytes(&g, key, 16);
            m = gold_i(&g);
            ns = gold_i(&g);
            if (m <= 5000) {
                tbl = gold_alloc(sizeof(uint32_t) * (size_t)m);
                hc_perm_table_build(key, (uint32_t)m, tbl);
            }
            for (j = 0; j < ns; j++) {
                uint32_t slot = (uint32_t)gold_i(&g);
                int64_t e = gold_i(&g);
                uint32_t got = hc_placement_permute(key, (uint32_t)m, slot);
                CHECK(got == e, "permute m=%lld slot=%u: %u vs %lld", (long long)m, slot, got,
                      (long long)e);
                if (tbl)
                    CHECK(tbl[slot] == e, "perm table m=%lld slot=%u", (long long)m, slot);
                nperm++;
            }
            free(tbl);
        }
        printf("placement_permute: %ld (key,m,slot) points\n", nperm);
    }

    /* E: placement_map */
    gold_magic(&g, 0xE1);
    cnt = gold_i(&g);
    {
        long ncmp = 0, nerr = 0;
        for (k = 0; k < cnt; k++) {
            uint8_t key[16];
            int nbh, nbw, erasure, r;
            size_t nb;
            uint8_t *bl;
            uint32_t *tbl;
            int32_t *run = gold_alloc(sizeof(int32_t) * 4 * 256);
            int done = 0, rc;
            gold_bytes(&g, key, 16);
            nbh = (int)gold_i(&g);
            nbw = (int)gold_i(&g);
            erasure = (int)gold_i(&g);
            nb = (size_t)nbh * nbw;
            bl = gold_alloc(nb);
            gold_bytes(&g, bl, nb);
            tbl = gold_alloc(sizeof(uint32_t) * nb);
            hc_perm_table_build(key, (uint32_t)nb, tbl);
            rc = hc_placement_run(key, nbh, nbw, bl, 256, 4, erasure, NULL, run, &done);
            CHECK(rc == 0, "placement_run rc");
            for (r = 0; r < 4; r++) {
                int status = (int)gold_i(&g);
                int32_t one[256], viaT[256];
                int rc1 = hc_placement_map(key, nbh, nbw, r, bl, 256, erasure, NULL, one);
                int rc2 = hc_placement_map(key, nbh, nbw, r, bl, 256, erasure, tbl, viaT);
                if (status) {
                    nerr++;
                    CHECK(rc1 == HC_EMB_CAPACITY && rc2 == HC_EMB_CAPACITY,
                          "placement_map case %lld r=%d should raise (rc %d %d)", (long long)k,
                          r, rc1, rc2);
                    CHECK(done <= r, "placement_run copies_done=%d but region %d raises", done, r);
                } else {
                    int i;
                    int32_t exp[256];
                    for (i = 0; i < 256; i++)
                        exp[i] = (int32_t)gold_i(&g);
                    CHECK(rc1 == 0 && memcmp(one, exp, sizeof exp) == 0,
                          "placement_map case %lld r=%d (nbh=%d nbw=%d er=%d)", (long long)k, r,
                          nbh, nbw, erasure);
                    CHECK(rc2 == 0 && memcmp(viaT, exp, sizeof exp) == 0,
                          "placement_map(table) case %lld r=%d", (long long)k, r);
                    CHECK(done > r && memcmp(run + (size_t)r * 256, exp, sizeof exp) == 0,
                          "placement_run case %lld r=%d done=%d", (long long)k, r, done);
                    ncmp++;
                }
            }
            free(bl);
            free(tbl);
            free(run);
        }
        printf("placement_map: %ld region maps compared, %ld expected-capacity-errors matched\n",
               ncmp, nerr);
    }

    /* F: isqrt, qim_delta, local variance / std */
    gold_magic(&g, 0xF1);
    cnt = gold_i(&g);
    for (k = 0; k < cnt; k++) {
        uint64_t v = (uint64_t)gold_i(&g), e;
        gold_bytes(&g, &e, 8);
        CHECK(hc_isqrt(v) == e, "isqrt(%llu)=%llu vs %llu", (unsigned long long)v,
              (unsigned long long)hc_isqrt(v), (unsigned long long)e);
    }
    printf("isqrt: %lld values\n", (long long)cnt);
    gold_magic(&g, 0xF2);
    cnt = gold_i(&g);
    for (k = 0; k < cnt; k++) {
        int64_t s = gold_i(&g), e = gold_i(&g);
        CHECK(hc_qim_delta(s) == e, "qim_delta(%lld)", (long long)s);
    }
    printf("qim_delta: %lld values\n", (long long)cnt);
    gold_magic(&g, 0xF3);
    cnt = gold_i(&g);
    {
        long npos = 0;
        for (k = 0; k < cnt; k++) {
            int lh = (int)gold_i(&g), lw = (int)gold_i(&g), np = (int)gold_i(&g);
            int32_t *ll = gold_alloc(sizeof(int32_t) * (size_t)lh * lw);
            gold_bytes(&g, ll, sizeof(int32_t) * (size_t)lh * lw);
            for (j = 0; j < np; j++) {
                int r = (int)gold_i(&g), c = (int)gold_i(&g);
                int64_t ev = gold_i(&g), es = gold_i(&g);
                CHECK(hc_local_variance(ll, lh, lw, r, c) == ev, "local_variance (%d,%d)", r, c);
                CHECK(hc_local_std(ll, lh, lw, r, c) == es, "local_std (%d,%d)", r, c);
                npos++;
            }
            free(ll);
        }
        printf("local_variance/std: %ld positions\n", npos);
    }

    /* G: block arithmetic */
    gold_magic(&g, 0x61);
    cnt = gold_i(&g);
    for (k = 0; k < cnt; k++) {
        int32_t x[16], q[16], got[16];
        int bit, eb, b2;
        int64_t delta, v, ee;
        double el, ec, el2, gl, gl2;
        gold_bytes(&g, x, sizeof x);
        bit = (int)gold_i(&g);
        delta = gold_i(&g);
        v = gold_i(&g);
        ee = gold_i(&g);
        gold_bytes(&g, q, sizeof q);
        eb = (int)gold_i(&g);
        el = gold_d(&g);
        ec = gold_d(&g);
        b2 = (int)gold_i(&g);
        el2 = gold_d(&g);
        CHECK(hc_block_projection(x, 4) == v, "block_projection case %lld", (long long)k);
        CHECK(hc_embed_error(v, bit, delta) == ee, "embed_error case %lld", (long long)k);
        hc_quantize_block(x, 4, bit, delta, got, 4);
        CHECK(memcmp(got, q, sizeof q) == 0, "quantize_block case %lld", (long long)k);
        { /* in place with a different stride (inside a wider band) */
            int32_t band[4 * 9];
            int i2, j2, ok = 1;
            for (i2 = 0; i2 < 4; i2++)
                for (j2 = 0; j2 < 9; j2++)
                    band[i2 * 9 + j2] = (j2 >= 2 && j2 < 6) ? x[i2 * 4 + j2 - 2] : 7777;
            hc_quantize_block(band + 2, 9, bit, delta, band + 2, 9);
            for (i2 = 0; i2 < 4; i2++)
                for (j2 = 0; j2 < 9; j2++)
                    ok &= band[i2 * 9 + j2] ==
                          ((j2 >= 2 && j2 < 6) ? q[i2 * 4 + j2 - 2] : 7777);
            CHECK(ok, "quantize_block in place, strided, case %lld", (long long)k);
        }
        gl = hc_read_block_llr(x, 4, delta, &b2);
        CHECK(b2 == eb && same_double(gl, el), "read_block_llr case %lld: %.17g vs %.17g",
              (long long)k, gl, el);
        CHECK(same_double(hc_block_confidence(x, 4, delta), ec), "block_confidence case %lld",
              (long long)k);
        {
            int bb;
            gl2 = hc_read_block_llr(q, 4, delta, &bb);
            CHECK(bb == b2 || 1, "unused");
            CHECK(same_double(gl2, el2), "read-back llr case %lld", (long long)k);
        }
    }
    printf("block ops: %lld cases (projection, embed_error, quantize, llr, confidence, readback)\n",
           (long long)cnt);

    /* H: read_block */
    gold_magic(&g, 0x71);
    cnt = gold_i(&g);
    {
        long np2 = 0;
        for (k = 0; k < cnt; k++) {
            int lh = (int)gold_i(&g), lw = (int)gold_i(&g), np = (int)gold_i(&g);
            int32_t *ll = gold_alloc(sizeof(int32_t) * (size_t)lh * lw);
            gold_bytes(&g, ll, sizeof(int32_t) * (size_t)lh * lw);
            for (j = 0; j < np; j++) {
                int r = (int)gold_i(&g), c = (int)gold_i(&g);
                int64_t ed = gold_i(&g), d = 0;
                int eb = (int)gold_i(&g), b = -1;
                double el = gold_d(&g), l = 0;
                int rc = hc_read_block(ll, lh, lw, r, c, &b, &l, &d);
                CHECK(rc == 0 && d == ed && b == eb && same_double(l, el), "read_block (%d,%d)", r,
                      c);
                np2++;
            }
            CHECK(hc_read_block(ll, lh, lw, lh - 3, 0, &(int){0}, &(double){0}, NULL) ==
                      HC_EMB_ARG,
                  "read_block outside must be rejected");
            free(ll);
        }
        printf("read_block: %ld positions\n", np2);
    }
    gold_magic(&g, 0xFF);

    printf("embed unit: %ld checks, %ld failures\n", n_checks, n_fail);
    if (n_fail) {
        printf("FAIL\n");
        return 1;
    }
    printf("PASS\n");
    return 0;
}
