"""Emit G2 conformance vectors for the perceptual-mask core (`perceptual_mask_core`).

The contract is `tools/stego_research/sims/perceptual_mask.mask_block_decision`, which is
`generate_perceptual_mask`'s 4x4-tile decision written without floats:

    var  = compute_dsp48_variance(block)          # E[X^2] - E[X]^2, floored, >= 0
    mask = 1 iff  roi_count * 2 < BLOCK  and  var > VAR_THRESHOLD

The block is `HW_BLOCK` signed 16-bit samples (sub-band / LL integer coefficients), and the
ROI rule is the reference's `np.mean(tile_roi) < 0.5` — a **majority** test, not "any".

Cases are chosen so that the interesting branches are all exercised and so that the
testbench is provably sensitive (verified by mutation):
  * var == 0 (flat blocks, both signs, both amplitude extremes);
  * var == 1 (must NOT embed) and var == 2 (must embed);
  * the ROI majority boundary: roi_count 7 (embeds) vs 8 (protected) on a var==2 block;
  * a negative sum that is not a multiple of BLOCK, where floor vs truncate division of
    E[X] changes the answer ([-7, -1 x10, 0 x5] -> mean -17/16 = -2, var clamps to 0);
  * the same with a positive sum (+17) so the floor branch is checked both ways;
  * full-scale and alternating-extreme blocks (accumulator width);
  * random blocks over several amplitude ranges with random ROI counts.

Files written (hex words, one per line, `$readmemh`-compatible):
  mask_params.vh     NUM_VECTORS, BLOCK, DATA_W, VAR_THRESHOLD
  mask_in.mem        the block samples, two's complement, `%04x`
  mask_roi.mem       the ROI bits, `%01x`
  mask_exp_var.mem   the expected variance, `%08x`
  mask_exp_mask.mem  the expected mask bit, `%01x`
  mask_vectors.json  the same, for humans and other languages

Run:  novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_mask_vectors.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parents[1]                      # tools/
SIMS = TOOLS / "stego_research" / "sims"
sys.path.insert(0, str(SIMS))

import perceptual_mask as pm  # noqa: E402

BLOCK = pm.HW_BLOCK                          # 16 samples
DATA_W = 16
SEED = 20261019


def _case(name: str, samples, roi) -> dict:
    b = np.asarray(samples, dtype=np.int64)
    r = np.asarray(roi, dtype=np.int64)
    assert b.size == BLOCK and r.size == BLOCK, name
    assert b.min() >= -(2 ** (DATA_W - 1)) and b.max() <= 2 ** (DATA_W - 1) - 1, name
    var, mask = pm.mask_block_decision(b, r)
    return {"name": name, "samples": b, "roi": r, "var": var, "mask": mask}


def build_cases() -> list[dict]:
    z = [0] * BLOCK
    cases: list[dict] = []

    v2 = [0] * BLOCK
    v2[0] = 6                                # sum 6, sum^2 36 -> mean_x 0, mean_x2 2, var 2
    v1 = [0] * BLOCK
    v1[0] = 4                                # sum^2 16 -> mean_x2 1, var 1 (not > 1)

    cases += [
        _case("flat_zero", z, z),
        _case("flat_const_pos", [100] * BLOCK, z),
        _case("flat_const_neg", [-100] * BLOCK, z),
        _case("var1_no_embed", v1, z),
        _case("var2_embed", v2, z),
        _case("var2_roi7_embed", v2, [1] * 7 + [0] * 9),
        _case("var2_roi8_protected", v2, [1] * 8 + [0] * 8),
        _case("var2_roi16_protected", v2, [1] * BLOCK),
        _case("negsum_floor", [-7] + [-1] * 10 + [0] * 5, z),
        _case("possum_floor", [7] + [1] * 10 + [0] * 5, z),
        _case("max_pos", [32767] * BLOCK, z),
        _case("max_neg", [-32768] * BLOCK, z),
        _case("alt_extremes", [32767 if i % 2 == 0 else -32768 for i in range(BLOCK)], z),
        _case("alt_extremes_roi8", [32767 if i % 2 == 0 else -32768 for i in range(BLOCK)],
              [1] * 8 + [0] * 8),
        _case("ramp", list(range(BLOCK)), z),
    ]

    rng = np.random.default_rng(SEED)
    ranges = [(-32768, 32768), (-8, 9), (-32000, 32001), (-64, 65), (-3, 4)]
    roi_counts = [0, 0, 3, 7, 8, 11, 16, 1]
    for i in range(16):
        lo, hi = ranges[i % len(ranges)]
        b = rng.integers(lo, hi, size=BLOCK, dtype=np.int64)
        if i % 3 == 2:                       # sparse: mostly flat with a few spikes
            keep = rng.random(BLOCK) < 0.25
            b = np.where(keep, b, 0)
        r = np.zeros(BLOCK, dtype=np.int64)
        k = roi_counts[i % len(roi_counts)]
        if k:
            r[rng.choice(BLOCK, size=k, replace=False)] = 1
        cases.append(_case(f"random_{i:02d}", b, r))

    return cases


def main() -> int:
    cases = build_cases()

    # the case set must exercise every branch the testbench has to protect
    masks = [c["mask"] for c in cases]
    assert any(m == 1 for m in masks) and any(m == 0 for m in masks)
    assert any(c["var"] == 0 for c in cases)
    assert any(c["var"] == 1 for c in cases)
    assert any(c["name"] == "var2_roi7_embed" and c["mask"] == 1 for c in cases)
    assert any(c["name"] == "var2_roi8_protected" and c["mask"] == 0 for c in cases)
    assert any(c["name"] == "negsum_floor" for c in cases)
    assert any(c["name"] == "possum_floor" and c["var"] > 1 for c in cases)

    (HERE / "mask_in.mem").write_text(
        "".join(
            "".join(f"{int(v) & 0xFFFF:04x}\n" for v in c["samples"]) for c in cases
        )
    )
    (HERE / "mask_roi.mem").write_text(
        "".join("".join(f"{int(v) & 0x1:01x}\n" for v in c["roi"]) for c in cases)
    )
    (HERE / "mask_exp_var.mem").write_text(
        "".join(f"{c['var']:08x}\n" for c in cases)
    )
    (HERE / "mask_exp_mask.mem").write_text(
        "".join(f"{c['mask']:01x}\n" for c in cases)
    )

    (HERE / "mask_params.vh").write_text(
        "\n".join(
            [
                "// GENERATED by tools/tag_reference/vectors/gen_mask_vectors.py - do not edit.",
                "`ifndef MASK_PARAMS_VH",
                "`define MASK_PARAMS_VH",
                f"localparam integer MASK_NUM_VECTORS = {len(cases)};",
                f"localparam integer MASK_BLOCK = {BLOCK};",
                f"localparam integer MASK_DATA_W = {DATA_W};",
                f"localparam integer MASK_VAR_THRESHOLD = {pm.VAR_THRESHOLD};",
                "`endif // MASK_PARAMS_VH",
                "",
            ]
        )
    )

    (HERE / "mask_vectors.json").write_text(
        json.dumps(
            {
                "generator": "tools/tag_reference/vectors/gen_mask_vectors.py",
                "date": "2026-10-19",
                "reference": "tools/stego_research/sims/perceptual_mask.py "
                             "(mask_block_decision -> compute_dsp48_variance)",
                "params": {
                    "num_vectors": len(cases),
                    "block": BLOCK,
                    "data_w": DATA_W,
                    "var_threshold": pm.VAR_THRESHOLD,
                },
                "format": "mask_in.mem/mask_roi.mem are per-sample lines, "
                          "mask_exp_var.mem/mask_exp_mask.mem are per-case lines",
                "vectors": [
                    {
                        "i": i,
                        "name": c["name"],
                        "samples": [int(v) for v in c["samples"]],
                        "roi": [int(v) for v in c["roi"]],
                        "expected_var": c["var"],
                        "expected_mask": c["mask"],
                    }
                    for i, c in enumerate(cases)
                ],
            },
            indent=2,
        )
        + "\n"
    )

    print(f"wrote {len(cases)} perceptual-mask vectors to {HERE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
