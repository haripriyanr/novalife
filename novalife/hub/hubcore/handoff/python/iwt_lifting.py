"""Lifting-based 5/3 Integer Wavelet Transform (IWT) — Lossless Integer-to-Integer.

Reversible 2D-IWT for FPGA PL implementation.
Uses the 5/3 Le Gall wavelet lifting scheme:
    Detail (High pass): d[n] = x[2n+1] - floor((x[2n] + x[2n+2])/2)
    Smooth (Low pass): s[n] = x[2n] + floor((d[n-1] + d[n] + 2)/4)

The 1D kernels are vectorised over the last axis so a whole image is transformed in
two calls instead of one Python loop per row and per column.  The integer arithmetic
is unchanged (`int32`, arithmetic right shift), so the output is bit-identical to the
scalar version; `sims/../README.md` keeps this the bit-exact target for `iwt_53_core`.
"""
from __future__ import annotations

import numpy as np


def iwt1d_53(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """1D 5/3 Integer Wavelet Transform, vectorised over the last axis.

    Accepts a 1-D signal or an array whose last axis is even; the transform runs along
    that last axis.
    """
    x = np.asarray(x, dtype=np.int32)
    n = x.shape[-1]
    assert n % 2 == 0
    even = x[..., 0::2]
    odd = x[..., 1::2]

    # Predict step (high pass d): next even sample, with the last one repeated.
    next_even = np.empty_like(even)
    next_even[..., :-1] = even[..., 1:]
    next_even[..., -1] = even[..., -1]
    d = odd - ((even + next_even) >> 1)

    # Update step (low pass s): previous detail, with the first one repeated.
    prev_d = np.empty_like(d)
    prev_d[..., 0] = d[..., 0]
    prev_d[..., 1:] = d[..., :-1]
    s = even + ((prev_d + d + 2) >> 2)

    return s, d


def iiwt1d_53(s: np.ndarray, d: np.ndarray) -> np.ndarray:
    """1D Inverse 5/3 Integer Wavelet Transform, vectorised over the last axis."""
    s = np.asarray(s, dtype=np.int32)
    d = np.asarray(d, dtype=np.int32)
    half = s.shape[-1]

    prev_d = np.empty_like(d)
    prev_d[..., 0] = d[..., 0]
    prev_d[..., 1:] = d[..., :-1]
    even = s - ((prev_d + d + 2) >> 2)

    next_even = np.empty_like(even)
    next_even[..., :-1] = even[..., 1:]
    next_even[..., -1] = even[..., -1]
    odd = d + ((even + next_even) >> 1)

    out = np.empty(s.shape[:-1] + (2 * half,), dtype=np.int32)
    out[..., 0::2] = even
    out[..., 1::2] = odd
    return out


def iwt2d_53(img: np.ndarray) -> tuple[np.ndarray, tuple[np.ndarray, np.ndarray, np.ndarray]]:
    """2D 5/3 Integer Wavelet Transform on image (LL, (LH, HL, HH))."""
    img = np.asarray(img, dtype=np.int32)
    h, w = img.shape

    row_s, row_d = iwt1d_53(img)  # (h, w//2), transformed along rows

    # Transform down the columns by transposing so the transform axis is last.
    ll_t, lh_t = iwt1d_53(np.ascontiguousarray(row_s.T))
    hl_t, hh_t = iwt1d_53(np.ascontiguousarray(row_d.T))

    LL = np.ascontiguousarray(ll_t.T)
    LH = np.ascontiguousarray(lh_t.T)
    HL = np.ascontiguousarray(hl_t.T)
    HH = np.ascontiguousarray(hh_t.T)
    assert LL.shape == (h // 2, w // 2)
    return LL, (LH, HL, HH)


def iiwt2d_53(LL: np.ndarray, sub_bands: tuple[np.ndarray, np.ndarray, np.ndarray]) -> np.ndarray:
    """2D Inverse 5/3 Integer Wavelet Transform."""
    LH, HL, HH = sub_bands
    LL = np.asarray(LL, dtype=np.int32)

    # Inverse along columns first (low/high pairs), then along rows.
    row_s = iiwt1d_53(np.ascontiguousarray(LL.T), np.ascontiguousarray(LH.T)).T
    row_d = iiwt1d_53(np.ascontiguousarray(HL.T), np.ascontiguousarray(HH.T)).T
    out = iiwt1d_53(row_s, row_d)

    return np.clip(out, 0, 255).astype(np.uint8)
