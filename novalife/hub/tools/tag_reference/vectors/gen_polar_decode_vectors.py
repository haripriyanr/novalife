"""Emit G2 conformance vectors for the polar SC decoder (N=256, K=128, list size 1).

The decoder contract is **integer** (the RTL cannot carry float64). This script:

  1. implements the SC decoder in exact Python integers, mirroring
     `polar_codec.SCLDecoder` with `l_size = 1` (min-sum F, integer G);
  2. cross-checks that integer decoder against `polar_codec.polar_scl_decode(llr, 1)`
     so the contract is provably the same decoder, not a lookalike;
  3. reports the largest internal magnitude, which sizes the RTL datapath;
  4. writes `polar_dec_llr.mem` / `polar_dec_info.mem` (flat, `$readmemh`) and
     `polar_dec_params.vh` / `polar_decode_vectors.json`.

Cases: clean, noisy at several amplitudes, and fully random integer LLRs (the last ones
exercise the FSM, not decode correctness).

Run:  novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_polar_decode_vectors.py
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
M = 24                 # number of decoder vectors
SEED = 20261019
WIDTH = 16             # candidate datapath width (bits, signed)

FROZEN = polar_codec.FROZEN_MASK
RELIABLE = np.asarray(polar_codec.RELIABLE_INDICES, dtype=int)

MAX_ABS = 0            # tracked across all cases


def _sign(a: int) -> int:
    # numpy.sign: 0 -> 0, positive -> 1, negative -> -1
    return 0 if a == 0 else (1 if a > 0 else -1)


def sc_decode_int(llr) -> list[int]:
    """SC (list size 1) decode with integer arithmetic — the RTL contract."""
    global MAX_ABS
    m = int(np.log2(N))
    llrs = [[0] * N for _ in range(m + 1)]
    bits = [[0] * N for _ in range(m + 1)]
    llrs[m] = [int(v) for v in llr]
    u_hat = [0] * N

    for i in range(N):
        for stage in range(m - 1, -1, -1):
            bl = 1 << stage
            step = 2 * bl
            off = (i // step) * step
            if (i // bl) % 2 == 0:
                for j in range(bl):
                    a = llrs[stage + 1][off + j]
                    b = llrs[stage + 1][off + bl + j]
                    v = _sign(a) * _sign(b) * min(abs(a), abs(b))
                    llrs[stage][off + j] = v
                    MAX_ABS = max(MAX_ABS, abs(v))
            else:
                for j in range(bl):
                    a = llrs[stage + 1][off + j]
                    b = llrs[stage + 1][off + bl + j]
                    u = bits[stage][off + j]
                    v = b + (1 - 2 * u) * a
                    llrs[stage][off + bl + j] = v
                    MAX_ABS = max(MAX_ABS, abs(v))

        if FROZEN[i]:
            v = 0
        else:
            v = 1 if llrs[0][i] < 0 else 0

        bits[0][i] = v
        u_hat[i] = v
        for stage in range(m):
            bl = 1 << stage
            step = 2 * bl
            off = (i // step) * step
            if (i // bl) % 2 == 1:
                for j in range(bl):
                    l = bits[stage][off + j]
                    r = bits[stage][off + bl + j]
                    bits[stage + 1][off + j] = l ^ r
                    bits[stage + 1][off + bl + j] = r

    return [int(u_hat[c]) for c in RELIABLE]


def encode(bits: np.ndarray) -> np.ndarray:
    return polar_codec.polar_encode(bits)


def s16(v: int) -> int:
    """wrap to signed 16-bit (the RTL datapath)"""
    v &= 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def main() -> int:
    rng = np.random.default_rng(SEED)
    llr_cases: list[list[int]] = []
    info_cases: list[list[int]] = []

    # --- build cases -----------------------------------------------------------------
    # 1. clean: llr = A * (1 - 2x), must decode to the exact info bits
    for A in (4, 8, 16):
        info = rng.integers(0, 2, K, dtype=np.uint8)
        code = encode(info)
        llr = [int(A * (1 - 2 * int(bit))) for bit in code]
        llr_cases.append(llr)
        info_cases.append([int(b) for b in info])
    # 2. noisy: clean + integer noise, several amplitudes (some will decode wrong — fine,
    #    the contract records the exact integer output)
    for A, noise, reps in ((8, 1, 2), (8, 3, 2), (16, 6, 2), (12, 10, 2)):
        for _ in range(reps):
            info = rng.integers(0, 2, K, dtype=np.uint8)
            code = encode(info)
            llr = [int(A * (1 - 2 * int(bit)) + rng.integers(-noise, noise + 1))
                   for bit in code]
            llr_cases.append(llr)
            info_cases.append([int(b) for b in info])
    # 3. random integer LLRs, clipped to the datapath range (exercise the FSM)
    for _ in range(M - len(llr_cases)):
        llr = [int(rng.integers(-64, 65)) for _ in range(N)]
        llr_cases.append(llr)
        info_cases.append([int(b) for b in rng.integers(0, 2, K, dtype=np.uint8)])

    assert len(llr_cases) == M, len(llr_cases)

    # --- run the integer decoder and cross-check vs the float reference ---------------
    out_cases: list[list[int]] = []
    for idx, llr in enumerate(llr_cases):
        out = sc_decode_int(llr)
        ref, _pm = polar_codec.polar_scl_decode(np.asarray(llr, dtype=np.float64), 1)
        ref = [int(b) for b in ref]
        if out != ref:
            diff = sum(1 for a, b in zip(out, ref) if a != b)
            raise SystemExit(
                f"CONTRACT MISMATCH on case {idx}: integer SC differs from float SCL(l=1) "
                f"in {diff} of {K} bits"
            )
        out_cases.append(out)

    # --- clean cases must decode exactly to their own info bits -----------------------
    for idx in range(3):
        assert out_cases[idx] == info_cases[idx], f"clean case {idx} failed to decode exactly"
    print(f"self-check: integer SC == polar_scl_decode(l_size=1) on {M} cases  [PASS]")
    print(f"self-check: clean cases 0..2 decode exactly to the info bits     [PASS]")
    print(f"datapath: max internal magnitude = {MAX_ABS}  "
          f"(signed {WIDTH}-bit range +/-{2**(WIDTH-1)-1})")

    if MAX_ABS > 2 ** (WIDTH - 1) - 1:
        raise SystemExit(
            f"OVERFLOW RISK: internal magnitude {MAX_ABS} exceeds signed {WIDTH}-bit. "
            f"Widen the datapath (WIDTH) and re-run."
        )

    # --- write flat memories ----------------------------------------------------------
    llr_lines = []
    for llr in llr_cases:
        for v in llr:
            llr_lines.append(f"{v & 0xFFFF:04x}")
    (HERE / "polar_dec_llr.mem").write_text("\n".join(llr_lines) + "\n")

    info_lines = []
    for out in out_cases:
        for v in out:
            info_lines.append(f"{v & 0x1:x}")
    (HERE / "polar_dec_info.mem").write_text("\n".join(info_lines) + "\n")

    (HERE / "polar_dec_params.vh").write_text(
        "\n".join([
            "// GENERATED by tools/tag_reference/vectors/gen_polar_decode_vectors.py — do not edit.",
            "`ifndef POLAR_DEC_PARAMS_VH",
            "`define POLAR_DEC_PARAMS_VH",
            f"localparam integer POLAR_DEC_NUM_VECTORS = {M};",
            f"localparam integer POLAR_DEC_WIDTH = {WIDTH};",
            "`endif // POLAR_DEC_PARAMS_VH",
            "",
        ])
    )

    (HERE / "polar_decode_vectors.json").write_text(
        json.dumps(
            {
                "generator": "tools/tag_reference/vectors/gen_polar_decode_vectors.py",
                "date": "2026-10-19",
                "reference": "tools/stego_research/sims/polar_codec.py (SCLDecoder, l_size=1)",
                "params": {"N": N, "K": K, "num_vectors": M, "seed": SEED,
                           "datapath_width": WIDTH, "max_internal_abs": MAX_ABS},
                "contract": "integer min-sum SC; F: sign(a)sign(b)min(|a|,|b|); "
                            "G: b+(1-2u)a; decision: u=0 if llr>=0 else 1; frozen -> 0",
                "selftest": "integer SC == float SCL(l=1) on all cases",
                "vectors": [
                    {
                        "i": idx,
                        "llr_hex": [f"{v & 0xFFFF:04x}" for v in llr_cases[idx]],
                        "info_out_hex": "".join(str(b) for b in out_cases[idx]),
                    }
                    for idx in range(M)
                ],
            },
            indent=2,
        )
        + "\n"
    )

    print(f"wrote {M} decode vectors + polar_dec_params.vh to {HERE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
