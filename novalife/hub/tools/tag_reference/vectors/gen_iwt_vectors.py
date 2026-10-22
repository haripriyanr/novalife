"""Emit G2 conformance vectors for the 5/3 IWT core (`iwt_53_core`).

The contract is `tools/stego_research/sims/iwt_lifting`:

  * `iwt1d_53`  — the 1D lifting kernel the core implements directly;
  * `iwt2d_53`  — the 2D transform (rows, then columns), which the testbench composes from
                  two instantiations of the same core and checks sub-band by sub-band.

Both are exact-integer (the reference uses numpy int32 and arithmetic `>>`), so the core can
be checked bit-exactly.

Cases:
  * 1D lines: minimum length 2, flat positive/negative, ramp, impulse, the two amplitude
    extremes, alternating extremes, a line whose predictor/update sums are negative and not
    divisible by 2 and 4 (so floor vs truncate shift shows up), a random full-range line and
    a random line at the maximum supported length (512);
  * 2D frames: a 16x16 and a **non-square** 8x16 frame of 8-bit pixels (the non-square one
    catches a row/column transpose in the testbench harness, which is where a 2D IWT is
    usually got wrong).

Files written (hex words, one per line, `$readmemh`-compatible; values are the low 32 bits of
the signed integer, so negatives survive):
  iwt_params.vh       NLINES, MAX_LEN, MAXK, MAX_FRAMES, MAX_H, MAX_W, SUB_WORDS, DATA_W
  iwt_line_len.mem    per line: the length
  iwt_line_in.mem     NLINES x MAX_LEN samples (zero padded)
  iwt_line_s.mem      NLINES x MAXK low-pass coefficients (zero padded)
  iwt_line_d.mem      NLINES x MAXK high-pass coefficients (zero padded)
  iwt_frame_spec.mem  per frame: h, w
  iwt_frame_in.mem    MAX_FRAMES x MAX_H*MAX_W pixels (zero padded)
  iwt_frame_sub.mem   MAX_FRAMES x 4 x SUB_WORDS, bands in the order LL, LH, HL, HH
  iwt_vectors.json    the same, for humans and other languages

Run:  novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_iwt_vectors.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SIMS = HERE.parents[1] / "stego_research" / "sims"
sys.path.insert(0, str(SIMS))

import iwt_lifting as iwt  # noqa: E402

MAX_LOG2 = 9
MAX_LEN = 1 << MAX_LOG2
MAXK = 1 << (MAX_LOG2 - 1)
DATA_W = 16
COEFF_W = DATA_W + 2          # the 1D kernel's output width
COEFF2_W = COEFF_W + 2        # the 2D result width
NL = 12

MAX_FRAMES = 2
MAX_H = 16
MAX_W = 16
FRAME_WORDS = MAX_H * MAX_W
SH = MAX_H // 2
SW = MAX_W // 2
SUB_WORDS = SH * SW
SEED = 20261019


def _u32(v) -> int:
    return int(v) & 0xFFFFFFFF


def build_lines() -> list[np.ndarray]:
    rng = np.random.default_rng(SEED)
    lines: list[np.ndarray] = [
        np.array([5, -3], dtype=np.int64),
        np.zeros(8, dtype=np.int64),
        np.full(8, 7, dtype=np.int64),
        np.full(8, -7, dtype=np.int64),
        np.arange(16, dtype=np.int64),
        np.array([0] * 5 + [1000] + [0] * 10, dtype=np.int64),
        np.full(8, 32767, dtype=np.int64),
        np.full(8, -32768, dtype=np.int64),
        np.array([32767 if i % 2 == 0 else -32768 for i in range(16)], dtype=np.int64),
        np.arange(-1, -17, -1, dtype=np.int64),
        rng.integers(-32768, 32768, size=64, dtype=np.int64),
        rng.integers(0, 256, size=MAX_LEN, dtype=np.int64),
    ]
    for i, ln in enumerate(lines):
        assert ln.size <= MAX_LEN, (i, ln.size)
        assert ln.size % 2 == 0, (i, ln.size)
        assert ln.min() >= -(2 ** (DATA_W - 1)) and ln.max() <= 2 ** (DATA_W - 1) - 1, i
    return lines


def build_frames() -> list[np.ndarray]:
    rng = np.random.default_rng(SEED + 1)
    frames = [
        rng.integers(0, 256, size=(16, 16), dtype=np.int64),
        rng.integers(0, 256, size=(8, 16), dtype=np.int64),
    ]
    for f in frames:
        assert f.shape[0] <= MAX_H and f.shape[1] <= MAX_W
        assert f.shape[0] % 2 == 0 and f.shape[1] % 2 == 0
    return frames


def main() -> int:
    lines = build_lines()
    frames = build_frames()

    line_len = [int(ln.size) for ln in lines]
    line_s, line_d = zip(*(iwt.iwt1d_53(ln.astype(np.int32)) for ln in lines))

    # the 1D kernel must stay inside the widths the core declares
    for ln, s, d in zip(lines, line_s, line_d):
        lim = 1 << (COEFF_W - 1)
        assert s.max() < lim and s.min() >= -lim, ("s overflow", ln.size)
        assert d.max() < lim and d.min() >= -lim, ("d overflow", ln.size)

    subs = []
    for f in frames:
        LL, (LH, HL, HH) = iwt.iwt2d_53(f.astype(np.int32))
        lim = 1 << (COEFF2_W - 1)
        for band in (LL, LH, HL, HH):
            assert band.max() < lim and band.min() >= -lim, "2D coefficient overflow"
        subs.append((LL, LH, HL, HH))

    (HERE / "iwt_line_len.mem").write_text("".join(f"{v:08x}\n" for v in line_len))
    (HERE / "iwt_line_in.mem").write_text(
        "".join(
            "".join(f"{_u32(v):08x}\n" for v in np.concatenate([ln, np.zeros(MAX_LEN - ln.size, dtype=np.int64)]))
            for ln in lines
        )
    )
    for name, arrs in (("iwt_line_s.mem", line_s), ("iwt_line_d.mem", line_d)):
        (HERE / name).write_text(
            "".join(
                "".join(f"{_u32(v):08x}\n" for v in np.concatenate([a, np.zeros(MAXK - a.size, dtype=np.int64)]))
                for a in arrs
            )
        )

    (HERE / "iwt_frame_spec.mem").write_text(
        "".join(f"{int(f.shape[0]):08x}\n{int(f.shape[1]):08x}\n" for f in frames)
    )
    (HERE / "iwt_frame_in.mem").write_text(
        "".join(
            "".join(
                f"{_u32(v):08x}\n"
                for v in np.concatenate([f.ravel(), np.zeros(FRAME_WORDS - f.size, dtype=np.int64)])
            )
            for f in frames
        )
    )
    (HERE / "iwt_frame_sub.mem").write_text(
        "".join(
            "".join(
                f"{_u32(v):08x}\n"
                for v in np.concatenate([band.ravel(), np.zeros(SUB_WORDS - band.size, dtype=np.int64)])
            )
            for bands in subs
            for band in bands
        )
    )

    (HERE / "iwt_params.vh").write_text(
        "\n".join(
            [
                "// GENERATED by tools/tag_reference/vectors/gen_iwt_vectors.py - do not edit.",
                "`ifndef IWT_PARAMS_VH",
                "`define IWT_PARAMS_VH",
                f"localparam integer IWT_MAX_LOG2 = {MAX_LOG2};",
                f"localparam integer IWT_NLINES = {NL};",
                f"localparam integer IWT_MAX_LEN = {MAX_LEN};",
                f"localparam integer IWT_MAXK = {MAXK};",
                f"localparam integer IWT_MAX_FRAMES = {MAX_FRAMES};",
                f"localparam integer IWT_MAX_H = {MAX_H};",
                f"localparam integer IWT_MAX_W = {MAX_W};",
                f"localparam integer IWT_FRAME_WORDS = {FRAME_WORDS};",
                f"localparam integer IWT_SUB_WORDS = {SUB_WORDS};",
                f"localparam integer IWT_DATA_W = {DATA_W};",
                f"localparam integer IWT_COEFF_W = {COEFF_W};",
                f"localparam integer IWT_COEFF2_W = {COEFF2_W};",
                "`endif // IWT_PARAMS_VH",
                "",
            ]
        )
    )

    (HERE / "iwt_vectors.json").write_text(
        json.dumps(
            {
                "generator": "tools/tag_reference/vectors/gen_iwt_vectors.py",
                "date": "2026-10-19",
                "reference": "tools/stego_research/sims/iwt_lifting.py (iwt1d_53, iwt2d_53)",
                "params": {
                    "max_log2": MAX_LOG2,
                    "n_lines": NL,
                    "max_len": MAX_LEN,
                    "maxk": MAXK,
                    "data_w": DATA_W,
                    "coeff_w": COEFF_W,
                    "coeff2_w": COEFF2_W,
                    "max_frames": MAX_FRAMES,
                    "max_h": MAX_H,
                    "max_w": MAX_W,
                    "sub_words": SUB_WORDS,
                },
                "format": "every .mem line is the low 32 bits of a signed integer in hex",
                "lines": [
                    {
                        "i": i,
                        "len": line_len[i],
                        "in": [int(v) for v in lines[i]],
                        "s": [int(v) for v in line_s[i]],
                        "d": [int(v) for v in line_d[i]],
                    }
                    for i in range(NL)
                ],
                "frames": [
                    {
                        "i": i,
                        "h": int(f.shape[0]),
                        "w": int(f.shape[1]),
                        "pixels": [int(v) for v in f.ravel()],
                        "LL": [int(v) for v in subs[i][0].ravel()],
                        "LH": [int(v) for v in subs[i][1].ravel()],
                        "HL": [int(v) for v in subs[i][2].ravel()],
                        "HH": [int(v) for v in subs[i][3].ravel()],
                    }
                    for i, f in enumerate(frames)
                ],
            },
            indent=2,
        )
        + "\n"
    )

    print(f"wrote {NL} IWT lines and {MAX_FRAMES} frames to {HERE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
