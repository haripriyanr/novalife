"""Perceptual Mask Engine.

Computes DICOM ROI-aware perceptual embedding mask on 2D-DWT sub-bands using DSP48-accurate
fixed-point local variance calculation: σ² = E[X²] - E[X]².
"""
from __future__ import annotations

import numpy as np
import pywt

N = 512
BLOCK_SIZE = 8

# Variance threshold and the block length the PL block-mask unit is built for.
VAR_THRESHOLD = 1
HW_BLOCK = 16


def compute_dsp48_variance(block: np.ndarray) -> float:
    """Fixed-point DSP48-accurate local variance: σ² = E[X²] - E[X]² in Q16.8."""
    # Convert to 16-bit fixed point simulating DSP48 A*B MAC
    b = block.astype(np.int64)
    num = b.size
    if num == 0:
        # No samples: there is no variance to measure.  Returning 0 (rather than reaching
        # `sum_x // num` and emitting a numpy divide-by-zero warning) keeps the frozen
        # contract total.  A caller with an empty window is asking about a block that is
        # not in its image -- `embed.local_std` guards that case and says so.
        return 0.0
    sum_x = np.sum(b)
    sum_x2 = np.sum(b * b)

    mean_x = sum_x // num
    mean_x2 = sum_x2 // num
    var = mean_x2 - (mean_x * mean_x)
    return max(0.0, float(var))


def generate_perceptual_mask(img: np.ndarray, roi_mask: np.ndarray) -> dict[str, np.ndarray]:
    """Generate perceptual embedding masks for 2D-DWT sub-bands (LH, HL, HH).
    
    Returns dict containing sub-band masks (256x256 uint8 arrays where 1 = embeddable, 0 = protected).
    """
    coeffs = pywt.dwt2(img.astype(np.float64), 'db1')
    LL, (LH, HL, HH) = coeffs
    
    # Downsample ROI mask to 256x256 (sub-band resolution)
    # If any pixel in 2x2 block is ROI (1), mark sub-band region as ROI protected
    sub_height, sub_width = LL.shape
    sub_roi = np.zeros((sub_height, sub_width), dtype=np.uint8)
    for r in range(sub_height):
        for c in range(sub_width):
            sub_roi[r, c] = 1 if np.any(roi_mask[2*r:2*r+2, 2*c:2*c+2] > 0) else 0

    masks = {}
    for band_name, band_data in [('LH', LH), ('HL', HL), ('HH', HH)]:
        mask = np.zeros((sub_height, sub_width), dtype=np.uint8)
        # Process in 4x4 tiles (simulating 8x8 image blocks)
        for r in range(0, sub_height, 4):
            for c in range(0, sub_width, 4):
                tile = band_data[r:r+4, c:c+4]
                tile_roi = sub_roi[r:r+4, c:c+4]
                var = compute_dsp48_variance(tile)
                
                # Condition for embedding: NOT in ROI (tile_roi == 0) AND high texture (var >= threshold)
                # Or background non-ROI region with moderate texture
                if np.mean(tile_roi) < 0.5 and var > 1.0:
                    mask[r:r+4, c:c+4] = 1
        masks[band_name] = mask
        
    return masks


def mask_block_decision(block, roi):
    """Integer contract for the PL block-mask unit (`vivado/ip_repo/perceptual_mask_core`).

    This is the *same decision* `generate_perceptual_mask` makes for a 4x4 tile, written
    without floats so a bit-exact hardware check is possible:

        var  = compute_dsp48_variance(block)              (>= 0, integer valued)
        mask = 1 iff  roi_count * 2 < BLOCK  and  var > VAR_THRESHOLD

    `roi_count * 2 < BLOCK` is `np.mean(tile_roi) < 0.5` from the loop above (the ROI rule is
    a *majority* test, not "any"); `var > VAR_THRESHOLD` is `var > 1.0`.  Returns `(var, mask)`.
    """
    b = np.asarray(block, dtype=np.int64).ravel()
    r = np.asarray(roi, dtype=np.int64).ravel()
    if b.size != r.size:
        raise ValueError("block and roi must have the same length")
    n = int(b.size)
    var = int(compute_dsp48_variance(b))
    roi_count = int(np.sum(r > 0))
    mask = 1 if (roi_count * 2 < n and var > VAR_THRESHOLD) else 0
    return var, mask
