/* Reader: C99 port of tools/tag_reference/extract.py (recover) with the pilot grid disabled
 * (embed.PILOT_ENABLED == False): the scale comes from the image sizes only.
 *
 *   candidates  = identity, size-ratio rescale, residual crop (corner x1.0, symmetric x0.5)
 *   cheap score = copy-0 confidence of the interpolated LL band
 *   exact path  = restore -> 5/3 IWT -> read copies (erasures) -> SCL decode attempts -> tag
 *   verdict     = the 48-bit Ascon tag, nothing else.
 *
 * Images are row-major uint8.  Bits are one per byte (0/1).  Nothing here allocates more than
 * a few images' worth of memory (about 5 bytes per declared pixel plus the received image). */
#ifndef HUBCORE_EXTRACT_H
#define HUBCORE_EXTRACT_H
#include <stddef.h>
#include <stdint.h>

#include "hubcore/tag_block.h"

#ifdef __cplusplus
extern "C" {
#endif

#define HC_EXT_OK 0
#define HC_EXT_NOMEM (-1)
#define HC_EXT_ARG (-2)

/* Python constants (extract.py / pilot_grid.py) */
#define HC_EXT_MAX_EXACT_CANDIDATES 5
#define HC_EXT_SCORE_SAMPLE_BLOCKS 64
#define HC_EXT_RESIDUAL_MIN_LL 4.0
#define HC_EXT_AXIS_AGREE_TOL 0.01
#define HC_EXT_SCALE_SNAP_TOL 0.03
#define HC_EXT_SCALE_MIN 0.4
#define HC_EXT_SCALE_MAX 2.0
#define HC_EXT_FINE_EXACT_TOP 3
#define HC_EXT_FINE_PRIORITY_CAP 25
#define HC_EXT_FINE_PRIOR_Y (-0.25)
#define HC_EXT_FINE_PRIOR_X (-0.25)

typedef enum {
    HC_CAND_NONE = 0,
    HC_CAND_IDENTITY,       /* "identity" */
    HC_CAND_RESCALE,        /* "rescale recv/decl ..." (size ratio) */
    HC_CAND_CROP_CORNER,    /* "residual crop 1.0x ... (corner)" */
    HC_CAND_CROP_SYMMETRIC, /* "residual crop 0.5x ... (symmetric)" */
    HC_CAND_DECLARED        /* "declared geometry (no offset)": nothing could be read */
} hc_cand_class;

typedef struct {
    hc_cand_class cls;
    double scale_y, beta_y, scale_x, beta_x; /* declared row = scale * received row + beta, LL units
                                                (beta includes the accepted fine offset) */
    double score;                            /* cheap score (coarse candidates) */
} hc_candidate_info;

typedef struct {
    int tag_ok;                  /* the verdict: 1 only if the 48-bit tag verified */
    uint8_t bits[HC_TAG_TOTAL_BITS]; /* the decoded 128 bits (of the last decode if no tag_ok) */
    hc_tag_fields fields;        /* version / hub_id / handle / tag of `bits` */
    hc_candidate_info accepted;  /* the candidate that verified (or the first readable one) */
    int decoded_subset_mask;     /* bit c set: copy c was combined in the verifying decode */
    int n_candidates;            /* coarse candidates generated */
    int n_exact_evals;           /* exact-path evaluations (restore+IWT+read+decode) done */
    int n_decodes;               /* SCL decodes run */
    int no_placement;            /* 1: the declared geometry has no room (Python 'no placement') */
    double llr_confidence;       /* mean |llr| over the 4 copies of the last evaluation */
} hc_recovery;

/* Python extract.recover(img, key, declared_shape).  `img` is h x w (an odd edge is trimmed by
 * one, like Python's _pad_even); declared_h/w are the export geometry (even, > 0).
 * Returns HC_EXT_OK (check out->tag_ok), HC_EXT_NOMEM or HC_EXT_ARG. */
int hc_recover(const uint8_t *img, int h, int w, int declared_h, int declared_w,
               const uint8_t key[16], hc_recovery *out);

/* --- pieces exposed for the tests --------------------------------------------------------- */

/* pilot_grid.resample_affine followed by extract.restore's clip(round()): output pixel (Y, X)
 * comes from (alpha_y*Y + beta_y, alpha_x*X + beta_x) of `img`, bilinear, border clamp, and 0
 * where the source coordinate is < -1.  beta_* are in pixels here (restore passes 2*beta_LL).
 * out is out_h x out_w uint8. */
int hc_resample_affine_u8(const uint8_t *img, int ih, int iw, double alpha_y, double beta_y,
                          double alpha_x, double beta_x, int out_h, int out_w, uint8_t *out);

/* extract.coverage_map for a candidate with scale/beta (LL units), 0/1 out_h x out_w. */
void hc_coverage_map(int ih, int iw, double scale_y, double beta_y, double scale_x, double beta_x,
                     int out_h, int out_w, uint8_t *out);

#ifdef __cplusplus
}
#endif
#endif
