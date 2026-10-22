"""Emit G2 conformance vectors for the polar SCL decoder (N=256, K=128, list size L=8).

The RTL contract is **integer** and follows the hardware schedule, not the numpy one:

  * LLRs are recomputed from the shared channel row at every leaf, one path at a time
    (the reference does the same full stage walk per leaf), so no per-path LLR memory
    and no LLR copy on pruning;
  * the partial sums of all L paths live in one L-bit word per (stage, idx) address, so
    pruning is an in-place **permutation** of each word (child k <- parent sel[k]) and
    the bit propagation runs on all paths at once (XOR on words);
  * candidates are ordered (parent 0 bit 0, parent 0 bit 1, parent 1 bit 0, ...), sorted
    stably by path metric, the first min(2P, L) kept -- exactly `polar_codec.SCLDecoder`;
  * the winner is the first minimum path metric among the P active paths.

This script implements that schedule in exact Python integers, cross-checks it against
`polar_codec.polar_scl_decode(llr, 8)` (float64 on integer inputs is exact here), checks
that the list matters (some cases decode differently from SC, list size 1), sizes the
datapath, and writes:

  polar_scl_llr.mem   (M x 256 signed 16-bit, hex)
  polar_scl_info.mem  (M x 128 bits)
  polar_scl_pm.mem    (M x winning path metric, 32-bit hex)
  polar_scl_params.vh / polar_scl_vectors.json

Run:  novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_polar_scl_vectors.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SIMS = HERE.parents[1] / "stego_research" / "sims"
sys.path.insert(0, str(SIMS))

import polar_codec  # noqa: E402

N = polar_codec.N
K = polar_codec.K
L = 8
LOG2N = 8
SEED = 20261020
WIDTH = 16
PM_WIDTH = 32

FROZEN = [bool(x) for x in polar_codec.FROZEN_MASK]
RELIABLE = [int(x) for x in polar_codec.RELIABLE_INDICES]

MAX_ABS = 0
MAX_PM = 0


def _sign(a: int) -> int:
    return 0 if a == 0 else (1 if a > 0 else -1)


def scl_decode_int(llr) -> tuple[list[int], int]:
    """SCL L=8 in the RTL's schedule, exact integers."""
    global MAX_ABS, MAX_PM
    m = LOG2N
    # bits[stage][idx] is an L-bit word: bit p = path p's partial sum
    bits = [[0] * N for _ in range(m + 1)]
    chan = [int(v) for v in llr]
    pm = [0] * L
    P = 1

    for i in range(N):
        # 1. leaf LLR for each active path, recomputed from the channel row
        leaf = [0] * L
        for p in range(P):
            llrs = [[0] * N for _ in range(m)] + [chan]
            for stage in range(m - 1, -1, -1):
                bl = 1 << stage
                step = 2 * bl
                off = (i // step) * step
                left = (i // bl) % 2 == 0
                for j in range(bl):
                    a = llrs[stage + 1][off + j]
                    b = llrs[stage + 1][off + bl + j]
                    if left:
                        v = _sign(a) * _sign(b) * min(abs(a), abs(b))
                        llrs[stage][off + j] = v
                    else:
                        u = (bits[stage][off + j] >> p) & 1
                        v = b + (1 - 2 * u) * a
                        llrs[stage][off + bl + j] = v
                    MAX_ABS = max(MAX_ABS, abs(v))
            leaf[p] = llrs[0][i]

        # 2. decision
        if FROZEN[i]:
            for p in range(P):
                if leaf[p] < 0:
                    pm[p] += -leaf[p]
            bits[0][i] = 0
        else:
            cand = []  # (pm, parent, bit) in the reference's interleaved order
            for p in range(P):
                lv = leaf[p]
                cand.append((pm[p] + (-lv if lv < 0 else 0), p, 0))
                cand.append((pm[p] + (lv if lv > 0 else 0), p, 1))
            keep = min(2 * P, L)
            # stable selection: repeatedly take the first minimum not yet taken
            taken = [False] * len(cand)
            sel = []
            for _ in range(keep):
                best = -1
                for c in range(len(cand)):
                    if not taken[c] and (best < 0 or cand[c][0] < cand[best][0]):
                        best = c
                taken[best] = True
                sel.append(cand[best])
            # in-place permutation of every word; leaf i's bit comes from the candidate
            for s in range(m + 1):
                for idx in range(N):
                    w = bits[s][idx]
                    nw = 0
                    for k, (_, par, b) in enumerate(sel):
                        bit = b if (s == 0 and idx == i) else (w >> par) & 1
                        nw |= bit << k
                    bits[s][idx] = nw
            pm = [c[0] for c in sel] + [0] * (L - keep)
            P = keep
        MAX_PM = max(MAX_PM, max(pm[:P]))

        # 3. propagate partial sums, all paths at once
        for stage in range(m):
            bl = 1 << stage
            step = 2 * bl
            off = (i // step) * step
            if (i // bl) % 2 == 1:
                for j in range(bl):
                    lw = bits[stage][off + j]
                    rw = bits[stage][off + bl + j]
                    bits[stage + 1][off + j] = lw ^ rw
                    bits[stage + 1][off + bl + j] = rw

    best = 0
    for p in range(1, P):
        if pm[p] < pm[best]:
            best = p
    return [(bits[0][c] >> best) & 1 for c in RELIABLE], pm[best]


def main() -> int:
    rng = np.random.default_rng(SEED)
    cases: list[list[int]] = []
    sent: list[list[int]] = []

    def add_noisy(A, noise, reps):
        for _ in range(reps):
            info = rng.integers(0, 2, K, dtype=np.uint8)
            code = polar_codec.polar_encode(info)
            cases.append([int(A * (1 - 2 * int(b)) + rng.integers(-noise, noise + 1))
                          for b in code])
            sent.append([int(b) for b in info])

    add_noisy(8, 0, 2)          # clean: must decode exactly
    add_noisy(8, 6, 3)          # mild
    add_noisy(8, 10, 4)         # SC starts to fail here
    add_noisy(8, 12, 4)
    add_noisy(16, 22, 3)
    for _ in range(4):          # tiny-range random: many ties (exercises stable ordering)
        cases.append([int(rng.integers(-2, 3)) for _ in range(N)])
        sent.append([0] * K)
    for _ in range(4):          # full-range random (exercises the datapath width)
        cases.append([int(rng.integers(-120, 121)) for _ in range(N)])
        sent.append([0] * K)
    M = len(cases)

    outs, pms = [], []
    differs_from_sc = 0
    scl_beats_sc = 0
    for idx, llr in enumerate(cases):
        out, pmv = scl_decode_int(llr)
        ref, ref_pm = polar_codec.polar_scl_decode(np.asarray(llr, dtype=np.float64), L)
        ref = [int(b) for b in ref]
        if out != ref or pmv != int(ref_pm):
            diff = sum(1 for a, b in zip(out, ref) if a != b)
            raise SystemExit(f"CONTRACT MISMATCH case {idx}: {diff} bits, pm {pmv} vs {ref_pm}")
        sc, _ = polar_codec.polar_scl_decode(np.asarray(llr, dtype=np.float64), 1)
        sc = [int(b) for b in sc]
        if sc != out:
            differs_from_sc += 1
            if out == sent[idx] and sc != sent[idx]:
                scl_beats_sc += 1
        outs.append(out)
        pms.append(pmv)

    assert outs[0] == sent[0] and outs[1] == sent[1], "clean cases must decode exactly"
    print(f"self-check: integer SCL(L=8, RTL schedule) == polar_scl_decode(L=8) on {M} cases "
          f"(bits and path metric)  [PASS]")
    print(f"self-check: clean cases decode exactly                                   [PASS]")
    print(f"list matters: {differs_from_sc}/{M} cases differ from SC; "
          f"{scl_beats_sc} of them SCL recovers the sent word where SC does not")
    print(f"datapath: max |llr| = {MAX_ABS} (signed {WIDTH}-bit), max pm = {MAX_PM} "
          f"(unsigned {PM_WIDTH}-bit)")
    if differs_from_sc == 0:
        raise SystemExit("no case separates SCL from SC: the vectors cannot catch a list bug")
    if MAX_ABS > 2 ** (WIDTH - 1) - 1 or MAX_PM >= 2 ** PM_WIDTH:
        raise SystemExit("OVERFLOW RISK: widen the datapath")

    (HERE / "polar_scl_llr.mem").write_text(
        "\n".join(f"{v & 0xFFFF:04x}" for llr in cases for v in llr) + "\n")
    (HERE / "polar_scl_info.mem").write_text(
        "\n".join(f"{b:x}" for out in outs for b in out) + "\n")
    (HERE / "polar_scl_pm.mem").write_text("\n".join(f"{v:08x}" for v in pms) + "\n")
    (HERE / "polar_scl_params.vh").write_text("\n".join([
        "// GENERATED by tools/tag_reference/vectors/gen_polar_scl_vectors.py -- do not edit.",
        "`ifndef POLAR_SCL_PARAMS_VH",
        "`define POLAR_SCL_PARAMS_VH",
        f"localparam integer POLAR_SCL_NUM_VECTORS = {M};",
        f"localparam integer POLAR_SCL_L = {L};",
        "`endif // POLAR_SCL_PARAMS_VH", ""]))
    (HERE / "polar_scl_vectors.json").write_text(json.dumps({
        "generator": "tools/tag_reference/vectors/gen_polar_scl_vectors.py",
        "date": "2026-10-20",
        "reference": "tools/stego_research/sims/polar_codec.py (SCLDecoder.decode, l_size=8)",
        "params": {"N": N, "K": K, "L": L, "num_vectors": M, "seed": SEED,
                   "datapath_width": WIDTH, "pm_width": PM_WIDTH,
                   "max_internal_abs": MAX_ABS, "max_pm": MAX_PM},
        "contract": "integer min-sum SCL; F: sign(a)sign(b)min(|a|,|b|); G: b+(1-2u)a; "
                    "pm += |llr| when the bit disagrees with sign (llr<0 for 0, llr>0 for 1); "
                    "candidates (p,0),(p,1) per parent, stable sort, keep min(2P,L); "
                    "winner = first minimum pm",
        "selftest": f"bits and pm equal to float SCL(L=8) on all cases; "
                    f"{differs_from_sc} cases differ from SC",
        "vectors": [{"i": k, "llr_hex": [f"{v & 0xFFFF:04x}" for v in cases[k]],
                     "info_out": "".join(str(b) for b in outs[k]), "pm": pms[k]}
                    for k in range(M)],
    }, indent=2) + "\n")
    print(f"wrote {M} SCL vectors to {HERE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
