/* handle_gen.h -- 64-bit record handles for marked images.
 *
 * A handle is the pointer a marked image carries to its record, so it must be unpredictable (nobody
 * may guess another patient's handle) and must never repeat (the registry is keyed by it).  The PS has
 * no hardware RNG, so a handle is a keyed PRF output:
 *
 *   tag    = Ascon-AEAD128(K, nonce "NovaLife/handle1", pt = empty,
 *                          ad = chain || counter || now || jitter || jitter_n || salt)
 *   handle = first 8 bytes of tag (big-endian), chain = tag
 *
 * Unpredictable because K never leaves the board.  Unique because the salt is the cloud job id (a
 * server-generated random UUID, one per job); the chain, counter, time and the interrupt-timing
 * jitter keep handles distinct when there is no salt (local /embed).  The nonce differs from the tag
 * MAC's NONCE_MAC, so the same key never produces a handle and a tag over the same input.
 *
 * Not thread-safe: callers serialise (image_worker runs one job at a time).  hg_add_entropy() is safe
 * to call from an interrupt.
 */
#ifndef HANDLE_GEN_H
#define HANDLE_GEN_H

#include <stdint.h>

/* Mix one timing sample (e.g. the global timer at an RX interrupt) into the jitter pool. */
void hg_add_entropy(uint32_t sample);

/* Next handle.  salt may be NULL; at most 64 bytes of it are used.  now: any free-running counter. */
uint64_t hg_next_handle(const uint8_t key[16], const char *salt, uint64_t now);

#endif /* HANDLE_GEN_H */
