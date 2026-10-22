/* Reader: port of tools/tag_reference/extract.py (pilot grid disabled) and
 * pilot_grid.resample_affine.  See include/hubcore/extract.h.
 *
 * Numerics: every double expression below keeps the order of operations of the numpy code
 * (separate multiply and add, no fused multiply-add: build with -ffp-contract=off); np.round
 * is round-half-to-even, i.e. rint(). */
#include "hubcore/extract.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "hubcore/embed.h"
#include "hubcore/iwt.h"
#include "hubcore/polar.h"
#include "hubcore/tag_block.h"

#define BLK HC_EMB_BLOCK
#define NCOPY HC_EMB_N_COPIES
#define NCW HC_EMB_CODEWORD

/* ------------------------------------------------------------------------------------------ */
/* resample_affine (+ restore's clip(round())) and coverage_map                                */
/* ------------------------------------------------------------------------------------------ */

static int is_id_map(double ay, double by, double ax, double bx, double tol)
{
    return fabs(ay - 1.0) < tol && fabs(ax - 1.0) < tol && fabs(by) < tol && fabs(bx) < tol;
}

static uint8_t clip_round_u8(double v)
{
    double r = rint(v); /* np.round: half to even */
    if (r < 0.0) return 0;
    if (r > 255.0) return 255;
    return (uint8_t)r;
}

int hc_resample_affine_u8(const uint8_t *img, int ih, int iw, double alpha_y, double beta_y,
                          double alpha_x, double beta_x, int out_h, int out_w, uint8_t *out)
{
    if (!img || !out || ih <= 0 || iw <= 0 || out_h <= 0 || out_w <= 0) return HC_EXT_ARG;
    if (is_id_map(alpha_y, beta_y, alpha_x, beta_x, 1e-9) && ih == out_h && iw == out_w) {
        memcpy(out, img, (size_t)ih * (size_t)iw); /* clip(round(integers)) == identity */
        return HC_EXT_OK;
    }
    /* the map is separable: per-row and per-column terms */
    int *y0 = malloc(sizeof(int) * 2 * (size_t)out_h);
    double *fy = malloc(sizeof(double) * (size_t)out_h);
    unsigned char *ymiss = malloc((size_t)out_h);
    int *x0 = malloc(sizeof(int) * 2 * (size_t)out_w);
    double *fx = malloc(sizeof(double) * (size_t)out_w);
    unsigned char *xmiss = malloc((size_t)out_w);
    if (!y0 || !fy || !ymiss || !x0 || !fx || !xmiss) {
        free(y0); free(fy); free(ymiss); free(x0); free(fx); free(xmiss);
        return HC_EXT_NOMEM;
    }
    int *y1 = y0 + out_h, *x1 = x0 + out_w;
    for (int Y = 0; Y < out_h; Y++) {
        double sy = alpha_y * (double)Y;
        sy = sy + beta_y;
        double c = sy < 0.0 ? 0.0 : (sy > (double)(ih - 1) ? (double)(ih - 1) : sy);
        int a = (int)floor(c);
        y0[Y] = a;
        y1[Y] = a + 1 < ih - 1 ? a + 1 : ih - 1;
        fy[Y] = c - (double)a;
        ymiss[Y] = sy < -1.0;
    }
    for (int X = 0; X < out_w; X++) {
        double sx = alpha_x * (double)X;
        sx = sx + beta_x;
        double c = sx < 0.0 ? 0.0 : (sx > (double)(iw - 1) ? (double)(iw - 1) : sx);
        int a = (int)floor(c);
        x0[X] = a;
        x1[X] = a + 1 < iw - 1 ? a + 1 : iw - 1;
        fx[X] = c - (double)a;
        xmiss[X] = sx < -1.0;
    }
    for (int Y = 0; Y < out_h; Y++) {
        const uint8_t *r0 = img + (size_t)y0[Y] * (size_t)iw;
        const uint8_t *r1 = img + (size_t)y1[Y] * (size_t)iw;
        double wy = fy[Y];
        double iy = 1.0 - wy;
        uint8_t *orow = out + (size_t)Y * (size_t)out_w;
        for (int X = 0; X < out_w; X++) {
            double v;
            if (ymiss[Y] || xmiss[X]) {
                v = 0.0;
            } else {
                double wx = fx[X];
                double ix = 1.0 - wx;
                double top = (double)r0[x0[X]] * ix + (double)r0[x1[X]] * wx;
                double bot = (double)r1[x0[X]] * ix + (double)r1[x1[X]] * wx;
                v = top * (1.0 - wy) + bot * wy;
                (void)iy;
            }
            orow[X] = clip_round_u8(v);
        }
    }
    free(y0); free(fy); free(ymiss); free(x0); free(fx); free(xmiss);
    return HC_EXT_OK;
}

void hc_coverage_map(int ih, int iw, double scale_y, double beta_y, double scale_x, double beta_x,
                     int out_h, int out_w, uint8_t *out)
{
    if (is_id_map(scale_y, beta_y, scale_x, beta_x, 1e-12) && ih == out_h && iw == out_w) {
        memset(out, 1, (size_t)out_h * (size_t)out_w);
        return;
    }
    for (int Y = 0; Y < out_h; Y++) {
        double ys = (double)Y * scale_y + beta_y * 2.0;
        uint8_t oky = (uint8_t)(ys >= -1.0 && ys <= (double)ih);
        uint8_t *row = out + (size_t)Y * (size_t)out_w;
        for (int X = 0; X < out_w; X++) {
            double xs = (double)X * scale_x + beta_x * 2.0;
            row[X] = (uint8_t)(oky && xs >= -1.0 && xs <= (double)iw);
        }
    }
}


/* LL band of a uint8 image through A's int32 transform (the other sub-bands are scratch). */
static int iwt_ll_u8(const uint8_t *img, int h, int w, int32_t *ll)
{
    size_t n = (size_t)h * (size_t)w, q = n / 4;
    int32_t *buf = malloc(sizeof(int32_t) * (n + 3 * q));
    if (!buf) return HC_EXT_NOMEM;
    for (size_t i = 0; i < n; i++) buf[i] = img[i];
    int rc = hc_iwt2d_53(buf, h, w, ll, buf + n, buf + n + q, buf + n + 2 * q);
    free(buf);
    return rc == 0 ? HC_EXT_OK : HC_EXT_ARG;
}

/* ------------------------------------------------------------------------------------------ */
/* candidates                                                                                  */
/* ------------------------------------------------------------------------------------------ */

typedef struct {
    hc_cand_class cls;
    double sy, by, sx, bx;
    double score;
    int priority;
} cand_t;

static int cand_is_identity(const cand_t *c)
{
    return fabs(c->sy - 1.0) < 1e-12 && fabs(c->sx - 1.0) < 1e-12 && fabs(c->by) < 1e-12 &&
           fabs(c->bx) < 1e-12;
}

#define MAX_CANDS 8

/* candidate_maps() with PILOT_ENABLED False.  Returns the number of candidates. */
static int candidate_maps(int decl_h, int decl_w, int recv_h, int recv_w, cand_t *out)
{
    int dl_y = decl_h / 2, dl_x = decl_w / 2;
    int rl_y = recv_h / 2, rl_x = recv_w / 2;
    double s_y = 1.0, s_x = 1.0;
    int n = 0;
    out[n++] = (cand_t){HC_CAND_IDENTITY, 1.0, 0.0, 1.0, 0.0, 0.0, 1};
    double sdy = (double)recv_h / (double)decl_h;
    double sdx = (double)recv_w / (double)decl_w;
    double res_y = (double)rl_y - (double)dl_y * s_y;
    double res_x = (double)rl_x - (double)dl_x * s_x;
    int no_crop = fabs(res_y) < HC_EXT_RESIDUAL_MIN_LL && fabs(res_x) < HC_EXT_RESIDUAL_MIN_LL;
    double mx = sdy > sdx ? sdy : sdx;
    int axes_agree = fabs(sdy - sdx) <= HC_EXT_AXIS_AGREE_TOL * mx;
    int resized = fabs(sdy - 1.0) > HC_EXT_SCALE_SNAP_TOL || fabs(sdx - 1.0) > HC_EXT_SCALE_SNAP_TOL;
    if (resized && (no_crop || axes_agree) && HC_EXT_SCALE_MIN <= sdy && sdy <= HC_EXT_SCALE_MAX &&
        HC_EXT_SCALE_MIN <= sdx && sdx <= HC_EXT_SCALE_MAX)
        out[n++] = (cand_t){HC_CAND_RESCALE, sdy, 0.0, sdx, 0.0, 0.0, 1};
    if (!no_crop && HC_EXT_SCALE_MIN <= s_y && s_y <= HC_EXT_SCALE_MAX && HC_EXT_SCALE_MIN <= s_x &&
        s_x <= HC_EXT_SCALE_MAX) {
        out[n++] = (cand_t){HC_CAND_CROP_CORNER, s_y, res_y * 1.0, s_x, res_x * 1.0, 0.0, 1};
        out[n++] = (cand_t){HC_CAND_CROP_SYMMETRIC, s_y, res_y * 0.5, s_x, res_x * 0.5, 0.0, 1};
    }
    /* out[1:] = sorted(out[1:], key=beta_y**2 + beta_x**2): stable insertion sort */
    for (int i = 2; i < n; i++) {
        cand_t t = out[i];
        double kt = t.by * t.by + t.bx * t.bx;
        int j = i - 1;
        while (j >= 1 && out[j].by * out[j].by + out[j].bx * out[j].bx > kt) {
            out[j + 1] = out[j];
            j--;
        }
        out[j + 1] = t;
    }
    return n;
}

/* ------------------------------------------------------------------------------------------ */
/* cheap score: copy-0 confidence on the interpolated LL band                                  */
/* ------------------------------------------------------------------------------------------ */

typedef struct {
    const int32_t *ll;  /* received LL band, rl_y x rl_x */
    int rl_y, rl_x;
    int dl_y, dl_x;     /* declared LL shape */
} score_ctx;

/* approximate_ll(...)[i, j]: bilinear sample of the received LL, border repeated */
static double approx_val(const score_ctx *s, const cand_t *c, int i, int j)
{
    int ih = s->rl_y, iw = s->rl_x;
    double ys = c->sy * (double)i;
    ys = ys + c->by;
    double xs = c->sx * (double)j;
    xs = xs + c->bx;
    ys = ys < 0.0 ? 0.0 : (ys > (double)(ih - 1) ? (double)(ih - 1) : ys);
    xs = xs < 0.0 ? 0.0 : (xs > (double)(iw - 1) ? (double)(iw - 1) : xs);
    int y0 = (int)floor(ys), x0 = (int)floor(xs);
    int y1 = y0 + 1 < ih - 1 ? y0 + 1 : ih - 1;
    int x1 = x0 + 1 < iw - 1 ? x0 + 1 : iw - 1;
    double fy = ys - (double)y0, fx = xs - (double)x0;
    const int32_t *L = s->ll;
    double top = (double)L[(size_t)y0 * iw + x0] * (1.0 - fx) + (double)L[(size_t)y0 * iw + x1] * fx;
    double bot = (double)L[(size_t)y1 * iw + x0] * (1.0 - fx) + (double)L[(size_t)y1 * iw + x1] * fx;
    return top * (1.0 - fy) + bot * fy;
}

/* copy_confidence(approximate_ll(...), placement of copy 0): only the sampled windows of the
 * interpolated band are evaluated (the band is a pointwise function of the indices, so this is
 * the same number as building the whole band). */
static double score_ll_band(const score_ctx *s, const cand_t *c, const int32_t *place0, int nbw)
{
    int pass = cand_is_identity(c) ||
               (fabs(c->sy - 1.0) < 1e-12 && fabs(c->sx - 1.0) < 1e-12 && s->rl_y == s->dl_y &&
                s->rl_x == s->dl_x);
    int ah = pass ? s->rl_y : s->dl_y; /* band returned by approximate_ll */
    int aw = pass ? s->rl_x : s->dl_x;
    double step = 255.0 / 63.0; /* np.linspace(0, 255, 64): i*step, last = stop */
    double sum = 0.0;
    int cnt = 0;
    for (int k = 0; k < HC_EXT_SCORE_SAMPLE_BLOCKS; k++) {
        double pv = (k == HC_EXT_SCORE_SAMPLE_BLOCKS - 1) ? 255.0 : (double)k * step;
        int i = (int)pv;
        int32_t bi = place0[i];
        if (bi < 0) continue;
        int br = (bi / nbw) * BLK, bc = (bi % nbw) * BLK;
        if (br + BLK > ah || bc + BLK > aw) continue;
        int r0 = br - 3 < 0 ? 0 : br - 3, r1 = br + 4 > ah ? ah : br + 4;
        int c0 = bc - 3 < 0 ? 0 : bc - 3, c1 = bc + 4 > aw ? aw : bc + 4;
        int ph = r1 - r0, pw = c1 - c0;
        int32_t tp[7 * 7], rp[7 * 7];
        for (int a = 0; a < ph; a++)
            for (int b = 0; b < pw; b++) {
                double v;
                if (pass) v = (double)s->ll[(size_t)(r0 + a) * aw + (c0 + b)];
                else v = approx_val(s, c, r0 + a, c0 + b);
                tp[a * pw + b] = (int32_t)v;          /* astype(int64): truncation */
                rp[a * pw + b] = (int32_t)rint(v);    /* np.round */
            }
        int64_t std = hc_local_std(tp, ph, pw, br - r0, bc - c0);
        int64_t delta = hc_qim_delta(std);
        double conf = hc_block_confidence(rp + (br - r0) * pw + (bc - c0), pw, delta);
        sum += conf;
        cnt++;
    }
    return cnt ? sum / (double)cnt : 0.0;
}

/* ------------------------------------------------------------------------------------------ */
/* the exact path                                                                              */
/* ------------------------------------------------------------------------------------------ */

typedef struct {
    const uint8_t *img;
    int h, w;               /* received (even) */
    int dh, dw;             /* declared */
    int dl_y, dl_x, nbh, nbw;
    uint8_t key[16];
    /* scratch for the exact path, allocated once */
    uint8_t *restored, *cov, *taint, *erase;
    int32_t *ll;
    int32_t *place;         /* NCOPY * NCW */
    uint32_t *perm;         /* optional permutation table */
    /* results of the last evaluation */
    double llrs[NCOPY][NCW];
    uint8_t dec[HC_POLAR_K];
    int tag_ok;
    int subset_mask;
    double llr_conf;
    int n_decodes;
} ctx_t;

static void sum_llrs(const ctx_t *x, int mask, double *comb)
{
    for (int i = 0; i < NCW; i++) comb[i] = 0.0;
    for (int c = 0; c < NCOPY; c++)
        if (mask & (1 << c))
            for (int i = 0; i < NCW; i++) comb[i] += x->llrs[c][i];
}

/* decode_attempts(): copy prefixes {0..3},{0..2},{0,1},{0}, then copies 1, 2, 3 alone.  A
 * combined vector identical to one already decoded is skipped (the decoder is deterministic,
 * so it could only repeat its failure).  Falls through to the combined decode of all copies. */
static int decode_attempts(ctx_t *x, int *tag_ok, uint8_t dec[HC_POLAR_K], int *mask_out)
{
    int masks[7] = {0xF, 0x7, 0x3, 0x1, 0x2, 0x4, 0x8};
    double tried[7][NCW];
    int nt = 0;
    double comb[NCW];
    hc_tag_fields f;
    for (int s = 0; s < 7; s++) {
        sum_llrs(x, masks[s], comb);
        int dup = 0;
        for (int t = 0; t < nt; t++)
            if (memcmp(tried[t], comb, sizeof comb) == 0) { dup = 1; break; }
        if (dup) continue;
        memcpy(tried[nt++], comb, sizeof comb);
        double pm;
        if (hc_polar_scl_decode(comb, dec, &pm) != 0) return HC_EXT_NOMEM;
        x->n_decodes++;
        hc_tag_verify_bits(dec, x->key, &f);
        if (f.tag_ok) { *tag_ok = 1; *mask_out = masks[s]; return HC_EXT_OK; }
    }
    /* nothing verified: the combined decode of all copies, for reporting */
    sum_llrs(x, 0xF, comb);
    double pm;
    if (hc_polar_scl_decode(comb, dec, &pm) != 0) return HC_EXT_NOMEM;
    x->n_decodes++;
    hc_tag_verify_bits(dec, x->key, &f);
    *tag_ok = f.tag_ok;
    *mask_out = 0xF;
    return HC_EXT_OK;
}

/* embed.read_regions(restored, key, coverage=cov): fills x->llrs */
static int read_regions(ctx_t *x)
{
    int rc = iwt_ll_u8(x->restored, x->dh, x->dw, x->ll);
    if (rc) return rc;
    rc = hc_placement_blocks(x->dl_y, x->dl_x, x->restored, x->dh, x->dw, x->cov, x->taint);
    if (rc) return rc == HC_EMB_NOMEM ? HC_EXT_NOMEM : HC_EXT_ARG;
    hc_undercovered_blocks(x->dl_y, x->dl_x, x->cov, x->dh, x->dw, x->erase);
    size_t nb = (size_t)x->nbh * (size_t)x->nbw;
    for (size_t i = 0; i < nb; i++) x->erase[i] |= x->taint[i];
    int done;
    rc = hc_placement_run(x->key, x->nbh, x->nbw, x->taint, NCW, NCOPY, 1, x->perm, x->place, &done);
    if (rc) return rc == HC_EMB_NOMEM ? HC_EXT_NOMEM : HC_EXT_ARG;
    double conf = 0.0;
    for (int c = 0; c < NCOPY; c++) {
        double acc = 0.0;
        for (int i = 0; i < NCW; i++) {
            double l = 0.0;
            int32_t bi = x->place[c * NCW + i];
            if (bi >= 0 && !x->erase[bi]) {
                int bit;
                int64_t delta;
                int r = hc_read_block(x->ll, x->dl_y, x->dl_x, (bi / x->nbw) * BLK,
                                      (bi % x->nbw) * BLK, &bit, &l, &delta);
                if (r) return HC_EXT_ARG;
            }
            x->llrs[c][i] = l;
            acc += fabs(l);
        }
        conf += acc / (double)NCW;
    }
    x->llr_conf = conf / (double)NCOPY;
    return HC_EXT_OK;
}

/* evaluate(): restore -> coverage -> read_regions -> decode_attempts.  Sets x->dec/tag_ok. */
static int evaluate(ctx_t *x, const cand_t *c)
{
    int rc;
    if (cand_is_identity(c) && x->h == x->dh && x->w == x->dw)
        memcpy(x->restored, x->img, (size_t)x->dh * (size_t)x->dw);
    else {
        rc = hc_resample_affine_u8(x->img, x->h, x->w, c->sy, c->by * 2.0, c->sx, c->bx * 2.0,
                                   x->dh, x->dw, x->restored);
        if (rc) return rc;
    }
    hc_coverage_map(x->h, x->w, c->sy, c->by, c->sx, c->bx, x->dh, x->dw, x->cov);
    rc = read_regions(x);
    if (rc) return rc;
    return decode_attempts(x, &x->tag_ok, x->dec, &x->subset_mask);
}

/* ------------------------------------------------------------------------------------------ */
/* recover()                                                                                   */
/* ------------------------------------------------------------------------------------------ */

typedef struct {
    cand_t c;
    double dist;
} fine_t;

/* stable insertion sort of fine candidates by a key */
static void sort_fine_by_score(fine_t *f, int n)
{
    for (int i = 1; i < n; i++) {
        fine_t t = f[i];
        int j = i - 1;
        while (j >= 0 && -f[j].c.score > -t.c.score) { f[j + 1] = f[j]; j--; }
        f[j + 1] = t;
    }
}

static void sort_fine_by_dist(fine_t *f, int n)
{
    for (int i = 1; i < n; i++) {
        fine_t t = f[i];
        int j = i - 1;
        while (j >= 0 && f[j].dist > t.dist) { f[j + 1] = f[j]; j--; }
        f[j + 1] = t;
    }
}

static void fill_result(hc_recovery *out, const ctx_t *x, const cand_t *acc, double bye, double bxe)
{
    out->tag_ok = x->tag_ok;
    memcpy(out->bits, x->dec, HC_TAG_TOTAL_BITS);
    hc_tag_verify_bits(x->dec, x->key, &out->fields);
    out->tag_ok = out->fields.tag_ok ? 1 : 0;
    out->accepted.cls = acc->cls;
    out->accepted.scale_y = acc->sy;
    out->accepted.scale_x = acc->sx;
    out->accepted.beta_y = acc->by + bye;
    out->accepted.beta_x = acc->bx + bxe;
    out->accepted.score = acc->score;
    out->decoded_subset_mask = x->subset_mask;
    out->n_decodes = x->n_decodes;
    out->llr_confidence = x->llr_conf;
}

int hc_recover(const uint8_t *img, int h, int w, int declared_h, int declared_w,
               const uint8_t key[16], hc_recovery *out)
{
    if (!img || !key || !out || h < 2 || w < 2 || declared_h < 8 || declared_w < 8 ||
        (declared_h & 1) || (declared_w & 1))
        return HC_EXT_ARG;
    memset(out, 0, sizeof *out);
    int rc = HC_EXT_OK;
    int eh = h - (h % 2), ew = w - (w % 2);
    uint8_t *trim = NULL;
    const uint8_t *rimg = img;
    if (eh != h || ew != w) { /* _pad_even */
        trim = malloc((size_t)eh * (size_t)ew);
        if (!trim) return HC_EXT_NOMEM;
        for (int r = 0; r < eh; r++) memcpy(trim + (size_t)r * ew, img + (size_t)r * w, (size_t)ew);
        rimg = trim;
    }
    ctx_t X;
    memset(&X, 0, sizeof X);
    X.img = rimg; X.h = eh; X.w = ew; X.dh = declared_h; X.dw = declared_w;
    X.dl_y = declared_h / 2; X.dl_x = declared_w / 2;
    X.nbh = X.dl_y / BLK; X.nbw = X.dl_x / BLK;
    memcpy(X.key, key, 16);
    size_t dpix = (size_t)declared_h * (size_t)declared_w;
    size_t nb = (size_t)X.nbh * (size_t)X.nbw;
    int32_t *ll_recv = malloc(sizeof(int32_t) * (size_t)(eh / 2) * (size_t)(ew / 2));
    uint8_t *approx = malloc(dpix);
    uint8_t *blk_score = malloc(nb ? nb : 1);
    int32_t *place_score = malloc(sizeof(int32_t) * NCOPY * NCW);
    X.restored = malloc(dpix);
    X.cov = malloc(dpix);
    X.taint = malloc(nb ? nb : 1);
    X.erase = malloc(nb ? nb : 1);
    X.ll = malloc(sizeof(int32_t) * (size_t)X.dl_y * (size_t)X.dl_x);
    X.place = malloc(sizeof(int32_t) * NCOPY * NCW);
    fine_t *fine = malloc(sizeof(fine_t) * 81);
    if (!ll_recv || !approx || !blk_score || !place_score || !X.restored || !X.cov || !X.taint ||
        !X.erase || !X.ll || !X.place || !fine || nb == 0) {
        rc = nb == 0 ? HC_EXT_ARG : HC_EXT_NOMEM;
        goto done;
    }
    if (nb <= 65536) {
        X.perm = malloc(sizeof(uint32_t) * nb);
        if (X.perm) hc_perm_table_build(key, (uint32_t)nb, X.perm);
    }

    /* 1. LL band of the received image (the cheap score interpolates it) */
    rc = iwt_ll_u8(rimg, eh, ew, ll_recv);
    if (rc) goto done;

    /* 2. candidates */
    cand_t cands[MAX_CANDS];
    int ncand = candidate_maps(declared_h, declared_w, eh, ew, cands);
    out->n_candidates = ncand;

    /* 3. ROI/clipping taint and placements at the declared geometry, for ranking only: the
     * received image rescaled by the scale-only map (no offset) */
    rc = hc_resample_affine_u8(rimg, eh, ew, (double)eh / (double)declared_h, 0.0,
                               (double)ew / (double)declared_w, 0.0, declared_h, declared_w, approx);
    if (rc) goto done;
    rc = hc_blocked_blocks(X.dl_y, X.dl_x, approx, declared_h, declared_w, NULL, blk_score);
    if (rc) { rc = rc == HC_EMB_NOMEM ? HC_EXT_NOMEM : HC_EXT_ARG; goto done; }
    int pdone;
    rc = hc_placement_run(key, X.nbh, X.nbw, blk_score, NCW, NCOPY, 1, X.perm, place_score, &pdone);
    if (rc) {
        out->no_placement = 1; /* Python: 'no placement at declared geometry' -> tag FAIL */
        rc = HC_EXT_OK;
        fill_result(out, &X, &cands[0], 0.0, 0.0);
        goto done;
    }

    score_ctx sc = {ll_recv, eh / 2, ew / 2, X.dl_y, X.dl_x};
    for (int i = 0; i < ncand; i++) cands[i].score = score_ll_band(&sc, &cands[i], place_score, X.nbw);

    /* priority ordering: stable sort by -score, identity pinned first */
    cand_t sorted[MAX_CANDS];
    memcpy(sorted, cands, sizeof(cand_t) * (size_t)ncand);
    for (int i = 1; i < ncand; i++) {
        cand_t t = sorted[i];
        int j = i - 1;
        while (j >= 0 && -sorted[j].score > -t.score) { sorted[j + 1] = sorted[j]; j--; }
        sorted[j + 1] = t;
    }
    cand_t ordered[MAX_CANDS];
    int no = 0;
    for (int i = 0; i < ncand; i++) if (sorted[i].priority && cand_is_identity(&sorted[i])) ordered[no++] = sorted[i];
    for (int i = 0; i < ncand; i++) if (sorted[i].priority && !cand_is_identity(&sorted[i])) ordered[no++] = sorted[i];
    for (int i = 0; i < ncand; i++) if (!sorted[i].priority) ordered[no++] = sorted[i];

    /* 4. fine-offset scan, exact path; the tag decides */
    static const double FO[9] = {-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0};
    int have_acc = 0, acc_ok = 0, have_dec = 0;
    cand_t accepted;
    double acc_dy = 0.0, acc_dx = 0.0;
    int lim = no < HC_EXT_MAX_EXACT_CANDIDATES ? no : HC_EXT_MAX_EXACT_CANDIDATES;
    for (int ci = 0; ci < lim; ci++) {
        const cand_t *coarse = &ordered[ci];
        int coarse_id = cand_is_identity(coarse);
        if (coarse_id && !(eh == declared_h && ew == declared_w)) continue;
        int nf;
        const double *fys;
        static const double ZERO[1] = {0.0};
        if (coarse_id && eh == declared_h && ew == declared_w) { fys = ZERO; nf = 1; }
        else { fys = FO; nf = 9; }
        int nfine = 0;
        for (int a = 0; a < nf; a++)
            for (int b = 0; b < nf; b++) {
                fine_t *f = &fine[nfine++];
                f->c = *coarse;
                f->c.by = coarse->by + fys[a];
                f->c.bx = coarse->bx + fys[b];
                f->c.priority = 0;
                f->c.score = score_ll_band(&sc, &f->c, place_score, X.nbw);
                f->dist = 0.0;
            }
        sort_fine_by_score(fine, nfine);
        int budget;
        if (coarse->priority && !coarse_id) {
            for (int i = 0; i < nfine; i++) {
                double ey = (fine[i].c.by - coarse->by) - HC_EXT_FINE_PRIOR_Y;
                double ex = (fine[i].c.bx - coarse->bx) - HC_EXT_FINE_PRIOR_X;
                fine[i].dist = ey * ey + ex * ex;
            }
            sort_fine_by_dist(fine, nfine);
            budget = nfine < HC_EXT_FINE_PRIORITY_CAP ? nfine : HC_EXT_FINE_PRIORITY_CAP;
        } else {
            budget = nfine < HC_EXT_FINE_EXACT_TOP ? nfine : HC_EXT_FINE_EXACT_TOP;
        }
        for (int i = 0; i < budget; i++) {
            rc = evaluate(&X, &fine[i].c);
            if (rc) goto done;
            out->n_exact_evals++;
            have_dec = 1;
            if (X.tag_ok) {
                accepted = *coarse;
                acc_dy = fine[i].c.by - coarse->by;
                acc_dx = fine[i].c.bx - coarse->bx;
                have_acc = 1;
                acc_ok = 1;
                break;
            }
            if (!have_acc) {
                accepted = *coarse;
                acc_dy = fine[i].c.by - coarse->by;
                acc_dx = fine[i].c.bx - coarse->bx;
                have_acc = 1;
            }
        }
        if (have_acc && acc_ok) break;
    }
    (void)have_dec;
    if (!have_acc) {
        accepted = (cand_t){HC_CAND_DECLARED, 1.0, 0.0, 1.0, 0.0, 0.0, 0};
        acc_dy = acc_dx = 0.0;
        rc = evaluate(&X, &accepted);
        if (rc) goto done;
        out->n_exact_evals++;
    }
    fill_result(out, &X, &accepted, acc_dy, acc_dx);
done:
    free(trim); free(ll_recv); free(approx); free(blk_score); free(place_score); free(X.restored);
    free(X.cov); free(X.taint); free(X.erase); free(X.ll); free(X.place); free(X.perm); free(fine);
    return rc;
}
