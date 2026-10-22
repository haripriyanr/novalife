/* run_golden.c -- checks a C implementation of nl_api.h against golden/ (made by make_golden.py
 * from the Python reference).  Exit code 0 only if EVERY case matches.
 *   mark    : marked image must be byte-identical to Python's (or refusal must match), plus
 *             copies_written and the four capacities.
 *   recover : tag_ok must equal Python's; when tag_ok the 128 bits must be identical; the
 *             must-fail cases (wrong key, unmarked image) must NOT verify.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "nl_api.h"

static int hexbyte(const char *s) { unsigned v; sscanf(s, "%2x", &v); return (int)v; }
static void unhex(const char *s, uint8_t *out, int n) { for (int i = 0; i < n; i++) out[i] = (uint8_t)hexbyte(s + 2 * i); }
static uint8_t *slurp(const char *dir, const char *name, size_t want) {
    char p[512]; snprintf(p, sizeof p, "%s/%s", dir, name);
    FILE *f = fopen(p, "rb"); if (!f) { printf("  cannot open %s\n", p); return NULL; }
    uint8_t *b = malloc(want); size_t n = fread(b, 1, want, f); fclose(f);
    if (n != want) { printf("  %s: short read %zu/%zu\n", p, n, want); free(b); return NULL; }
    return b;
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : "golden";
    char p[512]; snprintf(p, sizeof p, "%s/cases.txt", dir);
    FILE *f = fopen(p, "r"); if (!f) { printf("no %s (run make_golden.py)\n", p); return 2; }
    uint8_t demo_key[16]; unhex("00112233445566778899aabbccddeeff", demo_key, 16);
    char line[1024]; int pass = 0, fail = 0;
    while (fgets(line, sizeof line, f)) {
        char kind[16], id[200], blockhex[64] = "", keyhex[64] = "";
        int h, w, dh = 0, dw = 0, refused = 0, copies = 0, cap[4] = {0}, tag_ok = 0;
        clock_t t0 = clock(); int ok = 1;
        if (sscanf(line, "%15s %199s", kind, id) != 2) continue;
        if (!strcmp(kind, "mark")) {
            if (sscanf(line, "%*s %*s %d %d %d %d %d %d %d %d %63s", &h, &w, &refused, &copies, &cap[0], &cap[1], &cap[2], &cap[3], blockhex) != 9) { printf("bad line\n"); return 2; }
            char fn[260]; snprintf(fn, sizeof fn, "%s.cover.bin", id);
            uint8_t *cover = slurp(dir, fn, (size_t)h * w); uint8_t block[16]; unhex(blockhex, block, 16);
            uint8_t *marked = malloc((size_t)h * w); nl_mark_info info; memset(&info, 0, sizeof info);
            int rc = cover ? nl_mark(cover, h, w, demo_key, block, marked, &info) : -99;
            if (refused) { ok = (rc == 1); if (!ok) printf("  expected refusal, got rc=%d\n", rc); }
            else {
                ok = (rc == 0);
                if (!ok) printf("  rc=%d (expected 0)\n", rc);
                else {
                    snprintf(fn, sizeof fn, "%s.marked.bin", id);
                    uint8_t *exp = slurp(dir, fn, (size_t)h * w);
                    if (!exp) ok = 0;
                    else {
                        size_t diff = 0, first = 0; for (size_t i = 0; i < (size_t)h * w; i++) if (marked[i] != exp[i]) { if (!diff) first = i; diff++; }
                        if (diff) { ok = 0; printf("  marked image differs in %zu pixels (first at %zu)\n", diff, first); }
                        if (info.copies_written != copies) { ok = 0; printf("  copies_written %d != %d\n", info.copies_written, copies); }
                        for (int k = 0; k < 4; k++) if (info.capacity[k] != cap[k]) { ok = 0; printf("  capacity[%d] %d != %d\n", k, info.capacity[k], cap[k]); }
                        free(exp);
                    }
                }
            }
            free(cover); free(marked);
        } else if (!strcmp(kind, "recover")) {
            if (sscanf(line, "%*s %*s %d %d %d %d %d %63s %63s", &h, &w, &dh, &dw, &tag_ok, blockhex, keyhex) != 7) { printf("bad line\n"); return 2; }
            char fn[260]; snprintf(fn, sizeof fn, "%s.img.bin", id);
            uint8_t *img = slurp(dir, fn, (size_t)h * w); uint8_t key[16]; unhex(keyhex, key, 16);
            nl_recover_result r; memset(&r, 0, sizeof r);
            int rc = img ? nl_recover(img, h, w, dh, dw, key, &r) : -99;
            if (rc != 0) { ok = 0; printf("  rc=%d\n", rc); }
            else if ((r.tag_ok != 0) != (tag_ok != 0)) { ok = 0; printf("  tag_ok %d != expected %d\n", r.tag_ok, tag_ok); }
            else if (tag_ok && strcmp(blockhex, "-")) {
                uint8_t eb[16]; unhex(blockhex, eb, 16);
                if (memcmp(eb, r.block, 16)) { ok = 0; printf("  recovered 128 bits differ\n"); }
            }
            free(img);
        } else continue;
        double secs = (double)(clock() - t0) / CLOCKS_PER_SEC;
        printf("%s %-44s %6.2fs\n", ok ? "PASS" : "FAIL", id, secs);
        ok ? pass++ : fail++;
    }
    fclose(f);
    printf("run_golden: %d passed, %d failed\n", pass, fail);
    return fail ? 1 : 0;
}
