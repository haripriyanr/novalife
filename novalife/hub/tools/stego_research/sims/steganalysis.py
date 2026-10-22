"""3rd-Party Stegananalysis Test Suite.

Evaluates stego image resistance against industry-standard steganalysis attacks:
1. Chi-Square (χ²) Histogram Attack (Pair of Values PoV detection)
2. Sample Pair Analysis (SPA) hidden capacity estimation
3. RS Stegananalysis (Regular/Singular Group symmetry ratio)
4. KL-Divergence Histogram Difference
"""
from __future__ import annotations

import numpy as np
from scipy import stats


def chi_square_attack(img: np.ndarray, block_size: int = 64) -> dict[str, float]:
    """Chi-Square (χ²) Histogram Stegananalysis Attack.
    
    Returns:
        p_value: Probability that image contains LSB/QIM steganography.
                 p_value < 0.05 => Steganography DETECTED
                 p_value > 0.90 => Undetectable (Cover-like)
        detected: boolean
    """
    flat = img.flatten()
    # Count frequencies of Pairs of Values (PoV): (2k, 2k+1)
    counts = np.bincount(flat, minlength=256)
    
    chi2_stat = 0.0
    dof = 0
    for i in range(0, 256, 2):
        observed_even = counts[i]
        observed_odd = counts[i + 1]
        expected = (observed_even + observed_odd) / 2.0
        
        if expected > 5.0:  # Valid Chi-square bin threshold
            chi2_stat += ((observed_even - expected) ** 2) / expected + ((observed_odd - expected) ** 2) / expected
            dof += 1

    p_value = float(1.0 - stats.chi2.cdf(chi2_stat, df=dof)) if dof > 0 else 1.0
    return {
        "chi2_stat": float(chi2_stat),
        "p_value": float(p_value),
        "detected": bool(p_value < 0.05)
    }


def sample_pair_analysis(img: np.ndarray) -> dict[str, float]:
    """Sample Pair Analysis (SPA) Stegananalysis.
    
    Estimates hidden message embedding rate α in [0, 1].
    α ≈ 0.00 => Undetectable
    α > 0.10 => Steganography DETECTED
    """
    flat = img.flatten().astype(np.int64)
    u = flat[:-1]
    v = flat[1:]
    
    diff = v - u
    
    # Count sample pair categories
    # P: u is even, v == u or v == u + 1
    # X: u is odd, v == u or v == u - 1
    # Y: sample pairs modified by LSB flipping
    p = np.sum((u % 2 == 0) & ((v == u) | (v == u + 1)))
    x = np.sum((u % 2 == 1) & ((v == u) | (v == u - 1)))
    
    total_pairs = len(diff)
    if total_pairs == 0:
        return {"estimated_rate": 0.0, "detected": False}

    # Quadratic equation for estimated embedding rate alpha
    gamma = float((p - x) / total_pairs)
    estimated_rate = float(max(0.0, min(1.0, 2.0 * abs(gamma))))
    
    return {
        "estimated_rate": round(estimated_rate, 4),
        "detected": bool(estimated_rate > 0.08)
    }


def rs_steganalysis(img: np.ndarray) -> dict[str, float]:
    """RS Stegananalysis (Fridrich et al.).
    
    Measures ratio asymmetry between Regular (R_m, R_-m) and Singular (S_m, S_-m) groups.
    |Rm - R-m| > 0.05 => Steganography DETECTED
    """
    flat = img.flatten().astype(np.int64)
    n = len(flat) // 4 * 4
    blocks = flat[:n].reshape(-1, 4)

    mask_m = np.array([0, 1, 1, 0])
    mask_neg_m = np.array([0, -1, -1, 0])

    def variation(b):
        return np.sum(np.abs(b[:, 1:] - b[:, :-1]), axis=1)

    def flip(b, mask):
        out = b.copy()
        for i in range(4):
            if mask[i] == 1:
                out[:, i] = np.where(out[:, i] % 2 == 0, out[:, i] + 1, out[:, i] - 1)
            elif mask[i] == -1:
                out[:, i] = np.where(out[:, i] % 2 == 0, out[:, i] - 1, out[:, i] + 1)
        return out

    f_orig = variation(blocks)
    f_m = variation(flip(blocks, mask_m))
    f_neg_m = variation(flip(blocks, mask_neg_m))

    r_m = np.mean(f_m > f_orig)
    s_m = np.mean(f_m < f_orig)
    r_neg_m = np.mean(f_neg_m > f_orig)
    s_neg_m = np.mean(f_neg_m < f_orig)

    rm_diff = abs(float(r_m - r_neg_m))
    sm_diff = abs(float(s_m - s_neg_m))

    return {
        "rm_diff": round(rm_diff, 4),
        "sm_diff": round(sm_diff, 4),
        "detected": bool(rm_diff > 0.05 or sm_diff > 0.05)
    }


def kl_divergence(cover_img: np.ndarray, stego_img: np.ndarray) -> float:
    """Kullback-Leibler (KL) Divergence between cover & stego pixel distributions."""
    p_cover = np.bincount(cover_img.flatten(), minlength=256).astype(np.float64) + 1e-9
    p_stego = np.bincount(stego_img.flatten(), minlength=256).astype(np.float64) + 1e-9

    p_cover /= np.sum(p_cover)
    p_stego /= np.sum(p_stego)

    kl_div = np.sum(p_stego * np.log(p_stego / p_cover))
    return float(kl_div)
