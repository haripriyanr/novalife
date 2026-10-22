#include "hcA_util.h"
#include "hubcore/tag_block.h"

int main(void) {
    size_t len; char *txt, *line;
    int nb = 0, nv = 0, nrej = 0, nacc = 0;
    txt = (char *)hcA_readfile("tests/golden/tag_block.txt", &len);
    HCA_CHECK(txt, "golden missing (run tests/gen_tag_block.py)");
    for (line = txt; *line; ) {
        char *nl = strchr(line, '\n'); const char *t = line + 2; uint8_t key[16];
        if (nl) *nl = 0;
        HCA_CHECK(hcA_hex(t, key, 16) == 16, "key");
        t = hcA_next_tok(t);
        if (line[0] == 'B') {
            unsigned ver = (unsigned)atoi(t), hub; uint64_t handle; uint8_t bits[128], blk[16], rt[16], rb[128]; int i;
            t = hcA_next_tok(t); hub = (unsigned)atoi(t);
            t = hcA_next_tok(t); handle = strtoull(t, NULL, 10);
            t = hcA_next_tok(t);
            HCA_CHECK(hc_tag_build_bits(key, ver, hub, handle, bits) == 0, "build rc");
            for (i = 0; i < 128; i++) HCA_CHECK(t[i] == '0' + bits[i], "case %d bit %d differs", nb, i);
            /* bytes form is the packed bits; round trips */
            HCA_CHECK(hc_tag_build_bytes(key, ver, hub, handle, blk) == 0, "build bytes rc");
            hc_tag_bits_to_bytes(bits, rt); HCA_CHECK(!memcmp(rt, blk, 16), "bytes != packed bits");
            hc_tag_bytes_to_bits(blk, rb); HCA_CHECK(!memcmp(rb, bits, 128), "unpack mismatch");
            nb++;
        } else if (line[0] == 'V') {
            uint8_t bits[128]; int i, ok; hc_tag_fields f, g; uint8_t blk[16];
            unsigned ver, hub; uint64_t handle, tag, expect;
            for (i = 0; i < 128; i++) bits[i] = (uint8_t)(t[i] - '0');
            t = hcA_next_tok(t); ok = atoi(t);
            t = hcA_next_tok(t); ver = (unsigned)atoi(t);
            t = hcA_next_tok(t); hub = (unsigned)atoi(t);
            t = hcA_next_tok(t); handle = strtoull(t, NULL, 10);
            t = hcA_next_tok(t); tag = strtoull(t, NULL, 10);
            t = hcA_next_tok(t); expect = strtoull(t, NULL, 10);
            hc_tag_verify_bits(bits, key, &f);
            HCA_CHECK(f.tag_ok == ok, "V case %d tag_ok %d expected %d", nv, f.tag_ok, ok);
            HCA_CHECK(f.version == ver && f.hub_id == hub && f.handle == handle && f.tag == tag && f.expected_tag == expect,
                      "V case %d field mismatch", nv);
            hc_tag_bits_to_bytes(bits, blk); hc_tag_verify_bytes(blk, key, &g);
            HCA_CHECK(g.tag_ok == ok && g.expected_tag == expect, "bytes verify differs");
            if (ok) nacc++; else nrej++;
            nv++;
        }
        if (!nl) break;
        line = nl + 1;
    }
    free(txt);
    HCA_CHECK(nb == 300 && nv == 1028 && nacc == 300 && nrej == 728, "counts %d %d %d %d", nb, nv, nacc, nrej);
    { uint8_t k[16] = {0}, b[128]; HCA_CHECK(hc_tag_build_bits(k, 16, 0, 0, b) == -1 && hc_tag_build_bits(k, 0, 4096, 0, b) == -1, "range checks"); }
    printf("  build: %d, verify: %d (%d accepted, %d rejected: bit flips x all 128 positions, wrong keys)\n", nb, nv, nacc, nrej);
    printf("test_tag_block PASS\n");
    return 0;
}
