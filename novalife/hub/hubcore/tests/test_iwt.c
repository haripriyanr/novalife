#include "hcA_util.h"
#include "hubcore/iwt.h"

static int rd_i32(const uint8_t *p, size_t n, int32_t *o) { size_t i; for (i = 0; i < n; i++) o[i] = (int32_t)((uint32_t)p[4*i] | (uint32_t)p[4*i+1] << 8 | (uint32_t)p[4*i+2] << 16 | (uint32_t)p[4*i+3] << 24); return 0; }

int main(void) {
    size_t len, off; uint8_t *g; uint32_t n, i; int rt_ok = 0;
    g = hcA_readfile("tests/golden/iwt.bin", &len);
    HCA_CHECK(g, "golden missing (run tests/gen_iwt.py)");
    n = (uint32_t)g[0] | (uint32_t)g[1] << 8 | (uint32_t)g[2] << 16 | (uint32_t)g[3] << 24;
    off = 4;
    for (i = 0; i < n; i++) {
        int32_t h, w; size_t px, q; int32_t *img, *ex[5], *LL, *LH, *HL, *HH, *out; int j;
        rd_i32(g + off, 1, &h); rd_i32(g + off + 4, 1, &w); off += 8;
        px = (size_t)h * (size_t)w; q = px / 4;
        img = (int32_t *)malloc(px * 4 * 2); out = (int32_t *)malloc(px * 4);
        LL = (int32_t *)malloc(q * 4 * 4); LH = LL + q; HL = LH + q; HH = HL + q;
        for (j = 0; j < 5; j++) ex[j] = (int32_t *)malloc(px * 4);
        rd_i32(g + off, px, img); off += px * 4;
        rd_i32(g + off, q, ex[0]); off += q * 4;
        rd_i32(g + off, q, ex[1]); off += q * 4;
        rd_i32(g + off, q, ex[2]); off += q * 4;
        rd_i32(g + off, q, ex[3]); off += q * 4;
        rd_i32(g + off, px, ex[4]); off += px * 4;
        HCA_CHECK(hc_iwt2d_53(img, h, w, LL, LH, HL, HH) == 0, "fwd rc");
        HCA_CHECK(!memcmp(LL, ex[0], q * 4), "case %u (%dx%d) LL mismatch", i, h, w);
        HCA_CHECK(!memcmp(LH, ex[1], q * 4), "case %u (%dx%d) LH mismatch", i, h, w);
        HCA_CHECK(!memcmp(HL, ex[2], q * 4), "case %u (%dx%d) HL mismatch", i, h, w);
        HCA_CHECK(!memcmp(HH, ex[3], q * 4), "case %u (%dx%d) HH mismatch", i, h, w);
        HCA_CHECK(hc_iiwt2d_53(LL, LH, HL, HH, h / 2, w / 2, out) == 0, "inv rc");
        HCA_CHECK(!memcmp(out, ex[4], px * 4), "case %u clipped inverse differs from Python iiwt2d_53", i);
        HCA_CHECK(hc_iiwt2d_53_raw(LL, LH, HL, HH, h / 2, w / 2, out) == 0, "raw inv rc");
        HCA_CHECK(!memcmp(out, img, px * 4), "case %u raw round trip not exact", i);
        rt_ok++;
        for (j = 0; j < 5; j++) free(ex[j]);
        free(img); free(out); free(LL);
    }
    free(g);
    { int32_t d[4] = {0}; HCA_CHECK(hc_iwt2d_53(d, 3, 4, d, d, d, d) == -1 && hc_iwt2d_53(d, 4, 3, d, d, d, d) == -1, "odd dims rejected"); }
    HCA_CHECK(n >= 50, "case count %u", n);
    printf("  %u cases: forward subbands bit-exact vs Python, clipped inverse == Python iiwt2d_53, raw round trip exact (%d)\n", n, rt_ok);
    printf("test_iwt PASS\n");
    return 0;
}
