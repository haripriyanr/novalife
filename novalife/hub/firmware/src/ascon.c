#include "hubcore/ascon.h"

#include <stdlib.h>
#include <string.h>

const uint8_t HC_ASCON_NONCE_MAC[16] = {0x4E, 0x6F, 0x76, 0x61, 0x4C, 0x69, 0x66, 0x65,
                                        0x4D, 0x41, 0x43, 0x54, 0x30, 0x30, 0x30, 0x31};
const uint8_t HC_ASCON_NONCE_STREAM[16] = {0x4E, 0x6F, 0x76, 0x61, 0x4C, 0x69, 0x66, 0x65,
                                           0x53, 0x54, 0x52, 0x4D, 0x30, 0x30, 0x30, 0x31};
const uint8_t HC_ASCON_MAC_DOMAIN[21] = {'N', 'o', 'v', 'a', 'l', 'i', 'f', 'e', '/', 't', 'a',
                                         'g', '-', 'b', 'l', 'o', 'c', 'k', '/', 'v', '1'};

#define IV 0x00001000808C0001ULL
#define DSEP (0x80ULL << 56)
#define RATE 16u

static const uint8_t RC[12] = {0xF0, 0xE1, 0xD2, 0xC3, 0xB4, 0xA5, 0x96, 0x87, 0x78, 0x69, 0x5A, 0x4B};

static uint64_t ror(uint64_t x, unsigned n) { return (x >> n) | (x << (64u - n)); }

static void round_fn(uint64_t s[5], uint64_t c) {
    uint64_t t0, t1, t2, t3, t4;
    s[2] ^= c;
    s[0] ^= s[4];
    s[4] ^= s[3];
    s[2] ^= s[1];
    t0 = s[0] ^ (~s[1] & s[2]);
    t1 = s[1] ^ (~s[2] & s[3]);
    t2 = s[2] ^ (~s[3] & s[4]);
    t3 = s[3] ^ (~s[4] & s[0]);
    t4 = s[4] ^ (~s[0] & s[1]);
    t1 ^= t0;
    t0 ^= t4;
    t3 ^= t2;
    t2 = ~t2;
    s[0] = t0 ^ ror(t0, 19) ^ ror(t0, 28);
    s[1] = t1 ^ ror(t1, 61) ^ ror(t1, 39);
    s[2] = t2 ^ ror(t2, 1) ^ ror(t2, 6);
    s[3] = t3 ^ ror(t3, 10) ^ ror(t3, 17);
    s[4] = t4 ^ ror(t4, 7) ^ ror(t4, 41);
}

static void permute(uint64_t s[5], unsigned rounds) {
    unsigned i;
    for (i = 12u - rounds; i < 12u; i++) round_fn(s, RC[i]);
}

/* load up to 8 bytes little-endian */
static uint64_t ld(const uint8_t *p, size_t n) {
    uint64_t v = 0;
    size_t i;
    for (i = 0; i < n; i++) v |= (uint64_t)p[i] << (8u * i);
    return v;
}
static void st(uint8_t *p, uint64_t w, size_t n) {
    size_t i;
    for (i = 0; i < n; i++) p[i] = (uint8_t)(w >> (8u * i));
}

/* XOR a partial (< 16 byte) block into S0||S1 and add the 0x01 padding */
static void xor_partial(uint64_t s[5], const uint8_t *b, size_t r) {
    if (r < 8) {
        s[0] ^= ld(b, r) ^ (0x01ULL << (8u * r));
    } else {
        s[0] ^= ld(b, 8);
        s[1] ^= ld(b + 8, r - 8) ^ (0x01ULL << (8u * (r - 8)));
    }
}

/* pt == NULL means ptlen zero bytes.  tag may be NULL (keystream use). */
static void aead(const uint8_t key[16], const uint8_t nonce[16], const uint8_t *pt, size_t ptlen,
                 const uint8_t *ad, size_t adlen, uint8_t *ct, uint8_t *tag) {
    uint64_t s[5], k0 = ld(key, 8), k1 = ld(key + 8, 8);
    size_t off;
    static const uint8_t zero16[16] = {0};
    s[0] = IV;
    s[1] = k0;
    s[2] = k1;
    s[3] = ld(nonce, 8);
    s[4] = ld(nonce + 8, 8);
    permute(s, 12);
    s[3] ^= k0;
    s[4] ^= k1;
    if (adlen) {
        off = 0;
        while (adlen - off >= RATE) {
            s[0] ^= ld(ad + off, 8);
            s[1] ^= ld(ad + off + 8, 8);
            permute(s, 8);
            off += RATE;
        }
        xor_partial(s, ad + off, adlen - off);
        permute(s, 8);
    }
    s[4] ^= DSEP;
    off = 0;
    while (ptlen - off >= RATE) {
        const uint8_t *p = pt ? pt + off : zero16;
        s[0] ^= ld(p, 8);
        s[1] ^= ld(p + 8, 8);
        st(ct + off, s[0], 8);
        st(ct + off + 8, s[1], 8);
        permute(s, 8);
        off += RATE;
    }
    {
        size_t r = ptlen - off;
        uint8_t blk[16] = {0};
        uint8_t tmp[16];
        if (pt && r) memcpy(blk, pt + off, r);
        xor_partial(s, blk, r);
        st(tmp, s[0], 8);
        st(tmp + 8, s[1], 8);
        if (r) memcpy(ct + off, tmp, r);
    }
    if (tag) {
        s[2] ^= k0;
        s[3] ^= k1;
        permute(s, 12);
        st(tag, s[3] ^ k0, 8);
        st(tag + 8, s[4] ^ k1, 8);
    }
}

void hc_ascon_aead_encrypt(const uint8_t key[16], const uint8_t nonce[16], const uint8_t *pt,
                           size_t ptlen, const uint8_t *ad, size_t adlen, uint8_t *out) {
    aead(key, nonce, pt, ptlen, ad, adlen, out, out + ptlen);
}

void hc_ascon_tag(const uint8_t key[16], const uint8_t nonce[16], const uint8_t *ad, size_t adlen,
                  uint8_t tag[16]) {
    aead(key, nonce, NULL, 0, ad, adlen, NULL, tag);
}

int hc_ascon_mac_truncated(const uint8_t key[16], const uint8_t *msg, size_t msglen, unsigned nbits,
                           uint8_t *out) {
    uint8_t stackbuf[256], tag[16];
    uint8_t *buf = stackbuf;
    size_t total = HC_ASCON_MAC_DOMAIN_LEN + msglen;
    if (nbits % 8u != 0u || nbits > 128u || (msglen && !msg)) return -1;
    if (total > sizeof stackbuf) {
        buf = (uint8_t *)malloc(total);
        if (!buf) return -1;
    }
    memcpy(buf, HC_ASCON_MAC_DOMAIN, HC_ASCON_MAC_DOMAIN_LEN);
    if (msglen) memcpy(buf + HC_ASCON_MAC_DOMAIN_LEN, msg, msglen);
    hc_ascon_tag(key, HC_ASCON_NONCE_MAC, buf, total, tag);
    if (buf != stackbuf) free(buf);
    memcpy(out, tag, nbits / 8u);
    return 0;
}

void hc_ascon_keystream(const uint8_t key[16], const uint8_t *domain, size_t domlen, uint8_t *out,
                        size_t nbytes) {
    if (nbytes == 0) return;
    aead(key, HC_ASCON_NONCE_STREAM, NULL, nbytes, domain, domlen, out, NULL);
}
