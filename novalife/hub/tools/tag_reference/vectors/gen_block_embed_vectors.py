"""Emit G2 conformance vectors for the block embedder core (`block_embed_core`).

The contract is `tools/tag_reference/embed.py` (algorithm.md 3.2), all integer:

    delta = 64 + (5 * isqrt(var)) >> 3, forced even        (qim_delta(local_std))
    T     = delta / 2
    v     = sum(H * x),  H = outer([1,1,-1,-1],[1,1,-1,-1])  (block_projection)
    e     = embed_error(v, bit, delta)    (sign rule, capped at +/-4T)
    x'    = x + H * d,  d_k = floor(e/16) + (k < e mod 16)   (quantize_block)
    read  = (v < 0)                                           (read_block_llr hard bit)

Inputs per vector: 16 signed 16-bit LL samples (row-major), the 32-bit local variance, the bit.
Expected: delta, v, the 16 output samples, and the read bit of the INPUT block.

Cases: v already beyond +/-T (e = 0), v exactly at +/-T and +/-(T-1), a strong opposite host
(cap), e with every remainder 0..15, var 0 / perfect squares / squares-1 (isqrt edges), the
odd->even delta fix, large variance, and random blocks.

Files: be_params.vh, be_in.mem (%04x), be_var.mem (%08x), be_bit.mem, be_delta.mem (%04x),
be_v.mem (%08x, two's complement 32-bit), be_out.mem (%04x), be_rbit.mem, be_vectors.json.

Run:  novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_block_embed_vectors.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parents[1] / "stego_research" / "sims"))
import embed  # noqa: E402

SEED = 20261020
H = embed.HADAMARD.reshape(-1)


def delta_of(var: int) -> int:
    return embed.qim_delta(math.isqrt(var))


def case(name, x, var, bit):
    x = np.asarray(x, dtype=np.int64).reshape(4, 4)
    assert x.min() >= -32768 + 600 and x.max() <= 32767 - 600, name
    d = delta_of(var)
    y = embed.quantize_block(x, bit, d)
    return {"name": name, "x": x.reshape(-1).tolist(), "var": int(var), "bit": int(bit),
            "delta": d, "v": embed.block_projection(x), "y": y.reshape(-1).tolist(),
            "rbit": embed.read_block_llr(x, d)[0]}


def block_with_v(base: int, target_v: int, rng) -> np.ndarray:
    """A random block whose projection is exactly target_v."""
    x = rng.integers(base - 20, base + 21, 16)
    v = int(np.sum(H * x))
    x[0] += target_v - v      # H[0] = +1
    return x


def main() -> int:
    rng = np.random.default_rng(SEED)
    cs = []
    for var in (0, 1, 3, 4, 15, 16, 63, 64, 99, 100, 255, 256, 1023, 1024, 4095, 65535, 1 << 20,
                (1 << 31) - 1):
        cs.append(case(f"var {var}", rng.integers(0, 256, 16), var, int(rng.integers(0, 2))))
    t = delta_of(0) // 2
    for tv, bit in ((t, 0), (t - 1, 0), (-t, 1), (-t + 1, 1), (t + 5, 0), (-t - 5, 1),
                    (0, 0), (0, 1), (5 * t, 1), (-5 * t, 0), (4 * t, 1), (-4 * t, 0)):
        cs.append(case(f"v {tv} bit {bit}", block_with_v(100, tv, rng), 0, bit))
    for rem in range(16):           # e = t - v for bit 0 -> choose v = t - (32 + rem)
        cs.append(case(f"rem {rem} +", block_with_v(120, t - 32 - rem, rng), 0, 0))
        cs.append(case(f"rem {rem} -", block_with_v(120, -t + 32 + rem, rng), 0, 1))
    cs.append(case("negative samples", rng.integers(-300, 0, 16), 500, 1))
    for i in range(60):
        cs.append(case(f"random {i}", rng.integers(-200, 456, 16), int(rng.integers(0, 40000)),
                       int(rng.integers(0, 2))))
    n = len(cs)
    w = lambda name, vals, fmt: (HERE / name).write_text("".join(f"{fmt(v)}\n" for v in vals))
    w("be_in.mem", [s for c in cs for s in c["x"]], lambda v: f"{v & 0xFFFF:04x}")
    w("be_out.mem", [s for c in cs for s in c["y"]], lambda v: f"{v & 0xFFFF:04x}")
    w("be_var.mem", [c["var"] for c in cs], lambda v: f"{v:08x}")
    w("be_bit.mem", [c["bit"] for c in cs], lambda v: f"{v:01x}")
    w("be_rbit.mem", [c["rbit"] for c in cs], lambda v: f"{v:01x}")
    w("be_delta.mem", [c["delta"] for c in cs], lambda v: f"{v:04x}")
    w("be_v.mem", [c["v"] for c in cs], lambda v: f"{v & 0xFFFFFFFF:08x}")
    (HERE / "be_params.vh").write_text(f"localparam BE_NUM_VECTORS = {n};\n")
    (HERE / "be_vectors.json").write_text(json.dumps(cs, indent=1) + "\n")
    print(f"wrote {n} block-embed vectors")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
