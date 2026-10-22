#include "hubcore/iwt.h"

#include <stdlib.h>

/* floor shift right of a signed value, independent of the compiler's >> on negatives */
static int32_t sar(int32_t v, unsigned n) { return v >= 0 ? (int32_t)((uint32_t)v >> n) : ~(int32_t)((uint32_t)(~v) >> n); }
static int32_t add32(int32_t a, int32_t b) { return (int32_t)((uint32_t)a + (uint32_t)b); }
static int32_t sub32(int32_t a, int32_t b) { return (int32_t)((uint32_t)a - (uint32_t)b); }

/* forward 1-D: x has n (even) samples at stride xs; s,d get n/2 each (stride 1) */
static void fwd1d(const int32_t *x, size_t xs, int n, int32_t *s, int32_t *d) {
    int half = n / 2, k;
    for (k = 0; k < half; k++) {
        int32_t e = x[(size_t)(2 * k) * xs];
        int32_t ne = (k + 1 < half) ? x[(size_t)(2 * k + 2) * xs] : e;
        int32_t o = x[(size_t)(2 * k + 1) * xs];
        d[k] = sub32(o, sar(add32(e, ne), 1));
    }
    for (k = 0; k < half; k++) {
        int32_t e = x[(size_t)(2 * k) * xs];
        int32_t pd = k > 0 ? d[k - 1] : d[0];
        s[k] = add32(e, sar(add32(add32(pd, d[k]), 2), 2));
    }
}

/* inverse 1-D: s,d have half samples (stride 1); out has 2*half samples at stride os */
static void inv1d(const int32_t *s, const int32_t *d, int half, int32_t *out, size_t os,
                  int32_t *even_tmp) {
    int k;
    for (k = 0; k < half; k++) {
        int32_t pd = k > 0 ? d[k - 1] : d[0];
        even_tmp[k] = sub32(s[k], sar(add32(add32(pd, d[k]), 2), 2));
    }
    for (k = 0; k < half; k++) {
        int32_t ne = (k + 1 < half) ? even_tmp[k + 1] : even_tmp[k];
        out[(size_t)(2 * k) * os] = even_tmp[k];
        out[(size_t)(2 * k + 1) * os] = add32(d[k], sar(add32(even_tmp[k], ne), 1));
    }
}

int hc_iwt2d_53(const int32_t *img, int h, int w, int32_t *LL, int32_t *LH, int32_t *HL,
                int32_t *HH) {
    int h2, w2, r, c;
    int32_t *row_s, *row_d, *cs, *cd;
    if (h < 2 || w < 2 || (h & 1) || (w & 1)) return -1;
    h2 = h / 2;
    w2 = w / 2;
    row_s = (int32_t *)malloc(sizeof(int32_t) * (size_t)h * (size_t)w2 * 2u);
    cs = (int32_t *)malloc(sizeof(int32_t) * (size_t)h2 * 2u);
    if (!row_s || !cs) {
        free(row_s);
        free(cs);
        return -1;
    }
    row_d = row_s + (size_t)h * (size_t)w2;
    cd = cs + h2;
    for (r = 0; r < h; r++) fwd1d(img + (size_t)r * (size_t)w, 1, w, row_s + (size_t)r * w2, row_d + (size_t)r * w2);
    for (c = 0; c < w2; c++) {
        int k;
        fwd1d(row_s + c, (size_t)w2, h, cs, cd);
        for (k = 0; k < h2; k++) {
            LL[(size_t)k * w2 + c] = cs[k];
            LH[(size_t)k * w2 + c] = cd[k];
        }
        fwd1d(row_d + c, (size_t)w2, h, cs, cd);
        for (k = 0; k < h2; k++) {
            HL[(size_t)k * w2 + c] = cs[k];
            HH[(size_t)k * w2 + c] = cd[k];
        }
    }
    free(row_s);
    free(cs);
    return 0;
}

int hc_iiwt2d_53_raw(const int32_t *LL, const int32_t *LH, const int32_t *HL, const int32_t *HH,
                     int h2, int w2, int32_t *out) {
    int h = 2 * h2, w = 2 * w2, r, c, k;
    int32_t *row_s, *row_d, *a, *b, *tmp;
    if (h2 < 1 || w2 < 1) return -1;
    row_s = (int32_t *)malloc(sizeof(int32_t) * (size_t)h * (size_t)w2 * 2u);
    a = (int32_t *)malloc(sizeof(int32_t) * (size_t)(h2 > w2 ? h2 : w2) * 3u);
    if (!row_s || !a) {
        free(row_s);
        free(a);
        return -1;
    }
    row_d = row_s + (size_t)h * (size_t)w2;
    b = a + (h2 > w2 ? h2 : w2);
    tmp = b + (h2 > w2 ? h2 : w2);
    /* columns first: (LL,LH) -> row_s ; (HL,HH) -> row_d */
    for (c = 0; c < w2; c++) {
        for (k = 0; k < h2; k++) {
            a[k] = LL[(size_t)k * w2 + c];
            b[k] = LH[(size_t)k * w2 + c];
        }
        inv1d(a, b, h2, row_s + c, (size_t)w2, tmp);
        for (k = 0; k < h2; k++) {
            a[k] = HL[(size_t)k * w2 + c];
            b[k] = HH[(size_t)k * w2 + c];
        }
        inv1d(a, b, h2, row_d + c, (size_t)w2, tmp);
    }
    for (r = 0; r < h; r++) inv1d(row_s + (size_t)r * w2, row_d + (size_t)r * w2, w2, out + (size_t)r * w, 1, tmp);
    free(row_s);
    free(a);
    return 0;
}

int hc_iiwt2d_53(const int32_t *LL, const int32_t *LH, const int32_t *HL, const int32_t *HH,
                 int h2, int w2, int32_t *out) {
    size_t i, n = (size_t)(4 * h2) * (size_t)w2;
    if (hc_iiwt2d_53_raw(LL, LH, HL, HH, h2, w2, out) != 0) return -1;
    for (i = 0; i < n; i++) out[i] = out[i] < 0 ? 0 : (out[i] > 255 ? 255 : out[i]);
    return 0;
}
