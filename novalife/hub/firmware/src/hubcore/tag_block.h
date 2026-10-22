/* 128-bit tag block: build / verify.  Port of tools/tag_reference/tag_block.py.
 *
 * Layout (bit 0 first, MSB-first inside each field):
 *   0..3 version(4)  4..15 hub_id(12)  16..79 handle(64)  80..127 tag(48)
 * Two representations are provided:
 *   bytes: uint8[16], bit 0 is the MSB of byte 0 (== np.packbits of the Python array)
 *   bits : uint8[128], one bit (0/1) per byte, index 0 first (== the Python np.uint8 array,
 *          and what hc_polar_encode takes as its info bits). */
#ifndef HUBCORE_TAG_BLOCK_H
#define HUBCORE_TAG_BLOCK_H
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HC_TAG_VERSION_BITS 4
#define HC_TAG_HUBID_BITS 12
#define HC_TAG_HANDLE_BITS 64
#define HC_TAG_TAG_BITS 48
#define HC_TAG_TOTAL_BITS 128
#define HC_TAG_HEADER_BYTES 10 /* bits 0..79; the MAC input encodes it as 11 bytes (see tag_block.c) */

typedef struct {
    unsigned version;  /* 4 bits */
    unsigned hub_id;   /* 12 bits */
    uint64_t handle;   /* 64 bits */
    uint64_t tag;      /* 48 bits as received */
    uint64_t expected_tag;
    int tag_ok;        /* 1 iff tag == expected_tag */
} hc_tag_fields;

/* 48-bit tag over (version, hub_id, handle).  Python compute_tag. */
uint64_t hc_tag_compute(const uint8_t key[16], unsigned version, unsigned hub_id, uint64_t handle);

/* Build the block.  Return 0, or -1 if a field does not fit (Python asserts). */
int hc_tag_build_bytes(const uint8_t key[16], unsigned version, unsigned hub_id, uint64_t handle,
                       uint8_t block[16]);
int hc_tag_build_bits(const uint8_t key[16], unsigned version, unsigned hub_id, uint64_t handle,
                      uint8_t bits[128]);

void hc_tag_bytes_to_bits(const uint8_t block[16], uint8_t bits[128]);
void hc_tag_bits_to_bytes(const uint8_t bits[128], uint8_t block[16]);

/* Split without verification (any nonzero bit value counts as 1). */
void hc_tag_split_bits(const uint8_t bits[128], hc_tag_fields *f);

/* Verify a recovered block.  Fills f (including tag_ok / expected_tag). */
void hc_tag_verify_bits(const uint8_t bits[128], const uint8_t key[16], hc_tag_fields *f);
void hc_tag_verify_bytes(const uint8_t block[16], const uint8_t key[16], hc_tag_fields *f);

#ifdef __cplusplus
}
#endif
#endif
