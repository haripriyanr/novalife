/* Ascon-AEAD128 (NIST SP 800-232).  Port of tools/tag_reference/ascon_primitives.py. */
#ifndef HUBCORE_ASCON_H
#define HUBCORE_ASCON_H
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HC_ASCON_KEY_BYTES 16
#define HC_ASCON_NONCE_BYTES 16
#define HC_ASCON_TAG_BYTES 16

/* Fixed, published nonces (same as Python NONCE_MAC / NONCE_STREAM). */
extern const uint8_t HC_ASCON_NONCE_MAC[16];
extern const uint8_t HC_ASCON_NONCE_STREAM[16];
/* "Novalife/tag-block/v1" */
extern const uint8_t HC_ASCON_MAC_DOMAIN[21];
#define HC_ASCON_MAC_DOMAIN_LEN 21

/* Encrypt.  out must hold ptlen + 16 bytes; writes ciphertext then the 16-byte tag.
 * pt may be NULL only when ptlen == 0.  ad may be NULL only when adlen == 0.
 * Equivalent of Python ascon_aead_encrypt(key, nonce, pt, ad). */
void hc_ascon_aead_encrypt(const uint8_t key[16], const uint8_t nonce[16],
                           const uint8_t *pt, size_t ptlen,
                           const uint8_t *ad, size_t adlen, uint8_t *out);

/* Tag only: encrypt of the empty plaintext (the MAC construction). */
void hc_ascon_tag(const uint8_t key[16], const uint8_t nonce[16],
                  const uint8_t *ad, size_t adlen, uint8_t tag[16]);

/* Python mac_truncated(key, message, nbits): tag of (NONCE_MAC, empty pt,
 * ad = MAC_DOMAIN || message), first nbits/8 bytes written to out.
 * nbits must be a multiple of 8 and <= 128.  Returns 0 on success, -1 on bad
 * argument or allocation failure (message longer than the internal 256-byte buffer
 * uses malloc). */
int hc_ascon_mac_truncated(const uint8_t key[16], const uint8_t *msg, size_t msglen,
                           unsigned nbits, uint8_t *out);

/* Python keystream(key, domain, nbytes): ciphertext of nbytes zero bytes under
 * NONCE_STREAM with ad = domain (first nbytes bytes).  out must hold nbytes. */
void hc_ascon_keystream(const uint8_t key[16], const uint8_t *domain, size_t domlen,
                        uint8_t *out, size_t nbytes);

#ifdef __cplusplus
}
#endif
#endif
