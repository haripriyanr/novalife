/* hc_mark: port of embed.mark() (without the reader-side round-trip self-check). */
#include <stdlib.h>
#include <string.h>

#include "hubcore/embed.h"
#include "hubcore/iwt.h"
#include "hubcore/polar.h"


int hc_mark(const uint8_t *cover, int h, int w, const uint8_t *drawn_roi, const uint8_t key[16],
            const uint8_t block[HC_EMB_BITS], uint8_t *marked, hc_mark_info *info)
{
    int rc = HC_EMB_OK, lh, lw, nbh, nbw, c, i, copies_done = 0;
    size_t total, llsz, nb, k;
    int32_t *ll = NULL, *out = NULL, *sub = NULL, *buf32 = NULL;
    uint8_t *roi_blocks = NULL, *clip = NULL, *blocked = NULL, *alg_roi = NULL, *support = NULL;
    uint8_t *written = NULL;
    int32_t *placements = NULL;
    int32_t cap_tmp[HC_EMB_N_COPIES];

    if (h <= 0 || w <= 0 || (h & 1) || (w & 1) || !cover || !marked || !info || !key || !block)
        return HC_EMB_ARG;
    if ((size_t)h * (size_t)w > HC_EMB_MAX_PIXELS)
        return HC_EMB_ARG;
    memset(info, 0, sizeof *info);
    lh = h / 2;
    lw = w / 2;
    nbh = lh / HC_EMB_BLOCK;
    nbw = lw / HC_EMB_BLOCK;
    total = (size_t)h * (size_t)w;
    llsz = (size_t)lh * (size_t)lw;
    nb = (size_t)nbh * (size_t)nbw;
    info->ll_h = lh;
    info->ll_w = lw;
    info->blocks_used_per_region = HC_EMB_CODEWORD;

    ll = (int32_t *)malloc(llsz * sizeof(int32_t));
    out = (int32_t *)malloc(llsz * sizeof(int32_t));
    sub = (int32_t *)malloc(3 * llsz * sizeof(int32_t));
    buf32 = (int32_t *)malloc(total * sizeof(int32_t));
    roi_blocks = (uint8_t *)malloc(nb ? nb : 1);
    clip = (uint8_t *)malloc(nb ? nb : 1);
    blocked = (uint8_t *)malloc(nb ? nb : 1);
    alg_roi = (uint8_t *)malloc(total);
    support = (uint8_t *)malloc(llsz);
    written = (uint8_t *)calloc(llsz, 1);
    placements = (int32_t *)malloc(sizeof(int32_t) * HC_EMB_N_COPIES * HC_EMB_CODEWORD);
    if (!ll || !out || !sub || !buf32 || !roi_blocks || !clip || !blocked || !alg_roi || !support ||
        !written || !placements) {
        rc = HC_EMB_NOMEM;
        goto done;
    }

    for (k = 0; k < total; k++)
        buf32[k] = cover[k];
    rc = hc_iwt2d_53(buf32, h, w, ll, sub, sub + llsz, sub + 2 * llsz);
    if (rc != 0) {
        rc = HC_EMB_NOMEM;
        goto done;
    }

    /* --- the mask --- */
    rc = hc_roi_masks(lh, lw, cover, h, w, NULL, roi_blocks, NULL);
    if (rc != HC_EMB_OK)
        goto done;
    hc_clipped_blocks(lh, lw, cover, h, w, clip);
    for (k = 0; k < nb; k++)
        blocked[k] = (uint8_t)(roi_blocks[k] | clip[k]);
    hc_region_capacities(blocked, nbh, nbw, info->blocks_available_per_region);
    hc_region_capacities(clip, nbh, nbw, info->blocks_blocked_by_clipping_per_region);
    if (info->blocks_available_per_region[0] < HC_EMB_CODEWORD) {
        hc_region_capacities(roi_blocks, nbh, nbw, cap_tmp);
        info->refused_clip_only_capacity0 = info->blocks_blocked_by_clipping_per_region[0];
        info->refused_roi_only_capacity0 = cap_tmp[0];
        rc = HC_EMB_CAPACITY;
        goto done;
    }

    /* --- P2: the codeword --- */
    hc_polar_encode(block, info->codeword);

    /* --- P3 + P4: placement and sign-of-Hadamard embedding --- */
    memcpy(out, ll, llsz * sizeof(int32_t));
    rc = hc_placement_run(key, nbh, nbw, blocked, HC_EMB_CODEWORD, HC_EMB_N_COPIES, 0, NULL,
                          placements, &copies_done);
    if (rc != HC_EMB_OK)
        goto done;
    for (c = 0; c < copies_done; c++)
        for (i = 0; i < HC_EMB_CODEWORD; i++) {
            int32_t bi = placements[c * HC_EMB_CODEWORD + i];
            int br = (bi / nbw) * HC_EMB_BLOCK, bc = (bi % nbw) * HC_EMB_BLOCK, y, x;
            int64_t delta = hc_qim_delta(hc_local_std(ll, lh, lw, br, bc));
            hc_quantize_block(ll + (size_t)br * lw + bc, lw, info->codeword[i], delta,
                              out + (size_t)br * lw + bc, lw);
            for (y = 0; y < HC_EMB_BLOCK; y++)
                for (x = 0; x < HC_EMB_BLOCK; x++)
                    written[(size_t)(br + y) * lw + bc + x] = 1;
        }
    memcpy(info->placements, placements, sizeof(int32_t) * (size_t)copies_done * HC_EMB_CODEWORD);
    info->copies_written = copies_done;

    rc = hc_iiwt2d_53_raw(out, sub, sub + llsz, sub + 2 * llsz, lh, lw, buf32);
    if (rc != 0) {
        rc = HC_EMB_NOMEM;
        goto done;
    }
    for (k = 0; k < total; k++) {
        int32_t v = buf32[k];
        if (v < 0 || v > 255) {
            info->pixels_actually_clipped++;
            v = v < 0 ? 0 : 255;
        }
        marked[k] = (uint8_t)v;
    }
    /* Python computes the clip count on the already-clipped uint8 array, so it reports 0. */
    info->pixels_clipped_after_inverse = 0;

    /* --- what the marking actually touched --- */
    rc = hc_roi_from_image(cover, h, w, NULL, alg_roi);
    if (rc != HC_EMB_OK)
        goto done;
    hc_ll_support_roi(alg_roi, h, w, support);
    {
        long n_out = 0, n_u = 0, n_i = 0;
        int64_t sum_out = 0;
        int mx_d = 0, mx_a = 0, mx_o = 0;
        for (k = 0; k < total; k++) {
            int d = (int)marked[k] - (int)cover[k];
            int drawn = drawn_roi ? (drawn_roi[k] != 0) : 0, alg = alg_roi[k] != 0;
            if (d < 0)
                d = -d;
            if (drawn && d > mx_d)
                mx_d = d;
            if (alg && d > mx_a)
                mx_a = d;
            if (!alg) {
                if (d > mx_o)
                    mx_o = d;
                sum_out += d;
                n_out++;
            }
            if (drawn && alg)
                n_i++;
            if (drawn || alg)
                n_u++;
        }
        info->max_abs_change_inside_drawn_roi = mx_d;
        info->max_abs_change_inside_algorithm_roi = mx_a;
        info->max_abs_change_outside_roi = mx_o;
        info->mean_abs_change_outside_roi = n_out ? (double)sum_out / (double)n_out : 0.0;
        info->drawn_vs_algorithm_roi_jaccard = (double)n_i / (double)(n_u > 1 ? n_u : 1);
    }
    {
        long viol = 0;
        for (k = 0; k < llsz; k++)
            if (written[k] && support[k])
                viol++;
        info->support_rule_violations = (int)viol;
    }
    rc = HC_EMB_OK;

done:
    free(ll);
    free(out);
    free(sub);
    free(buf32);
    free(roi_blocks);
    free(clip);
    free(blocked);
    free(alg_roi);
    free(support);
    free(written);
    free(placements);
    return rc;
}
