#include "hcA_util.h"
#include "hubcore/ascon.h"

static const char *KAT = "../tools/tag_reference/vectors/kat/LWC_AEAD_KAT_128_128.txt";

static int test_kat(void) {
    static const uint8_t K[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
    static const uint8_t N[16] = {16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31};
    size_t len; char *txt; char *p; int count = 0;
    const char *path = getenv("HC_KAT_FILE") ? getenv("HC_KAT_FILE") : KAT;
    txt = (char *)hcA_readfile(path, &len);
    HCA_CHECK(txt, "KAT file missing: %s", path);
    for (p = txt; (p = strstr(p, "Count = ")) != NULL; ) {
        char *pt = strstr(p, "PT = "), *ad = strstr(p, "AD = "), *ct = strstr(p, "CT = ");
        uint8_t ptb[64], adb[64], exp[96], got[96];
        long ptl, adl, ctl;
        HCA_CHECK(pt && ad && ct, "malformed KAT");
        ptl = hcA_hex(pt + 5, ptb, sizeof ptb); adl = hcA_hex(ad + 5, adb, sizeof adb);
        ctl = hcA_hex(ct + 5, exp, sizeof exp);
        if (pt + 5 < ct && *(pt + 5) == '\n') ptl = 0;
        if (*(ad + 5) == '\n') adl = 0;
        HCA_CHECK(ptl >= 0 && adl >= 0 && ctl == ptl + 16, "KAT parse (count %d)", count + 1);
        hc_ascon_aead_encrypt(K, N, ptb, (size_t)ptl, adb, (size_t)adl, got);
        HCA_CHECK(memcmp(got, exp, (size_t)ctl) == 0, "KAT %d mismatch", count + 1);
        count++;
        p = ct;
    }
    free(txt);
    HCA_CHECK(count == 1089, "expected 1089 KATs, got %d", count);
    printf("  official KATs: %d/1089 match\n", count);
    return 0;
}

static int test_hub(void) {
    size_t len; char *txt, *line; int ne = 0, nm = 0, nk = 0;
    txt = (char *)hcA_readfile("tests/golden/ascon_hub.txt", &len);
    HCA_CHECK(txt, "golden missing (run tests/gen_ascon.py)");
    for (line = txt; *line; ) {
        char *nl = strchr(line, '\n'); const char *t;
        uint8_t key[16], nonce[16], a[4096], b[4096], exp[8192], got[8192];
        if (nl) *nl = 0;
        t = line + 2;
        if (line[0] == 'E') {
            long pl, al, cl;
            HCA_CHECK(hcA_hex(t, key, 16) == 16, "key");
            t = hcA_next_tok(t); HCA_CHECK(hcA_hex(t, nonce, 16) == 16, "nonce");
            t = hcA_next_tok(t); pl = hcA_hex(t, a, sizeof a);
            t = hcA_next_tok(t); al = hcA_hex(t, b, sizeof b);
            t = hcA_next_tok(t); cl = hcA_hex(t, exp, sizeof exp);
            HCA_CHECK(pl >= 0 && al >= 0 && cl == pl + 16, "E parse");
            hc_ascon_aead_encrypt(key, nonce, a, (size_t)pl, b, (size_t)al, got);
            HCA_CHECK(!memcmp(got, exp, (size_t)cl), "E case %d mismatch", ne);
            if (pl == 0) { /* tag-only helper must agree */
                uint8_t tg[16]; hc_ascon_tag(key, nonce, b, (size_t)al, tg);
                HCA_CHECK(!memcmp(tg, exp, 16), "tag helper mismatch");
            }
            ne++;
        } else if (line[0] == 'M') {
            long ml, ol; unsigned nb;
            HCA_CHECK(hcA_hex(t, key, 16) == 16, "key");
            t = hcA_next_tok(t); ml = hcA_hex(t, a, sizeof a);
            t = hcA_next_tok(t); nb = (unsigned)atoi(t);
            t = hcA_next_tok(t); ol = hcA_hex(t, exp, sizeof exp);
            HCA_CHECK(ml >= 0 && ol == (long)nb / 8, "M parse");
            HCA_CHECK(hc_ascon_mac_truncated(key, a, (size_t)ml, nb, got) == 0, "mac rc");
            HCA_CHECK(!memcmp(got, exp, (size_t)ol), "M case %d mismatch", nm);
            nm++;
        } else if (line[0] == 'K') {
            long dl; size_t nbytes; long ol;
            HCA_CHECK(hcA_hex(t, key, 16) == 16, "key");
            t = hcA_next_tok(t); dl = hcA_hex(t, a, sizeof a);
            t = hcA_next_tok(t); nbytes = (size_t)atol(t);
            t = hcA_next_tok(t); ol = hcA_hex(t, exp, sizeof exp);
            HCA_CHECK(dl >= 0 && (size_t)ol == nbytes, "K parse");
            hc_ascon_keystream(key, a, (size_t)dl, got, nbytes);
            HCA_CHECK(!memcmp(got, exp, nbytes), "K case %d mismatch", nk);
            nk++;
        }
        if (!nl) break;
        line = nl + 1;
    }
    free(txt);
    HCA_CHECK(ne == 300 && nm == 200 && nk == 100, "golden counts %d %d %d", ne, nm, nk);
    printf("  hub golden: %d aead + %d mac_truncated + %d keystream match\n", ne, nm, nk);
    return 0;
}

int main(void) {
    if (test_kat()) return 1;
    if (test_hub()) return 1;
    printf("test_ascon PASS\n");
    return 0;
}
