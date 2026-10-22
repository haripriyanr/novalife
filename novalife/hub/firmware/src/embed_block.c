/* The bit in one block.  Port of embed.py: local_variance, local_std, qim_delta,
 * block_projection, sign_threshold, embed_error, quantize_block, read_block_llr,
 * block_confidence. */
#include "hubcore/embed.h"

#define WIN 3 /* QIM_STD_WINDOW */

static int64_t floordiv64(int64_t a, int64_t b) /* b > 0 */
{
    int64_t q = a / b;
    if ((a % b) < 0)
        q--;
    return q;
}

int64_t hc_local_variance(const int32_t *ll, int ll_h, int ll_w, int r, int c)
{
    int r0 = r - WIN, r1 = r + WIN + 1, c0 = c - WIN, c1 = c + WIN + 1, i, j;
    int64_t sum_x = 0, sum_x2 = 0, num, mean_x, mean_x2, var;
    if (r0 < 0)
        r0 = 0;
    if (r1 > ll_h)
        r1 = ll_h;
    if (c0 < 0)
        c0 = 0;
    if (c1 > ll_w)
        c1 = ll_w;
    if (r0 >= r1 || c0 >= c1)
        return 0; /* outside the band: the step drops to its floor */
    for (i = r0; i < r1; i++)
        for (j = c0; j < c1; j++) {
            int64_t v = ll[(size_t)i * ll_w + j];
            sum_x += v;
            sum_x2 += v * v;
        }
    num = (int64_t)(r1 - r0) * (c1 - c0);
    mean_x = floordiv64(sum_x, num);
    mean_x2 = floordiv64(sum_x2, num);
    var = mean_x2 - mean_x * mean_x;
    return var > 0 ? var : 0;
}

uint64_t hc_isqrt(uint64_t v)
{
    uint64_t r = 0, bit = (uint64_t)1 << 62;
    while (bit > v)
        bit >>= 2;
    while (bit) {
        if (v >= r + bit) {
            v -= r + bit;
            r = (r >> 1) + bit;
        } else {
            r >>= 1;
        }
        bit >>= 2;
    }
    return r;
}

int64_t hc_local_std(const int32_t *ll, int ll_h, int ll_w, int r, int c)
{
    return (int64_t)hc_isqrt((uint64_t)hc_local_variance(ll, ll_h, ll_w, r, c));
}

int64_t hc_qim_delta(int64_t std)
{
    int64_t d = HC_EMB_QIM_BASE_DELTA + ((5 * std) >> 3);
    return d + (d & 1);
}

static const int HAD1[4] = {1, 1, -1, -1};

int64_t hc_block_projection(const int32_t *blk, int stride)
{
    int64_t s = 0;
    int i, j;
    for (i = 0; i < 4; i++)
        for (j = 0; j < 4; j++)
            s += (int64_t)(HAD1[i] * HAD1[j]) * blk[(size_t)i * stride + j];
    return s;
}

int64_t hc_sign_threshold(int64_t delta)
{
    return floordiv64(delta, 2);
}

int64_t hc_embed_error(int64_t v, int bit, int64_t delta)
{
    int64_t t = hc_sign_threshold(delta), cap = HC_EMB_SIGN_MAX_MOVE_T * t, e;
    if (bit == 0)
        e = v < t ? t - v : 0;
    else
        e = v > -t ? -t - v : 0;
    if (e > cap)
        e = cap;
    if (e < -cap)
        e = -cap;
    return e;
}

void hc_quantize_block(const int32_t *src, int sstride, int bit, int64_t delta, int32_t *dst,
                       int dstride)
{
    int32_t x[16];
    int64_t e, q, rem;
    int i, j, k;
    for (i = 0; i < 4; i++)
        for (j = 0; j < 4; j++)
            x[i * 4 + j] = src[(size_t)i * sstride + j];
    e = hc_embed_error(hc_block_projection(x, 4), bit, delta);
    q = floordiv64(e, 16);
    rem = e - 16 * q; /* 0 <= rem < 16 */
    for (k = 0; k < 16; k++) {
        int64_t d = q + (k < rem ? 1 : 0);
        i = k / 4;
        j = k % 4;
        dst[(size_t)i * dstride + j] = (int32_t)(x[k] + (int64_t)(HAD1[i] * HAD1[j]) * d);
    }
}

double hc_read_block_llr(const int32_t *blk, int stride, int64_t delta, int *bit)
{
    int64_t v = hc_block_projection(blk, stride), t = hc_sign_threshold(delta);
    double llr = 2.0 * (double)v / (double)t;
    if (llr > HC_EMB_SIGN_LLR_CLIP)
        llr = HC_EMB_SIGN_LLR_CLIP;
    if (llr < -HC_EMB_SIGN_LLR_CLIP)
        llr = -HC_EMB_SIGN_LLR_CLIP;
    *bit = v < 0 ? 1 : 0;
    return llr;
}

double hc_block_confidence(const int32_t *blk, int stride, int64_t delta)
{
    int64_t v = hc_block_projection(blk, stride), t = hc_sign_threshold(delta);
    double x = (double)(v < 0 ? -v : v) / (double)t;
    return x < 1.0 ? x : 1.0;
}

int hc_read_block(const int32_t *ll, int ll_h, int ll_w, int r, int c, int *bit, double *llr,
                  int64_t *delta)
{
    int64_t d;
    if (r < 0 || c < 0 || r + 4 > ll_h || c + 4 > ll_w)
        return HC_EMB_ARG;
    d = hc_qim_delta(hc_local_std(ll, ll_h, ll_w, r, c));
    *llr = hc_read_block_llr(ll + (size_t)r * ll_w + c, ll_w, d, bit);
    if (delta)
        *delta = d;
    return HC_EMB_OK;
}
