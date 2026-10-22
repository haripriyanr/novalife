"""Conformance vectors for `roi_cut_core` (contract: embed.roi_cut over the ROI statistics).

Each vector is a pixel stream; the core counts n, sum, sum of squares of
`where(p <= ROI_STATS_FLOOR, 0, p)` and must output embed.roi_cut(n, s, q) (0..256).
Files: roi_params.vh, roi_len.mem (%08x), roi_pix.mem (%02x, concatenated), roi_exp.mem (%03x).
Run: novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_roi_cut_vectors.py
"""
from __future__ import annotations
import json, sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parents[1] / "stego_research" / "sims"))
import embed  # noqa: E402


def stats(px):
    a = np.where(np.asarray(px) <= embed.ROI_STATS_FLOOR, 0, px).astype(np.int64)
    return int(a.size), int(a.sum()), int((a * a).sum())


def main() -> int:
    rng = np.random.default_rng(20261022)
    cs = []
    def add(name, px):
        px = np.asarray(px, dtype=np.uint8).reshape(-1)
        n, s, q = stats(px)
        cs.append({"name": name, "px": px.tolist(), "exp": embed.roi_cut(n, s, q)})
    add("all zero", np.zeros(64)); add("all 16", np.full(64, 16)); add("all 17", np.full(64, 17))
    add("all 255", np.full(64, 255)); add("const 100", np.full(100, 100)); add("single", [200])
    add("two level", [0] * 50 + [200] * 50); add("ramp", np.arange(256))
    add("bimodal", np.concatenate([rng.integers(0, 20, 500), rng.integers(150, 255, 500)]))
    add("mostly dark", np.concatenate([np.zeros(900), rng.integers(30, 200, 100)]))
    add("one bright", np.concatenate([np.zeros(999), [255]]))
    add("tie-ish", [10, 20, 30, 40] * 25)
    for i in range(24):
        n = int(rng.integers(50, 3000)); hi = int(rng.choice([40, 128, 256]))
        px = rng.integers(0, hi, n)
        px[rng.random(n) < rng.random()] = 0
        add(f"random {i}", px)
    cover = embed.make_cover()[0]
    add("phantom 128x128 crop", cover[:128, :128])
    mri = sorted(Path("/home/user/novalife_covers/mri256").glob("*.jpg"))
    if mri:
        from PIL import Image
        add("mri slice", np.asarray(Image.open(mri[0]).convert("L")))
    (HERE / "roi_len.mem").write_text("".join(f"{len(c['px']):08x}\n" for c in cs))
    (HERE / "roi_pix.mem").write_text("".join(f"{p:02x}\n" for c in cs for p in c["px"]))
    (HERE / "roi_exp.mem").write_text("".join(f"{c['exp']:03x}\n" for c in cs))
    (HERE / "roi_floored.mem").write_text("".join(
        f"{int(p):02x}\n" for c in cs
        for p in embed.floor_background(np.asarray(c["px"], dtype=np.uint8).reshape(1, -1)).reshape(-1)))
    total = sum(len(c["px"]) for c in cs)
    (HERE / "roi_params.vh").write_text(f"localparam ROI_NUM_VECTORS = {len(cs)};\nlocalparam ROI_TOTAL_PIX = {total};\n")
    (HERE / "roi_vectors.json").write_text(json.dumps([{"name": c["name"], "n": len(c["px"]), "exp": c["exp"]} for c in cs], indent=1) + "\n")
    print(f"{len(cs)} vectors, {total} pixels; cuts {sorted(set(c['exp'] for c in cs))[:12]}...")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
