/* ROI / taint masks.  Port of embed.py: roi_cut, roi_from_image, floor_background,
 * ll_support_roi, _dilate*, roi_masks, clipped_blocks, placement_blocks, undercovered_blocks,
 * blocked_blocks, region_capacities. */
#include <stdlib.h>
#include <string.h>

#include "hubcore/embed.h"

int hc_roi_cut(uint64_t n, uint64_t s, uint64_t q)
{
    /* is_roi(p): d = p*n - s > 0 and 25*d^2 > D, D = n*q - s^2.
     * 25*d^2 > D  <=>  d^2 > floor(D/25)  (d^2 is an integer), which avoids 64-bit overflow. */
    uint64_t dbig = n * q - s * s;
    uint64_t lim = dbig / 25u;
    int lo = 0, hi = 256;
    while (lo < hi) {
        int mid = (lo + hi) >> 1;
        int roi = 0;
        uint64_t pn = (uint64_t)mid * n;
        if (pn > s) {
            uint64_t d = pn - s;
            roi = (d * d > lim);
        }
        if (roi)
            hi = mid;
        else
            lo = mid + 1;
    }
    return lo;
}

int hc_roi_from_image(const uint8_t *img, int h, int w, const uint8_t *valid, uint8_t *out)
{
    size_t total, i;
    uint64_t n = 0, s = 0, q = 0;
    int cut;
    if (h < 0 || w < 0)
        return HC_EMB_ARG;
    total = (size_t)h * (size_t)w;
    if (total > HC_EMB_MAX_PIXELS)
        return HC_EMB_ARG;
    if (valid) {
        for (i = 0; i < total; i++)
            if (valid[i]) {
                unsigned p = img[i] <= HC_EMB_ROI_STATS_FLOOR ? 0u : img[i];
                n++;
                s += p;
                q += (uint64_t)p * p;
            }
    }
    if (!valid || n == 0) { /* empty sample falls back to all pixels */
        n = s = q = 0;
        for (i = 0; i < total; i++) {
            unsigned p = img[i] <= HC_EMB_ROI_STATS_FLOOR ? 0u : img[i];
            n++;
            s += p;
            q += (uint64_t)p * p;
        }
    }
    cut = hc_roi_cut(n, s, q);
    for (i = 0; i < total; i++) {
        uint8_t v = (uint8_t)((int)img[i] >= cut);
        if (valid && !valid[i])
            v = 0;
        out[i] = v;
    }
    return HC_EMB_OK;
}

int hc_floor_background(const uint8_t *img, int h, int w, uint8_t *out)
{
    size_t total = (size_t)h * (size_t)w, i;
    uint8_t *roi = (uint8_t *)malloc(total ? total : 1);
    int rc;
    if (!roi)
        return HC_EMB_NOMEM;
    rc = hc_roi_from_image(img, h, w, NULL, roi);
    if (rc != HC_EMB_OK) {
        free(roi);
        return rc;
    }
    for (i = 0; i < total; i++) {
        uint8_t v = img[i];
        if (!roi[i] && v < HC_EMB_BG_FLOOR)
            v = HC_EMB_BG_FLOOR;
        out[i] = v;
    }
    free(roi);
    return HC_EMB_OK;
}

void hc_ll_support_roi(const uint8_t *roi, int h, int w, uint8_t *m)
{
    int lh = h / 2, lw = w / 2, r, c, dr, dc;
    for (r = 0; r < lh; r++)
        for (c = 0; c < lw; c++) {
            uint8_t v = 0;
            for (dr = -HC_EMB_ROI_SUPPORT_LL; dr <= HC_EMB_ROI_SUPPORT_LL && !v; dr++) {
                int sr = 2 * r + dr;
                if (sr < 0 || sr >= h)
                    continue;
                for (dc = -HC_EMB_ROI_SUPPORT_LL; dc <= HC_EMB_ROI_SUPPORT_LL; dc++) {
                    int sc = 2 * c + dc;
                    if (sc < 0 || sc >= w)
                        continue;
                    if (roi[(size_t)sr * w + sc]) {
                        v = 1;
                        break;
                    }
                }
            }
            m[(size_t)r * lw + c] = v;
        }
}

int hc_dilate(uint8_t *mask, int h, int w, int m)
{
    /* A square structuring element is separable: dilate rows, then columns. */
    size_t total = (size_t)h * (size_t)w;
    uint8_t *tmp;
    int r, c, k;
    if (m <= 0 || total == 0)
        return HC_EMB_OK;
    tmp = (uint8_t *)malloc(total);
    if (!tmp)
        return HC_EMB_NOMEM;
    for (r = 0; r < h; r++)
        for (c = 0; c < w; c++) {
            uint8_t v = 0;
            for (k = -m; k <= m && !v; k++) {
                int cc = c + k;
                if (cc >= 0 && cc < w && mask[(size_t)r * w + cc])
                    v = 1;
            }
            tmp[(size_t)r * w + c] = v;
        }
    for (r = 0; r < h; r++)
        for (c = 0; c < w; c++) {
            uint8_t v = 0;
            for (k = -m; k <= m && !v; k++) {
                int rr = r + k;
                if (rr >= 0 && rr < h && tmp[(size_t)rr * w + c])
                    v = 1;
            }
            mask[(size_t)r * w + c] = v;
        }
    free(tmp);
    return HC_EMB_OK;
}

int hc_roi_masks(int ll_h, int ll_w, const uint8_t *img, int h, int w, const uint8_t *valid,
                 uint8_t *roi_blocks, uint8_t *roi_ll_out)
{
    int rh = h / 2, rw = w / 2, nbh, nbw, br, bc, r, c, rc;
    uint8_t *full, *roi_ll;
    size_t total = (size_t)h * (size_t)w;
    if (ll_h < 0 || ll_w < 0 || h < 0 || w < 0)
        return HC_EMB_ARG;
    full = (uint8_t *)malloc(total ? total : 1);
    roi_ll = roi_ll_out ? roi_ll_out : (uint8_t *)malloc((size_t)rh * (size_t)rw + 1);
    if (!full || !roi_ll) {
        free(full);
        if (!roi_ll_out)
            free(roi_ll);
        return HC_EMB_NOMEM;
    }
    rc = hc_roi_from_image(img, h, w, valid, full);
    if (rc == HC_EMB_OK) {
        hc_ll_support_roi(full, h, w, roi_ll);
        if (HC_EMB_ROI_CLEARANCE_LL > 0)
            rc = hc_dilate(roi_ll, rh, rw, HC_EMB_ROI_CLEARANCE_LL);
    }
    if (rc == HC_EMB_OK) {
        nbh = ll_h / HC_EMB_BLOCK;
        nbw = ll_w / HC_EMB_BLOCK;
        for (br = 0; br < nbh; br++)
            for (bc = 0; bc < nbw; bc++) {
                uint8_t v = 0;
                for (r = br * HC_EMB_BLOCK; r < (br + 1) * HC_EMB_BLOCK && r < rh && !v; r++)
                    for (c = bc * HC_EMB_BLOCK; c < (bc + 1) * HC_EMB_BLOCK && c < rw; c++)
                        if (roi_ll[(size_t)r * rw + c]) {
                            v = 1;
                            break;
                        }
                roi_blocks[(size_t)br * nbw + bc] = v;
            }
    }
    free(full);
    if (!roi_ll_out)
        free(roi_ll);
    return rc;
}

void hc_clipped_blocks(int ll_h, int ll_w, const uint8_t *img, int h, int w, uint8_t *out)
{
    int nbh = ll_h / HC_EMB_BLOCK, nbw = ll_w / HC_EMB_BLOCK, br, bc, r, c;
    for (br = 0; br < nbh; br++) {
        int r0 = 2 * br * HC_EMB_BLOCK - 1, r1 = 2 * br * HC_EMB_BLOCK + 2 * HC_EMB_BLOCK;
        if (r0 < 0)
            r0 = 0;
        if (r1 > h)
            r1 = h;
        for (bc = 0; bc < nbw; bc++) {
            int c0 = 2 * bc * HC_EMB_BLOCK - 1, c1 = 2 * bc * HC_EMB_BLOCK + 2 * HC_EMB_BLOCK;
            int mn = 255, mx = 0;
            if (c0 < 0)
                c0 = 0;
            if (c1 > w)
                c1 = w;
            if (r0 >= r1 || c0 >= c1) {
                out[(size_t)br * nbw + bc] = 1; /* nothing to write into */
                continue;
            }
            for (r = r0; r < r1; r++)
                for (c = c0; c < c1; c++) {
                    int v = img[(size_t)r * w + c];
                    if (v < mn)
                        mn = v;
                    if (v > mx)
                        mx = v;
                }
            out[(size_t)br * nbw + bc] =
                (uint8_t)(mn < HC_EMB_CLIP_MARGIN || mx > 255 - HC_EMB_CLIP_MARGIN);
        }
    }
}

int hc_placement_blocks(int ll_h, int ll_w, const uint8_t *img, int h, int w,
                        const uint8_t *valid, uint8_t *out)
{
    size_t nb = (size_t)(ll_h / HC_EMB_BLOCK) * (size_t)(ll_w / HC_EMB_BLOCK), i;
    uint8_t *clip = (uint8_t *)malloc(nb ? nb : 1);
    uint8_t *src = NULL;
    int rc;
    if (!clip)
        return HC_EMB_NOMEM;
    rc = hc_roi_masks(ll_h, ll_w, img, h, w, valid, out, NULL);
    if (rc != HC_EMB_OK) {
        free(clip);
        return rc;
    }
    if (valid) {
        size_t total = (size_t)h * (size_t)w;
        src = (uint8_t *)malloc(total ? total : 1);
        if (!src) {
            free(clip);
            return HC_EMB_NOMEM;
        }
        for (i = 0; i < total; i++)
            src[i] = valid[i] ? img[i] : 128;
        hc_clipped_blocks(ll_h, ll_w, src, h, w, clip);
        free(src);
    } else {
        hc_clipped_blocks(ll_h, ll_w, img, h, w, clip);
    }
    for (i = 0; i < nb; i++)
        out[i] = (uint8_t)(out[i] | clip[i]);
    free(clip);
    return HC_EMB_OK;
}

void hc_undercovered_blocks(int ll_h, int ll_w, const uint8_t *coverage, int h, int w,
                            uint8_t *out)
{
    int nbh = ll_h / HC_EMB_BLOCK, nbw = ll_w / HC_EMB_BLOCK, br, bc, r, c;
    const int step = HC_EMB_BLOCK * 2;
    for (br = 0; br < nbh; br++) {
        int r0 = br * step, r1 = (br + 1) * step;
        if (r1 > h)
            r1 = h;
        for (bc = 0; bc < nbw; bc++) {
            int c0 = bc * step, c1 = (bc + 1) * step;
            uint8_t v;
            if (c1 > w)
                c1 = w;
            if (r0 >= r1 || c0 >= c1) {
                v = 1;
            } else {
                long cnt = 0, size = (long)(r1 - r0) * (c1 - c0);
                for (r = r0; r < r1; r++)
                    for (c = c0; c < c1; c++)
                        if (coverage[(size_t)r * w + c])
                            cnt++;
                v = (uint8_t)(4 * cnt < 3 * size); /* mean < BLOCK_COVERAGE_MIN = 0.75 */
            }
            out[(size_t)br * nbw + bc] = v;
        }
    }
}

int hc_blocked_blocks(int ll_h, int ll_w, const uint8_t *img, int h, int w,
                      const uint8_t *coverage, uint8_t *out)
{
    int rc = hc_placement_blocks(ll_h, ll_w, img, h, w, coverage, out);
    if (rc == HC_EMB_OK && coverage) {
        size_t nb = (size_t)(ll_h / HC_EMB_BLOCK) * (size_t)(ll_w / HC_EMB_BLOCK), i;
        uint8_t *under = (uint8_t *)malloc(nb ? nb : 1);
        if (!under)
            return HC_EMB_NOMEM;
        hc_undercovered_blocks(ll_h, ll_w, coverage, h, w, under);
        for (i = 0; i < nb; i++)
            out[i] = (uint8_t)(out[i] | under[i]);
        free(under);
    }
    return rc;
}

void hc_region_capacities(const uint8_t *blocked, int nbh, int nbw,
                          int32_t out[HC_EMB_N_COPIES])
{
    size_t nb = (size_t)nbh * (size_t)nbw, i;
    long freeb = 0;
    int c;
    for (i = 0; i < nb; i++)
        if (!blocked[i])
            freeb++;
    for (c = 0; c < HC_EMB_N_COPIES; c++) {
        long v = freeb - (long)c * HC_EMB_CODEWORD;
        out[c] = (int32_t)(v > 0 ? v : 0);
    }
}
