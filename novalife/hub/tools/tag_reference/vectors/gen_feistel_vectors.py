"""Conformance vectors for `feistel_perm_core` (contract: embed.placement_permute).
Files: fp_params.vh, fp_key.mem (%032x), fp_m.mem (%08x), fp_slot.mem (%08x), fp_exp.mem (%08x).
Run: novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_feistel_vectors.py
"""
from __future__ import annotations
import sys
from pathlib import Path
import numpy as np
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE.parents[1] / "stego_research" / "sims"))
import embed  # noqa: E402

def main() -> int:
    rng = np.random.default_rng(20261022)
    keys = [embed.HUB_KEY] + [bytes(rng.integers(0, 256, 16, dtype=np.uint8)) for _ in range(5)]
    ms = [1, 2, 3, 4, 5, 16, 17, 1000, 1024, 4096, 4097, 36864, 100000, 1 << 20]
    rows = []
    for m in ms:
        for _ in range(12 if m > 3 else 3):
            slots = [int(rng.integers(0, m))] if m > 1 else [0]
            for s in slots + ([0, m - 1] if m > 1 else []):
                k = keys[int(rng.integers(0, len(keys)))]
                rows.append((k, m, s, embed.placement_permute(k, m, s)))
    (HERE / "fp_key.mem").write_text("".join(f"{r[0].hex()}\n" for r in rows))
    (HERE / "fp_m.mem").write_text("".join(f"{r[1]:08x}\n" for r in rows))
    (HERE / "fp_slot.mem").write_text("".join(f"{r[2]:08x}\n" for r in rows))
    (HERE / "fp_exp.mem").write_text("".join(f"{r[3]:08x}\n" for r in rows))
    (HERE / "fp_params.vh").write_text(f"localparam FP_NUM_VECTORS = {len(rows)};\n")
    print(f"{len(rows)} feistel vectors")
    return 0
if __name__ == "__main__":
    raise SystemExit(main())
