/* Embedder: C99 port of tools/tag_reference/embed.py (algorithm.md 3.2, 2026-10-22 revision).
 *
 * 4x4 LL blocks, integer sign-of-Hadamard embedding, no pilot grid, Feistel-permutation
 * placement (Ascon tag as the round function), exact-integer ROI cut, taint = ROI | clipped.
 *
 * Conventions
 *   * Images are row-major uint8, h x w, both even where the 5/3 IWT is involved.
 *   * "Masks" are one byte per cell (0/1), row-major.
 *   * The LL band is row-major int32, ll_h x ll_w (ll = h/2 x w/2 for an image h x w).
 *   * A payload block is 4x4 LL coefficients.  The block grid is nbh x nbw with nbh = ll_h/4,
 *     nbw = ll_w/4.  Python's `block_universe` is (with the pilot grid off) exactly the whole
 *     grid in raster order, so a "block index" bi = brow * nbw + bcol, and the Python block
 *     coordinate (br, bc) in LL units is (brow*4, bcol*4).  -1 means "no block" (an erasure).
 *   * All functions return 0 (HC_EMB_OK) or a negative HC_EMB_* code, except pure functions.
 *
 * For the reader (module C):
 *   hc_placement_run()   -> placement of copies 0..k-1 (block indices, -1 = erasure)
 *   hc_placement_blocks()/hc_blocked_blocks() -> the taint masks (placement / erasure taint)
 *   hc_read_block()      -> hard bit + LLR + delta of one block of a given LL band
 */
#ifndef HUBCORE_EMBED_H
#define HUBCORE_EMBED_H
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- status codes ------------------------------------------------------------------------ */
#define HC_EMB_OK 0
#define HC_EMB_NOMEM (-1)     /* allocation failed */
#define HC_EMB_ARG (-2)       /* bad argument (Python would assert / raise on it) */
#define HC_EMB_CAPACITY (-3)  /* Python ValueError: a copy could not be placed / mark refused */

/* ---- parameters (embed.py constants) ----------------------------------------------------- */
#define HC_EMB_BLOCK 4              /* DCT_BLOCK */
#define HC_EMB_N_COPIES 4           /* N_REGIONS */
#define HC_EMB_CODEWORD 256         /* BLOCKS_PER_REGION */
#define HC_EMB_BITS 128             /* TOTAL_BITS */
#define HC_EMB_CLIP_MARGIN 6
#define HC_EMB_BG_FLOOR 16
#define HC_EMB_ROI_STATS_FLOOR 16
#define HC_EMB_ROI_SUPPORT_LL 1
#define HC_EMB_ROI_CLEARANCE_LL 2
#define HC_EMB_QIM_BASE_DELTA 64
#define HC_EMB_SIGN_MAX_MOVE_T 4
#define HC_EMB_SIGN_LLR_CLIP 8.0
#define HC_EMB_PLACEMENT_ROUNDS 6
#define HC_EMB_MAX_PIXELS (1u << 24) /* roi_cut integer range: n <= 2^24 pixels */

/* ---- ROI (exact integer) ----------------------------------------------------------------- */

/* Smallest pixel value that is ROI (0..256) for pixel statistics n, sum s, sum of squares q
 * (p > mean + 0.2*std in exact integers).  Requires n <= 2^24 (64-bit range). */
int hc_roi_cut(uint64_t n, uint64_t s, uint64_t q);

/* roi_from_image: out[h*w] = 0/1.  `valid` (nullable, h*w) restricts the statistics to covered
 * pixels and masks the result.  Returns HC_EMB_ARG if h*w > HC_EMB_MAX_PIXELS. */
int hc_roi_from_image(const uint8_t *img, int h, int w, const uint8_t *valid, uint8_t *out);

/* floor_background: out = img with every pixel OUTSIDE the ROI raised to >= BG_FLOOR.
 * `out` may equal `img`. */
int hc_floor_background(const uint8_t *img, int h, int w, uint8_t *out);

/* ll_support_roi: roi (h x w) -> m ((h/2) x (w/2)), 1 where any of the 3x3 pixel support is ROI. */
void hc_ll_support_roi(const uint8_t *roi, int h, int w, uint8_t *m);

/* Binary dilation by `m` cells each direction, no wraparound (in place not allowed: out != in
 * unless tmp is used internally; here in-place is supported). */
int hc_dilate(uint8_t *mask, int h, int w, int m);

/* roi_masks: roi_blocks[(ll_h/4)*(ll_w/4)] and, if non-NULL, roi_ll[(h/2)*(w/2)] (Python's
 * roi_ll is always h/2 x w/2 of the image, whatever ll_h/ll_w are). */
int hc_roi_masks(int ll_h, int ll_w, const uint8_t *img, int h, int w, const uint8_t *valid,
                 uint8_t *roi_blocks, uint8_t *roi_ll);

/* clipped_blocks: 1 where the block's pixel support touches a uint8 clipping level. */
void hc_clipped_blocks(int ll_h, int ll_w, const uint8_t *img, int h, int w, uint8_t *out);

/* placement_blocks: ROI | clipping.  This is the taint hc_placement_* is allowed to see.
 * `valid` (nullable, h*w): see Python placement_blocks (uncovered pixels read as 128 for the
 * clipping test and are excluded from the ROI statistics). */
int hc_placement_blocks(int ll_h, int ll_w, const uint8_t *img, int h, int w,
                        const uint8_t *valid, uint8_t *out);

/* undercovered_blocks: 1 where < 75% of the block's 16x16 pixel support is covered
 * (coverage is a 0/1 mask of the image, h x w). */
void hc_undercovered_blocks(int ll_h, int ll_w, const uint8_t *coverage, int h, int w,
                            uint8_t *out);

/* blocked_blocks: placement taint, plus (when coverage != NULL) undercovered blocks, i.e. the
 * decoder's erasure taint.  With coverage == NULL equals hc_placement_blocks(valid=NULL). */
int hc_blocked_blocks(int ll_h, int ll_w, const uint8_t *img, int h, int w,
                      const uint8_t *coverage, uint8_t *out);

/* region_capacities: out[c] = max(0, free - c*256) for c in 0..3, free = untainted blocks. */
void hc_region_capacities(const uint8_t *blocked, int nbh, int nbw,
                          int32_t out[HC_EMB_N_COPIES]);

/* ---- keyed placement (Feistel permutation, Ascon tag round function) ---------------------- */

int hc_feistel_half_bits(uint64_t m);
/* Block index that slot `slot` maps to (m >= 1, slot < m).  Python placement_permute. */
uint32_t hc_placement_permute(const uint8_t key[16], uint32_t m, uint32_t slot);
/* Whole permutation table tbl[0..m-1] (an optional speed-up for the reader). */
void hc_perm_table_build(const uint8_t key[16], uint32_t m, uint32_t *tbl);

/* Placement of copies 0..ncopies-1 (copy-major, one shared `used` pool), n bits each (n=256).
 * out[c*n + i] = block index or -1.  `blocked` = nbh*nbw taint (placement taint).
 * allow_erasures=0 (encoder): stops at the first copy that cannot complete; *copies_done is
 * the number of complete copies (rows >= copies_done are left untouched).  allow_erasures=1
 * (decoder): never fails, missing positions are -1 and *copies_done == ncopies.
 * `perm` (nullable): table from hc_perm_table_build(key, nbh*nbw, .) used instead of
 * recomputing the permutation.  Returns HC_EMB_OK / NOMEM / ARG (m == 0, ncopies out of range). */
int hc_placement_run(const uint8_t key[16], int nbh, int nbw, const uint8_t *blocked, int n,
                     int ncopies, int allow_erasures, const uint32_t *perm, int32_t *out,
                     int *copies_done);

/* Python placement_map for ONE region: out[n].  Returns HC_EMB_CAPACITY where Python raises
 * ValueError (only when allow_erasures == 0). */
int hc_placement_map(const uint8_t key[16], int nbh, int nbw, int region, const uint8_t *blocked,
                     int n, int allow_erasures, const uint32_t *perm, int32_t *out);

/* ---- the bit in one block ----------------------------------------------------------------- */

/* Integer local variance around block (r, c) of an ll_h x ll_w band (window +-3), 0 if the
 * window is empty.  = int(perceptual_mask.compute_dsp48_variance(...)). */
int64_t hc_local_variance(const int32_t *ll, int ll_h, int ll_w, int r, int c);
/* isqrt(local_variance) */
int64_t hc_local_std(const int32_t *ll, int ll_h, int ll_w, int r, int c);
uint64_t hc_isqrt(uint64_t v);
/* 64 + (5*std)>>3, forced even */
int64_t hc_qim_delta(int64_t std);

/* Hadamard projection of a 4x4 block (row stride `stride`). */
int64_t hc_block_projection(const int32_t *blk, int stride);
int64_t hc_sign_threshold(int64_t delta);
int64_t hc_embed_error(int64_t v, int bit, int64_t delta);
/* Write the quantised 4x4 block (v' = v + e exactly) to dst (stride dstride); src may be dst. */
void hc_quantize_block(const int32_t *src, int sstride, int bit, int64_t delta, int32_t *dst,
                       int dstride);
/* Hard bit (v < 0) and LLR (positive = bit 0) of a 4x4 block for a given delta. */
double hc_read_block_llr(const int32_t *blk, int stride, int64_t delta, int *bit);
double hc_block_confidence(const int32_t *blk, int stride, int64_t delta);

/* Reader helper: read block (r, c) (LL units) of `ll`: delta from the local variance, then bit
 * and LLR.  HC_EMB_ARG if the 4x4 block is not fully inside the band (Python would raise). */
int hc_read_block(const int32_t *ll, int ll_h, int ll_w, int r, int c, int *bit, double *llr,
                  int64_t *delta);

/* ---- mark --------------------------------------------------------------------------------- */

typedef struct {
    int max_abs_change_inside_drawn_roi;
    int max_abs_change_inside_algorithm_roi;
    int max_abs_change_outside_roi;
    double mean_abs_change_outside_roi;
    int support_rule_violations;
    int32_t blocks_available_per_region[HC_EMB_N_COPIES];
    int32_t blocks_blocked_by_clipping_per_region[HC_EMB_N_COPIES];
    int blocks_used_per_region;
    int copies_written;
    int pixels_clipped_after_inverse;  /* mirrors Python: counted on the already clipped uint8
                                          array, so always 0 */
    int pixels_actually_clipped;       /* extra (not in Python): pixels the inverse put outside
                                          0..255 before clipping */
    int ll_h, ll_w;
    double drawn_vs_algorithm_roi_jaccard;
    uint8_t codeword[HC_EMB_CODEWORD];
    /* On HC_EMB_CAPACITY (mark refused): capacity if the ROI taint were ignored / if the
     * clipping taint were ignored, as in the Python ValueError text. */
    int32_t refused_clip_only_capacity0;
    int32_t refused_roi_only_capacity0;
    /* placements[c*256 + i] = block index (see top of file); filled for c < copies_written. */
    int32_t placements[HC_EMB_N_COPIES * HC_EMB_CODEWORD];
} hc_mark_info;

/* embed.mark(): mark `cover` (h x w, even) with the 128 bit block (one bit per byte).
 * `drawn_roi` (nullable) is only used for the report.  `marked` (h*w) may not alias `cover`.
 * Returns HC_EMB_CAPACITY when Python raises ValueError (cannot place one copy; info->blocks_
 * available_per_region and the refused_* fields are filled), HC_EMB_ARG for odd/zero dimensions.
 * The Python round-trip self-check (info["round_trip_*"]) is the reader's job and is NOT done. */
int hc_mark(const uint8_t *cover, int h, int w, const uint8_t *drawn_roi, const uint8_t key[16],
            const uint8_t block[HC_EMB_BITS], uint8_t *marked, hc_mark_info *info);

#ifdef __cplusplus
}
#endif
#endif
