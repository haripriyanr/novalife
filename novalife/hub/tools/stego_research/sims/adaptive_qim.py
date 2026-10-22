"""Adaptive 2D-DWT QIM Embedder & Extractor.

Implements hardware-accurate adaptive Quantization Index Modulation in Q8.8 fixed-point math:
    Δ_hw = base_Δ + α × σ²_local
HMAC-SHA256 pseudo-random coefficient placement order across sub-bands.
"""
from __future__ import annotations

import hashlib
import hmac
import numpy as np
import pywt

BASE_DELTA = 36.0  # Increased for robust integer rounding tolerance after IDWT
ALPHA = 0.10
KEY = b"novalife-zynq7010-v2-stego-key"


def compute_adaptive_delta(ll_subband: np.ndarray, r: int, c: int) -> float:
    """Compute Δ_hw from LL sub-band local variance (invariant across embed & extract)."""
    r_start, r_end = max(0, r - 1), min(ll_subband.shape[0], r + 2)
    c_start, c_end = max(0, c - 1), min(ll_subband.shape[1], c + 2)
    local_var = float(np.var(ll_subband[r_start:r_end, c_start:c_end]))
    
    delta = BASE_DELTA + ALPHA * np.sqrt(local_var)
    delta_q88 = np.round(delta * 256.0) / 256.0
    return max(24.0, float(delta_q88))


def qim_embed_coeff(coeff: float, bit: int, delta: float) -> float:
    """Embed single bit into DWT coefficient using QIM."""
    if bit == 0:
        return np.round(coeff / delta) * delta
    else:
        return np.round((coeff - delta / 2.0) / delta) * delta + delta / 2.0


def qim_extract_coeff(coeff: float, delta: float) -> int:
    """Extract single bit from DWT coefficient using QIM."""
    d0 = abs(coeff - np.round(coeff / delta) * delta)
    d1 = abs(coeff - (np.round((coeff - delta / 2.0) / delta) * delta + delta / 2.0))
    return 0 if d0 <= d1 else 1


def keyed_embedding_locations(masks: dict[str, np.ndarray], num_bits: int) -> list[tuple[str, int, int]]:
    """Determine HMAC-SHA256 keyed ordering of embeddable (mask==1) sub-band locations."""
    candidates = []
    for band_name in ['LH', 'HL', 'HH']:
        mask = masks[band_name]
        rows, cols = np.where(mask == 1)
        for r, c in zip(rows, cols):
            candidates.append((band_name, int(r), int(c)))

    if len(candidates) < num_bits:
        raise ValueError(f"Insufficient mask embedding capacity: need {num_bits} bits, have {len(candidates)}")

    keyed_vals = []
    for idx, (b, r, c) in enumerate(candidates):
        h = hmac.new(KEY, f"{b}:{r}:{c}:{idx}".encode(), hashlib.sha256).digest()
        keyed_vals.append((h, (b, r, c)))
    
    keyed_vals.sort(key=lambda x: x[0])
    return [pos for _, pos in keyed_vals[:num_bits]]


def dwt_qim_embed(img: np.ndarray, masks: dict[str, np.ndarray], bits: np.ndarray) -> np.ndarray:
    """Embed bitstream into image using Adaptive 2D-DWT QIM.
    
    Returns:
        stego_img: 512x512 uint8 image
    """
    coeffs = pywt.dwt2(img.astype(np.float64), 'db1')
    LL, (LH, HL, HH) = coeffs
    sub_bands = {'LH': LH.copy(), 'HL': HL.copy(), 'HH': HH.copy()}

    locations = keyed_embedding_locations(masks, len(bits))
    
    for bit, (band_name, r, c) in zip(bits, locations):
        band = sub_bands[band_name]
        delta = compute_adaptive_delta(LL, r, c)
        band[r, c] = qim_embed_coeff(band[r, c], int(bit), delta)

    stego_coeffs = LL, (sub_bands['LH'], sub_bands['HL'], sub_bands['HH'])
    stego_img = pywt.idwt2(stego_coeffs, 'db1')
    return np.clip(stego_img, 0, 255).astype(np.uint8)


def dwt_qim_extract(stego_img: np.ndarray, masks: dict[str, np.ndarray], num_bits: int) -> tuple[np.ndarray, np.ndarray]:
    """Extract bitstream & raw LLRs from stego image using Adaptive 2D-DWT QIM."""
    coeffs = pywt.dwt2(stego_img.astype(np.float64), 'db1')
    LL, (LH, HL, HH) = coeffs
    sub_bands = {'LH': LH, 'HL': HL, 'HH': HH}

    locations = keyed_embedding_locations(masks, num_bits)
    extracted_bits = []
    llrs = []

    for band_name, r, c in locations:
        band = sub_bands[band_name]
        delta = compute_adaptive_delta(LL, r, c)
        coeff = band[r, c]
        
        d0 = abs(coeff - np.round(coeff / delta) * delta)
        d1 = abs(coeff - (np.round((coeff - delta / 2.0) / delta) * delta + delta / 2.0))
        
        # Soft LLR: positive for 0, negative for 1
        llr = float((d1 - d0) / (delta / 4.0))
        llrs.append(llr)
        
        bit = 0 if d0 <= d1 else 1
        extracted_bits.append(bit)

    return np.array(extracted_bits, dtype=np.uint8), np.array(llrs, dtype=np.float64)
