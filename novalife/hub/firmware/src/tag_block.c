#include "hubcore/tag_block.h"

#include <string.h>

#include "hubcore/ascon.h"

uint64_t hc_tag_compute(const uint8_t key[16], unsigned version, unsigned hub_id, uint64_t handle) {
    /* Python: message = [len(header)] + header;  mac_truncated(key, MAC_DOMAIN + message, 48)
     * and mac_truncated itself prepends MAC_DOMAIN again, so the AD is DOMAIN||DOMAIN||len||header. */
    uint8_t msg[HC_ASCON_MAC_DOMAIN_LEN + 1 + 11]; /* header as encoded by Python is 1+2+8 = 11 bytes */
    uint8_t t[6];
    uint64_t v = 0;
    int i;
    memcpy(msg, HC_ASCON_MAC_DOMAIN, HC_ASCON_MAC_DOMAIN_LEN);
    msg[HC_ASCON_MAC_DOMAIN_LEN] = 11;
    msg[HC_ASCON_MAC_DOMAIN_LEN + 1] = (uint8_t)(version & 0xFF);
    msg[HC_ASCON_MAC_DOMAIN_LEN + 2] = (uint8_t)((hub_id >> 8) & 0xFF);
    msg[HC_ASCON_MAC_DOMAIN_LEN + 3] = (uint8_t)(hub_id & 0xFF);
    for (i = 0; i < 8; i++) msg[HC_ASCON_MAC_DOMAIN_LEN + 4 + i] = (uint8_t)(handle >> (56 - 8 * i));
    hc_ascon_mac_truncated(key, msg, sizeof msg, HC_TAG_TAG_BITS, t);
    for (i = 0; i < 6; i++) v = (v << 8) | t[i];
    return v;
}

int hc_tag_build_bytes(const uint8_t key[16], unsigned version, unsigned hub_id, uint64_t handle,
                       uint8_t block[16]) {
    uint64_t tag;
    int i;
    if (version >= 16u || hub_id >= 4096u) return -1;
    tag = hc_tag_compute(key, version, hub_id, handle);
    block[0] = (uint8_t)((version << 4) | (hub_id >> 8));
    block[1] = (uint8_t)(hub_id & 0xFF);
    for (i = 0; i < 8; i++) block[2 + i] = (uint8_t)(handle >> (56 - 8 * i));
    for (i = 0; i < 6; i++) block[10 + i] = (uint8_t)(tag >> (40 - 8 * i));
    return 0;
}

void hc_tag_bytes_to_bits(const uint8_t block[16], uint8_t bits[128]) {
    int i;
    for (i = 0; i < 128; i++) bits[i] = (uint8_t)((block[i >> 3] >> (7 - (i & 7))) & 1u);
}

void hc_tag_bits_to_bytes(const uint8_t bits[128], uint8_t block[16]) {
    int i;
    memset(block, 0, 16);
    for (i = 0; i < 128; i++)
        if (bits[i]) block[i >> 3] |= (uint8_t)(1u << (7 - (i & 7)));
}

int hc_tag_build_bits(const uint8_t key[16], unsigned version, unsigned hub_id, uint64_t handle,
                      uint8_t bits[128]) {
    uint8_t b[16];
    if (hc_tag_build_bytes(key, version, hub_id, handle, b) != 0) return -1;
    hc_tag_bytes_to_bits(b, bits);
    return 0;
}

static uint64_t field(const uint8_t *bits, int lo, int hi) {
    uint64_t v = 0;
    int i;
    for (i = lo; i < hi; i++) v = (v << 1) | (bits[i] ? 1u : 0u);
    return v;
}

void hc_tag_split_bits(const uint8_t bits[128], hc_tag_fields *f) {
    f->version = (unsigned)field(bits, 0, 4);
    f->hub_id = (unsigned)field(bits, 4, 16);
    f->handle = field(bits, 16, 80);
    f->tag = field(bits, 80, 128);
    f->expected_tag = 0;
    f->tag_ok = 0;
}

void hc_tag_verify_bits(const uint8_t bits[128], const uint8_t key[16], hc_tag_fields *f) {
    hc_tag_split_bits(bits, f);
    f->expected_tag = hc_tag_compute(key, f->version, f->hub_id, f->handle);
    f->tag_ok = (f->expected_tag == f->tag);
}

void hc_tag_verify_bytes(const uint8_t block[16], const uint8_t key[16], hc_tag_fields *f) {
    uint8_t bits[128];
    hc_tag_bytes_to_bits(block, bits);
    hc_tag_verify_bits(bits, key, f);
}
