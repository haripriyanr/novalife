#include <math.h>
#include <time.h>
#include "hcA_util.h"
#include "hubcore/polar.h"

int main(void) {
    size_t len, off; char *txt, *line; int ne = 0;
    uint8_t *g; uint32_t n, i;
    int differ_info = 0, differ_pm = 0, ok_tx = 0;
    double maxpm = 0.0;
    txt = (char *)hcA_readfile("tests/golden/polar_encode.txt", &len);
    HCA_CHECK(txt, "polar_encode golden missing (run tests/gen_polar.py)");
    for (line = txt; *line; ) {
        char *nl = strchr(line, '\n'); uint8_t info[128], code[256]; int k;
        if (nl) *nl = 0;
        for (k = 0; k < 128; k++) info[k] = (uint8_t)(line[k] - '0');
        hc_polar_encode(info, code);
        for (k = 0; k < 256; k++) HCA_CHECK(line[129 + k] == '0' + code[k], "encode case %d bit %d", ne, k);
        ne++;
        if (!nl) break;
        line = nl + 1;
    }
    free(txt);
    HCA_CHECK(ne == 500, "encode count %d", ne);
    printf("  encode: %d/500 bit-exact\n", ne);

    g = hcA_readfile("tests/golden/polar_decode.bin", &len);
    HCA_CHECK(g, "polar_decode golden missing");
    n = (uint32_t)g[0] | (uint32_t)g[1] << 8 | (uint32_t)g[2] << 16 | (uint32_t)g[3] << 24;
    off = 4;
    {
        struct timespec t0, t1; double total = 0.0, worst = 0.0;
        for (i = 0; i < n; i++) {
            double llr[256], pm_py, pm_c; uint8_t info[128]; int k, rc;
            memcpy(llr, g + off, sizeof llr); off += sizeof llr;
            memcpy(&pm_py, g + off + 128, 8);
            clock_gettime(CLOCK_MONOTONIC, &t0);
            rc = hc_polar_scl_decode(llr, info, &pm_c);
            clock_gettime(CLOCK_MONOTONIC, &t1);
            { double dt = (double)(t1.tv_sec - t0.tv_sec) * 1e3 + (double)(t1.tv_nsec - t0.tv_nsec) / 1e6; total += dt; if (dt > worst) worst = dt; }
            HCA_CHECK(rc == 0, "decode rc");
            if (memcmp(info, g + off, 128) != 0) { differ_info++; fprintf(stderr, "INFO MISMATCH case %u\n", i); }
            if (pm_c != pm_py) { differ_pm++; fprintf(stderr, "PM MISMATCH case %u: C %.17g py %.17g\n", i, pm_c, pm_py); }
            if (fabs(pm_c - pm_py) > maxpm) maxpm = fabs(pm_c - pm_py);
            (void)k; (void)ok_tx;
            off += 128 + 8;
        }
        printf("  decode: %u golden cases; info bits differ in %d, path metric not bit-identical in %d (max |dpm| %.3g)\n",
               n, differ_info, differ_pm, maxpm);
        printf("  speed: mean %.3f ms, worst %.3f ms per codeword (host, -O2)\n", total / n, worst);
    }
    free(g);
    HCA_CHECK(n >= 300, "need >= 300 decode cases");
    HCA_CHECK(differ_info == 0, "decoder differs from Python");
    HCA_CHECK(differ_pm == 0, "path metric differs from Python");
    printf("test_polar PASS\n");
    return 0;
}
