/* hc_recover() against the Python reference: golden/extract_index.txt (tests/gen_extract.py).
 * Every case must reproduce the Python verdict (tag_ok), and where Python recovers, the exact
 * 128 bits and the class of the accepted candidate.  Where Python rejects, C must reject too
 * (no false accept).  Exits non-zero on any mismatch.  Usage: test_extract [name-substring] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "hubcore/extract.h"

#ifndef GOLDEN_DIR
#define GOLDEN_DIR "tests/golden/"
#endif

static double now(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + 1e-9 * (double)ts.tv_nsec;
}

static uint8_t *slurp(const char *name, size_t *n)
{
    char path[512];
    snprintf(path, sizeof path, GOLDEN_DIR "%s", name);
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); return NULL; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *b = malloc((size_t)sz ? (size_t)sz : 1);
    if (b && fread(b, 1, (size_t)sz, f) != (size_t)sz) { free(b); b = NULL; }
    fclose(f);
    if (n) *n = (size_t)sz;
    return b;
}

static int unhex(const char *s, uint8_t *o, int n)
{
    for (int i = 0; i < n; i++) {
        unsigned v;
        if (sscanf(s + 2 * i, "%2x", &v) != 1) return -1;
        o[i] = (uint8_t)v;
    }
    return 0;
}

static const char *cname(int c)
{
    static const char *n[] = {"none", "identity", "rescale", "crop_corner", "crop_symmetric", "declared"};
    return n[c];
}

static int expect_class(const char *s)
{
    if (!strcmp(s, "identity")) return HC_CAND_IDENTITY;
    if (!strcmp(s, "rescale")) return HC_CAND_RESCALE;
    if (!strcmp(s, "crop_corner")) return HC_CAND_CROP_CORNER;
    if (!strcmp(s, "crop_symmetric")) return HC_CAND_CROP_SYMMETRIC;
    if (!strcmp(s, "declared")) return HC_CAND_DECLARED;
    return -1;
}

static int test_resample(void)
{
    char path[512];
    snprintf(path, sizeof path, GOLDEN_DIR "extract_resample.txt");
    FILE *f = fopen(path, "r");
    if (!f) { fprintf(stderr, "no %s\n", path); return 1; }
    size_t blen;
    uint8_t *blob = slurp("extract_resample.bin", &blen);
    if (!blob) return 1;
    size_t off = 0;
    int ih, iw, oh, ow, n = 0, bad = 0;
    double ay, by, ax, bx;
    while (fscanf(f, "%d %d %lf %lf %lf %lf %d %d", &ih, &iw, &ay, &by, &ax, &bx, &oh, &ow) == 8) {
        size_t ni = (size_t)ih * iw, no = (size_t)oh * ow;
        if (off + ni + 2 * no > blen) { fprintf(stderr, "resample golden truncated\n"); return 1; }
        const uint8_t *in = blob + off, *want = in + ni, *wcov = want + no;
        off += ni + 2 * no;
        uint8_t *got = malloc(no), *cov = malloc(no);
        if (hc_resample_affine_u8(in, ih, iw, ay, by, ax, bx, oh, ow, got)) { fprintf(stderr, "resample error\n"); return 1; }
        hc_coverage_map(ih, iw, ay, by / 2.0, ax, bx / 2.0, oh, ow, cov);
        size_t d1 = 0, d2 = 0;
        for (size_t i = 0; i < no; i++) { d1 += got[i] != want[i]; d2 += cov[i] != wcov[i]; }
        printf("resample case %d: %dx%d -> %dx%d  pixel mismatches %zu  coverage mismatches %zu\n",
               n, ih, iw, oh, ow, d1, d2);
        if (d1 || d2) bad++;
        free(got); free(cov);
        n++;
    }
    fclose(f);
    free(blob);
    if (n < 5) { fprintf(stderr, "too few resample cases (%d)\n", n); return 1; }
    return bad;
}

int main(int argc, char **argv)
{
    const char *filt = argc > 1 ? argv[1] : NULL;
    int fails = 0;
    if (!filt || !strcmp(filt, "resample")) {
        int b = test_resample();
        if (b) { printf("FAIL: resample/coverage unit\n"); fails++; }
        if (filt) return fails ? 1 : 0;
    }
    char path[512];
    snprintf(path, sizeof path, GOLDEN_DIR "extract_index.txt");
    FILE *idx = fopen(path, "r");
    if (!idx) { fprintf(stderr, "no %s (run tests/gen_extract.py)\n", path); return 1; }
    char name[128], file[256], keyhex[64], cls[32], bitstr[256];
    int h, w, dh, dw, pyok, n = 0, n_ok = 0, n_rej = 0, rej_match = 0;
    double tmax = 0, tmax_crop = 0, tmax_mri = 0, tmax_mri_noncrop = 0;
    while (fscanf(idx, "%127s %255s %d %d %d %d %63s %d %31s %255s", name, file, &h, &w, &dh, &dw,
                  keyhex, &pyok, cls, bitstr) == 10) {
        if (filt && strstr(name, filt) == NULL) continue;
        size_t sz;
        uint8_t *img = slurp(file, &sz);
        if (!img || sz != (size_t)h * w) { fprintf(stderr, "bad image %s\n", file); return 1; }
        uint8_t key[16], pybits[128];
        if (unhex(keyhex, key, 16)) return 1;
        for (int i = 0; i < 128; i++) pybits[i] = (uint8_t)(bitstr[i] - '0');
        hc_recovery r;
        double t0 = now();
        int rc = hc_recover(img, h, w, dh, dw, key, &r);
        double dt = now() - t0;
        free(img);
        int ok = (rc == HC_EXT_OK) && (r.tag_ok == pyok);
        int bits_eq = memcmp(r.bits, pybits, 128) == 0;
        if (ok && pyok) ok = bits_eq && (int)r.accepted.cls == expect_class(cls);
        printf("%-22s %4dx%-4d py:%s C:%s class py=%-11s C=%-11s bits%s evals=%d decodes=%d %.2fs  %s\n",
               name, h, w, pyok ? "OK  " : "rej ", r.tag_ok ? "OK  " : "rej ", cls,
               cname(r.accepted.cls), bits_eq ? "==" : "!=", r.n_exact_evals, r.n_decodes, dt,
               ok ? "match" : "MISMATCH");
        if (!ok) fails++;
        n++;
        if (pyok) n_ok++; else { n_rej++; if (ok) rej_match++; }
        if (dt > tmax) tmax = dt;
        int is_crop = strstr(name, "crop") != NULL;
        if (is_crop && dt > tmax_crop) tmax_crop = dt;
        if (strstr(name, "mri") && is_crop && dt > tmax_mri) tmax_mri = dt;
        if (strstr(name, "mri") && !is_crop && dt > tmax_mri_noncrop) tmax_mri_noncrop = dt;
    }
    fclose(idx);
    printf("cases %d (python recovers %d, python rejects %d, C rejected-as-python %d); "
           "max %.2fs, max crop %.2fs, max MRI512 crop %.2fs, max MRI512 non-crop %.2fs\n",
           n, n_ok, n_rej, rej_match, tmax, tmax_crop, tmax_mri, tmax_mri_noncrop);
    if (n == 0) { fprintf(stderr, "no cases ran\n"); return 1; }
    printf(fails ? "FAIL: %d mismatches\n" : "PASS: all %d cases match Python\n", fails ? fails : n);
    return fails ? 1 : 0;
}
