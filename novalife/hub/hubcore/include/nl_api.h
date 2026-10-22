/* nl_api.h -- the ONE interface a C implementation of NovaLife must provide, so the golden test
 * harness (run_golden.c) can check it against the Python reference.  Plain C99, no platform code.
 *
 * Conventions
 *   image  : row-major uint8, h rows x w columns, h and w EVEN.
 *   key    : 16 bytes.
 *   block  : the 128-bit tag block as 16 bytes, MSB first = numpy.packbits(build_block(...)).
 *            Layout: version(4) | hub_id(12) | handle(64) | tag(48).
 */
#ifndef NL_API_H
#define NL_API_H
#include <stdint.h>
#include <stddef.h>

typedef struct {
    int copies_written;      /* embed.mark info["copies_written"] */
    int capacity[4];         /* info["blocks_available_per_region"] (free 4x4 LL blocks per copy) */
} nl_mark_info;

/* Bit-identical to Python embed.mark(cover, drawn_roi, bits, key) -> marked uint8 (h*w bytes).
 * Returns 0 ok; 1 refused (Python raises ValueError: cannot place one copy);
 * negative: error (alloc, bad size). `marked` is caller-provided, h*w bytes. */
int nl_mark(const uint8_t *cover, int h, int w, const uint8_t key[16], const uint8_t block[16],
            uint8_t *marked, nl_mark_info *info);

typedef struct {
    int      tag_ok;         /* 1 iff the 48-bit tag verified */
    uint8_t  block[16];      /* the recovered 128 bits (valid when tag_ok) */
    int      version;
    int      hub_id;
    uint64_t handle;
    int      candidate;      /* index of the accepted geometry candidate, -1 if none */
} nl_recover_result;

/* Same decisions as Python extract.recover(img, key, declared_shape).  `decl_h/decl_w` are the
 * declared export size.  Returns 0 (result filled, tag_ok may be 0) or negative on error. */
int nl_recover(const uint8_t *img, int h, int w, int decl_h, int decl_w, const uint8_t key[16],
               nl_recover_result *out);

#endif
