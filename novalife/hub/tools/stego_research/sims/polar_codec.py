"""Polar Code Encoder & SCL Decoder L=8 (Arıkan Standard).

Systematic/Non-systematic Polar Code (N=256, K=128) with Successive Cancellation List (SCL) Decoder L=8.
Capacity-achieving channel coding for FPGA steganography pipeline.
"""
from __future__ import annotations

import numpy as np

N = 256
K = 128
L = 8  # SCL List size confirmed


def bhattacharyya_reliability(n: int, design_snr_db: float = 2.0) -> np.ndarray:
    """Compute Bhattacharyya reliability order for N bit channels."""
    z = np.zeros(n)
    sigma = 10 ** (-design_snr_db / 20.0)
    z[0] = np.exp(-1.0 / (2 * sigma**2))
    
    length = 1
    while length < n:
        for i in range(length):
            t = z[i]
            z[i] = 2 * t - t**2
            z[i + length] = t**2
        length *= 2

    rev_indices = np.array([int(f"{i:0{int(np.log2(n))}b}"[::-1], 2) for i in range(n)])
    return np.argsort(z[rev_indices])


RELIABLE_INDICES = bhattacharyya_reliability(N)[:K]
FROZEN_MASK = np.ones(N, dtype=bool)
FROZEN_MASK[RELIABLE_INDICES] = False


def polar_transform(u: np.ndarray) -> np.ndarray:
    """Fast polar transform u -> x = u * F^tensor(n) in O(N log N)."""
    x = u.copy().astype(np.uint8)
    n = len(u)
    step = 1
    while step < n:
        for i in range(0, n, 2 * step):
            for j in range(i, i + step):
                x[j] = x[j] ^ x[j + step]
        step *= 2
    return x


def polar_encode(info_bits: np.ndarray) -> np.ndarray:
    """Polar Encoder (N=256, K=128). Map info_bits -> u -> x."""
    assert len(info_bits) == K, f"Expected {K} info bits, got {len(info_bits)}"
    u = np.zeros(N, dtype=np.uint8)
    u[RELIABLE_INDICES] = info_bits
    return polar_transform(u)


def compute_f(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Vectorized min-sum F operation."""
    return np.sign(a) * np.sign(b) * np.minimum(np.abs(a), np.abs(b))


def compute_g(a: np.ndarray, b: np.ndarray, u: np.ndarray) -> np.ndarray:
    """Vectorized G operation."""
    return b + (1.0 - 2.0 * u) * a


class PathState:
    """Tree state for single SCL decoding path."""
    def __init__(self, m: int, n: int, channel_llrs: np.ndarray):
        self.m = m
        self.n = n
        self.llrs = np.zeros((m + 1, n), dtype=np.float64)
        self.bits = np.zeros((m + 1, n), dtype=np.uint8)
        self.llrs[m] = channel_llrs.copy()
        self.u_hat = np.zeros(n, dtype=np.uint8)
        self.pm = 0.0

    def copy(self):
        p = PathState(self.m, self.n, self.llrs[self.m])
        p.llrs = self.llrs.copy()
        p.bits = self.bits.copy()
        p.u_hat = self.u_hat.copy()
        p.pm = self.pm
        return p


class SCLDecoder:
    """Exact Arıkan SCL Decoder using 2D tree array representation."""
    def __init__(self, n: int = N, k: int = K, l_size: int = L):
        self.n = n
        self.k = k
        self.m = int(np.log2(n))
        self.l_size = l_size

    def decode_scalar(self, channel_llrs: np.ndarray) -> tuple[np.ndarray, float]:
        m = self.m
        n = self.n
        paths = [PathState(m, n, channel_llrs)]

        def update_llrs(path: PathState, leaf_idx: int):
            for stage in range(m - 1, -1, -1):
                block_len = 2**stage
                step = 2 * block_len
                node_offset = (leaf_idx // step) * step
                
                if (leaf_idx // block_len) % 2 == 0:
                    # Left node: F function
                    a = path.llrs[stage + 1, node_offset : node_offset + block_len]
                    b = path.llrs[stage + 1, node_offset + block_len : node_offset + step]
                    path.llrs[stage, node_offset : node_offset + block_len] = compute_f(a, b)
                else:
                    # Right node: G function
                    a = path.llrs[stage + 1, node_offset : node_offset + block_len]
                    b = path.llrs[stage + 1, node_offset + block_len : node_offset + step]
                    u_left = path.bits[stage, node_offset : node_offset + block_len]
                    path.llrs[stage, node_offset + block_len : node_offset + step] = compute_g(a, b, u_left)

        def propagate_bits(path: PathState, leaf_idx: int, bit_val: int):
            path.bits[0, leaf_idx] = bit_val
            path.u_hat[leaf_idx] = bit_val

            for stage in range(m):
                block_len = 2**stage
                step = 2 * block_len
                node_offset = (leaf_idx // step) * step
                
                if (leaf_idx // block_len) % 2 == 1:
                    # Combine left and right bits into parent stage
                    l_val = path.bits[stage, node_offset : node_offset + block_len]
                    r_val = path.bits[stage, node_offset + block_len : node_offset + step]
                    path.bits[stage + 1, node_offset : node_offset + block_len] = l_val ^ r_val
                    path.bits[stage + 1, node_offset + block_len : node_offset + step] = r_val

        for i in range(n):
            for p in paths:
                update_llrs(p, i)

            is_frozen = FROZEN_MASK[i]
            next_paths = []

            for p in paths:
                llr_leaf = p.llrs[0, i]

                if is_frozen:
                    p_new = p.copy()
                    propagate_bits(p_new, i, 0)
                    if llr_leaf < 0:
                        p_new.pm += abs(llr_leaf)
                    next_paths.append(p_new)
                else:
                    # Branch 0
                    p0 = p.copy()
                    propagate_bits(p0, i, 0)
                    if llr_leaf < 0:
                        p0.pm += abs(llr_leaf)
                    next_paths.append(p0)

                    # Branch 1
                    p1 = p.copy()
                    propagate_bits(p1, i, 1)
                    if llr_leaf > 0:
                        p1.pm += abs(llr_leaf)
                    next_paths.append(p1)

            next_paths.sort(key=lambda x: x.pm)
            paths = next_paths[:self.l_size]

        best_p = min(paths, key=lambda x: x.pm)
        info_bits = best_p.u_hat[RELIABLE_INDICES]
        return info_bits, best_p.pm


    def decode(self, channel_llrs: np.ndarray) -> tuple[np.ndarray, float]:
        """Vectorised SCL decoder: all active paths are carried in one batched array.

        The arithmetic is identical to `decode_scalar` (min-sum F, G with u, the same
        pruning by path metric and the same frozen/non-frozen branching) -- only the
        per-path Python loop is gone: every stage update and bit propagation now runs
        over all active paths at once with numpy broadcasting.  `decode_scalar` is
        retained as the reference for cross-checking.

        The number of active paths grows from 1 to at most L, so the arrays are kept
        at their actual size rather than padded to L with sentinel path metrics.
        """
        m = self.m
        n = self.n
        L = self.l_size

        llrs = np.zeros((1, m + 1, n), dtype=np.float64)
        bits = np.zeros((1, m + 1, n), dtype=np.uint8)
        u_hat = np.zeros((1, n), dtype=np.uint8)
        pm = np.zeros(1, dtype=np.float64)
        llrs[0, m, :] = channel_llrs

        P = 1

        for i in range(n):
            for stage in range(m - 1, -1, -1):
                block_len = 1 << stage
                step = 2 * block_len
                node_offset = (i // step) * step
                if (i // block_len) % 2 == 0:
                    a = llrs[:, stage + 1, node_offset:node_offset + block_len]
                    b = llrs[:, stage + 1, node_offset + block_len:node_offset + step]
                    llrs[:, stage, node_offset:node_offset + block_len] = compute_f(a, b)
                else:
                    a = llrs[:, stage + 1, node_offset:node_offset + block_len]
                    b = llrs[:, stage + 1, node_offset + block_len:node_offset + step]
                    u_left = bits[:, stage, node_offset:node_offset + block_len]
                    llrs[:, stage, node_offset + block_len:node_offset + step] = compute_g(a, b, u_left)

            is_frozen = bool(FROZEN_MASK[i])
            llr_leaf = llrs[:, 0, i]

            if is_frozen:
                pm_new = pm + np.where(llr_leaf < 0, np.abs(llr_leaf), 0.0)
                bits_new = bits.copy()
                bits_new[:, 0, i] = 0
                u_hat_new = u_hat.copy()
                u_hat_new[:, i] = 0
                for stage in range(m):
                    block_len = 1 << stage
                    step = 2 * block_len
                    node_offset = (i // step) * step
                    if (i // block_len) % 2 == 1:
                        l_val = bits_new[:, stage, node_offset:node_offset + block_len]
                        r_val = bits_new[:, stage, node_offset + block_len:node_offset + step]
                        bits_new[:, stage + 1, node_offset:node_offset + block_len] = l_val ^ r_val
                        bits_new[:, stage + 1, node_offset + block_len:node_offset + step] = r_val
                llrs = llrs
                bits = bits_new
                u_hat = u_hat_new
                pm = pm_new
            else:
                pm0 = pm + np.where(llr_leaf < 0, np.abs(llr_leaf), 0.0)
                bits0 = bits.copy()
                bits0[:, 0, i] = 0
                uhat0 = u_hat.copy()
                uhat0[:, i] = 0
                for stage in range(m):
                    block_len = 1 << stage
                    step = 2 * block_len
                    node_offset = (i // step) * step
                    if (i // block_len) % 2 == 1:
                        l_val = bits0[:, stage, node_offset:node_offset + block_len]
                        r_val = bits0[:, stage, node_offset + block_len:node_offset + step]
                        bits0[:, stage + 1, node_offset:node_offset + block_len] = l_val ^ r_val
                        bits0[:, stage + 1, node_offset + block_len:node_offset + step] = r_val

                pm1 = pm + np.where(llr_leaf > 0, np.abs(llr_leaf), 0.0)
                bits1 = bits.copy()
                bits1[:, 0, i] = 1
                uhat1 = u_hat.copy()
                uhat1[:, i] = 1
                for stage in range(m):
                    block_len = 1 << stage
                    step = 2 * block_len
                    node_offset = (i // step) * step
                    if (i // block_len) % 2 == 1:
                        l_val = bits1[:, stage, node_offset:node_offset + block_len]
                        r_val = bits1[:, stage, node_offset + block_len:node_offset + step]
                        bits1[:, stage + 1, node_offset:node_offset + block_len] = l_val ^ r_val
                        bits1[:, stage + 1, node_offset + block_len:node_offset + step] = r_val

                llrs_both = np.repeat(llrs, 2, axis=0)
                bits_both = np.stack([bits0, bits1], axis=1).reshape(2 * P, m + 1, n)
                uhat_both = np.stack([uhat0, uhat1], axis=1).reshape(2 * P, n)
                pm_both = np.stack([pm0, pm1], axis=1).reshape(2 * P)

                keep = min(2 * P, L)
                order = np.argsort(pm_both, kind="stable")[:keep]
                llrs = llrs_both[order]
                bits = bits_both[order]
                u_hat = uhat_both[order]
                pm = pm_both[order]
                P = keep

        best = int(np.argmin(pm))
        info_bits = u_hat[best, RELIABLE_INDICES]
        return info_bits, float(pm[best])



def polar_scl_decode(r_llrs: np.ndarray, l_size: int = L) -> tuple[np.ndarray, float]:
    decoder = SCLDecoder(N, K, l_size)
    return decoder.decode(r_llrs)
