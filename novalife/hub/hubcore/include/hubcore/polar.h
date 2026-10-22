/* Polar code N=256, K=128 and SCL (L=8) decoder.  Port of
 * tools/stego_research/sims/polar_codec.py.  Bit arrays are one bit per byte (0/1). */
#ifndef HUBCORE_POLAR_H
#define HUBCORE_POLAR_H
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HC_POLAR_N 256
#define HC_POLAR_K 128
#define HC_POLAR_L 8

/* Python RELIABLE_INDICES: info bit i sits at u[hc_polar_info_index[i]] (order matters). */
extern const uint16_t hc_polar_info_index[HC_POLAR_K];

/* info[128] (0/1 bytes) -> codeword[256] (0/1 bytes).  Python polar_encode. */
void hc_polar_encode(const uint8_t info[HC_POLAR_K], uint8_t code[HC_POLAR_N]);

/* SCL decode, list size 8, channel LLRs (positive = bit 0, Python convention).
 * Writes info[128] and the best path metric.  Returns 0, or -1 on allocation failure.
 * Python polar_scl_decode(llr). */
int hc_polar_scl_decode(const double llr[HC_POLAR_N], uint8_t info[HC_POLAR_K], double *pm_out);

#ifdef __cplusplus
}
#endif
#endif
