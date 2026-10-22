#include "hubcore/polar.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "polar_tables.h"

#define N HC_POLAR_N
#define M 8
#define L HC_POLAR_L


void hc_polar_encode(const uint8_t info[HC_POLAR_K], uint8_t code[HC_POLAR_N]) {
    unsigned step, i, j;
    memset(code, 0, N);
    for (i = 0; i < HC_POLAR_K; i++) code[hc_polar_info_index[i]] = info[i] ? 1 : 0;
    for (step = 1; step < N; step *= 2)
        for (i = 0; i < N; i += 2 * step)
            for (j = i; j < i + step; j++) code[j] ^= code[j + step];
}

typedef struct {
    double llr[M + 1][N];
    uint8_t bit[M + 1][N]; /* bit[0] is u_hat */
    double pm;
} path_t;

static uint8_t frozen_mask[N];

static double fsign(double v) { return (v > 0.0) - (v < 0.0); }

/* min-sum F exactly as Python: sign(a)*sign(b)*minimum(|a|,|b|) */
static double f_op(double a, double b) {
    double aa = fabs(a), ab = fabs(b);
    return fsign(a) * fsign(b) * (aa < ab ? aa : ab);
}

static void update_llrs(path_t *p, unsigned leaf) {
    int stage;
    for (stage = M - 1; stage >= 0; stage--) {
        unsigned bl = 1u << stage, step = 2u * bl;
        unsigned off = (leaf / step) * step, k;
        const double *a = &p->llr[stage + 1][off];
        const double *b = &p->llr[stage + 1][off + bl];
        if ((leaf / bl) % 2u == 0u) {
            double *o = &p->llr[stage][off];
            for (k = 0; k < bl; k++) o[k] = f_op(a[k], b[k]);
        } else {
            const uint8_t *u = &p->bit[stage][off];
            double *o = &p->llr[stage][off + bl];
            /* Python: b + (1 - 2u) * a ; (1-2u) is exactly +-1 so this is b +- a */
            for (k = 0; k < bl; k++) o[k] = u[k] ? b[k] - a[k] : b[k] + a[k];
        }
    }
}

static void propagate(path_t *p, unsigned leaf, unsigned val) {
    unsigned stage, k;
    p->bit[0][leaf] = (uint8_t)val;
    for (stage = 0; stage < M; stage++) {
        unsigned bl = 1u << stage, step = 2u * bl;
        unsigned off = (leaf / step) * step;
        if ((leaf / bl) % 2u == 1u) {
            const uint8_t *l = &p->bit[stage][off];
            const uint8_t *r = &p->bit[stage][off + bl];
            uint8_t *o = &p->bit[stage + 1][off];
            for (k = 0; k < bl; k++) {
                o[k] = (uint8_t)(l[k] ^ r[k]);
                o[bl + k] = r[k];
            }
        }
    }
}

typedef struct {
    double pm;
    unsigned parent, val;
} cand_t;

int hc_polar_scl_decode(const double llr[HC_POLAR_N], uint8_t info[HC_POLAR_K], double *pm_out) {
    path_t *cur, *nxt, *pool;
    unsigned P = 1, i, k;
    static int inited = 0;
    if (!inited) {
        memset(frozen_mask, 1, sizeof frozen_mask);
        for (k = 0; k < HC_POLAR_K; k++) frozen_mask[hc_polar_info_index[k]] = 0;
        inited = 1;
    }
    pool = (path_t *)calloc(2u * L, sizeof(path_t));
    if (!pool) return -1;
    cur = pool;
    nxt = pool + L;
    memcpy(cur[0].llr[M], llr, sizeof(double) * N);
    cur[0].pm = 0.0;

    for (i = 0; i < N; i++) {
        cand_t cand[2 * L];
        unsigned nc = 0, keep, j;
        for (k = 0; k < P; k++) update_llrs(&cur[k], i);
        for (k = 0; k < P; k++) {
            double leaf = cur[k].llr[0][i];
            cand[nc].pm = cur[k].pm + (leaf < 0.0 ? fabs(leaf) : 0.0);
            cand[nc].parent = k;
            cand[nc].val = 0;
            nc++;
            if (!frozen_mask[i]) {
                cand[nc].pm = cur[k].pm + (leaf > 0.0 ? fabs(leaf) : 0.0);
                cand[nc].parent = k;
                cand[nc].val = 1;
                nc++;
            }
        }
        /* Python reorders (stable argsort by pm) only at information leaves; at a frozen
         * leaf the path order is left untouched, and that matters for later ties. */
        for (j = 1; !frozen_mask[i] && j < nc; j++) {
            cand_t t = cand[j];
            int q = (int)j - 1;
            while (q >= 0 && cand[q].pm > t.pm) {
                cand[q + 1] = cand[q];
                q--;
            }
            cand[q + 1] = t;
        }
        keep = nc < L ? nc : L;
        for (j = 0; j < keep; j++) {
            memcpy(&nxt[j], &cur[cand[j].parent], sizeof(path_t));
            nxt[j].pm = cand[j].pm;
            propagate(&nxt[j], i, cand[j].val);
        }
        {
            path_t *t = cur;
            cur = nxt;
            nxt = t;
        }
        P = keep;
    }
    {
        unsigned best = 0;
        for (k = 1; k < P; k++)
            if (cur[k].pm < cur[best].pm) best = k; /* first minimum, like np.argmin */
        for (k = 0; k < HC_POLAR_K; k++) info[k] = cur[best].bit[0][hc_polar_info_index[k]];
        if (pm_out) *pm_out = cur[best].pm;
    }
    free(pool);
    return 0;
}
