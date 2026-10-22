"""Conformance vectors for `placement_core` (contract: embed._placement_map_impl, copy-major).

Per case: key, LL shape -> m, a taint map (one byte per block, raster order), erasure_mode, copies.
Expected stream: for copy c, bit i (c-major): block index, or 0xFFFFFF for "none" (erasure mode),
or the stream ends at the first copy that cannot complete (encoder mode; Python raises).
Files: pl_params.vh, pl_case.mem (%08x x 4 per case: m, erasure, copies, nrec), pl_key.mem,
pl_taint.mem (%02x, concatenated), pl_exp.mem (%06x, concatenated).
Run: novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_placement_vectors.py
"""
from __future__ import annotations
import sys
from pathlib import Path
import numpy as np
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE.parents[1] / "stego_research" / "sims"))
import embed  # noqa: E402

NONE = 0xFFFFFF

def expected(key, shape, blocked, erasure, copies):
    lh, lw = shape
    wb = lw // 4
    out = []
    for c in range(copies):
        try:
            order = embed._placement_map_impl(key, shape, c, blocked, 256, None, erasure)
        except ValueError:
            break                       # encoder: this copy cannot complete, stop
        for pos in order:
            out.append(NONE if pos is None else (pos[0] // 4) * wb + pos[1] // 4)
    return out

def main() -> int:
    rng = np.random.default_rng(20261022)
    cases = []
    for shape, dens, erasure, copies in [((128, 128), 0.5, 0, 4), ((128, 128), 0.8, 0, 4),
                                          ((128, 128), 0.8, 1, 4), ((256, 256), 0.5, 0, 4),
                                          ((256, 256), 0.9, 1, 3), ((128, 128), 0.0, 0, 4),
                                          ((136, 120), 0.3, 0, 2)]:
        key = bytes(rng.integers(0, 256, 16, dtype=np.uint8))
        hb, wb = shape[0] // 4, shape[1] // 4
        blocked = rng.random((hb, wb)) < dens
        cases.append((key, shape, blocked, erasure, copies, expected(key, shape, blocked, erasure, copies)))
    (HERE / "pl_key.mem").write_text("".join(f"{c[0].hex()}\n" for c in cases))
    meta, taint, exp = [], [], []
    for key, shape, blocked, erasure, copies, e in cases:
        m = (shape[0] // 4) * (shape[1] // 4)
        meta += [m, erasure, copies, len(e)]
        taint += [int(b) for b in blocked.reshape(-1)]
        exp += e
    (HERE / "pl_case.mem").write_text("".join(f"{v:08x}\n" for v in meta))
    (HERE / "pl_taint.mem").write_text("".join(f"{v:02x}\n" for v in taint))
    (HERE / "pl_exp.mem").write_text("".join(f"{v:06x}\n" for v in exp))
    (HERE / "pl_params.vh").write_text(
        f"localparam PL_NUM_CASES = {len(cases)};\nlocalparam PL_TOTAL_TAINT = {len(taint)};\n"
        f"localparam PL_TOTAL_EXP = {len(exp)};\n")
    print(f"{len(cases)} cases, {len(exp)} expected records:", [len(c[5]) for c in cases])
    return 0
if __name__ == "__main__":
    raise SystemExit(main())
