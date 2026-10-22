/* 5/3 integer wavelet transform (lifting), 2D forward/inverse.
 * Port of tools/stego_research/sims/iwt_lifting.py (iwt2d_53 / iiwt2d_53).
 * Images are row-major int32.  h and w must be even and >= 2.
 * Arithmetic wraps modulo 2^32 exactly like numpy int32; right shifts are floor shifts. */
#ifndef HUBCORE_IWT_H
#define HUBCORE_IWT_H
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Forward.  LL, LH, HL, HH each (h/2) x (w/2) row-major, caller allocated.
 * Python: LL,(LH,HL,HH) = iwt2d_53(img).  Returns 0, or -1 (bad dims / malloc). */
int hc_iwt2d_53(const int32_t *img, int h, int w, int32_t *LL, int32_t *LH, int32_t *HL,
                int32_t *HH);

/* Inverse, unclipped int32 output (h x w, h = 2*h2, w = 2*w2): exact inverse of hc_iwt2d_53. */
int hc_iiwt2d_53_raw(const int32_t *LL, const int32_t *LH, const int32_t *HL, const int32_t *HH,
                     int h2, int w2, int32_t *out);

/* Inverse + clip to [0,255]: values equal the Python iiwt2d_53 (which returns uint8). */
int hc_iiwt2d_53(const int32_t *LL, const int32_t *LH, const int32_t *HL, const int32_t *HH,
                 int h2, int w2, int32_t *out);

#ifdef __cplusplus
}
#endif
#endif
