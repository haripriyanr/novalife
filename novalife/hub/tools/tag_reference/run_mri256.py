#!/usr/bin/env python3
"""256 x 256 patient MRI slices: can RPP-QIM mark them, and how?

    novalife_hub/.venv/bin/python tools/tag_reference/run_mri256.py [--dir DIR] [--scales 4 6]

Images: 8 real, de-identified brain MRI slices (2 per class: glioma, meningioma, pituitary, no
tumour) from Kaggle `thomasdubail/brain-tumors-256x256` (CC0; the curator already JPEG-compressed,
histogram-normalised and resized them to 256 x 256).  Kept outside the repository at
/home/user/novalife_covers/mri256 with SHA256SUMS; not committed.

Per slice:
  1. native 256 x 256: mark, or record the refusal and the usable blocks per region;
  2. the SHARE COPY the hub would export, at k x nearest-neighbour (every original pixel becomes a
     k x k block of the same value, so diagnostic values are unchanged), in two variants:
       plain        -- the enlarged slice as is
       bg_floor16   -- background pixels OUTSIDE the slice's diagnostic region raised to >= 16, so
                       the black background is no longer clipped; brain pixels are not touched;
  3. for the first markable variant at the smallest scale: the 9 modelled chat-app channels of
     run_real_image.py, exact 128-bit recovery, the wrong-key false accept, PSNR/SSIM against the
     share copy before marking, and the maximum change inside the ORIGINAL diagnostic region.
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "stego_research" / "sims"))

import embed  # noqa: E402
import extract  # noqa: E402
import tag_block  # noqa: E402
import run_real_image as rri  # noqa: E402

RESULTS = HERE.parents[1] / "results"
FLOOR = 16


def nearest(img: np.ndarray, k: int) -> np.ndarray:
    return np.repeat(np.repeat(img, k, axis=0), k, axis=1)


def bg_floor(img: np.ndarray, floor: int = FLOOR) -> tuple[np.ndarray, np.ndarray]:
    """Raise background pixels outside the diagnostic region to >= floor; brain untouched."""
    return embed.floor_background(img), embed.roi_from_image(img).astype(bool)


def capacity(img: np.ndarray) -> list[int]:
    lsh = (img.shape[0] // 2, img.shape[1] // 2)
    roi_blocks, _ = embed.roi_masks(lsh, img)
    blocked = np.asarray(roi_blocks, bool) | embed.clipped_blocks(lsh, img)
    return list(embed.region_capacities(embed.block_universe(lsh), blocked, lsh))[:1]


def try_mark(img: np.ndarray, block: np.ndarray):
    drawn = embed.roi_from_image(img)
    try:
        return embed.mark(img, drawn, block), None
    except ValueError as exc:
        return None, str(exc).split(";")[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="/home/user/novalife_covers/mri256")
    ap.add_argument("--scales", type=int, nargs="+", default=[1, 2, 4])
    args = ap.parse_args()
    t0 = time.time()
    files = sorted(glob.glob(os.path.join(args.dir, "*.jpg")))
    block = tag_block.build_block(embed.HUB_KEY, tag_block.CURRENT_VERSION, embed.DEMO_HUB_ID,
                                  tag_block.new_handle(0))
    need = embed.BLOCKS_PER_REGION
    doc = {"generated_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "dataset": "kaggle thomasdubail/brain-tumors-256x256 (CC0), 8 slices",
           "blocks_needed_per_region": need, "slices": []}

    for f in files:
        name = os.path.basename(f)
        raw = np.asarray(Image.open(f).convert("L"), dtype=np.uint8)
        sha = hashlib.sha256(open(f, "rb").read()).hexdigest()
        rec = {"file": name, "sha256": sha, "shape": list(raw.shape),
               "pixels_at_0_pct": round(float(np.mean(raw == 0)) * 100, 1),
               "roi_pct": round(float(embed.roi_from_image(raw).mean()) * 100, 1),
               "native": {"capacity_floored": capacity(embed.floor_background(raw))}, "share": []}
        _, why = try_mark(embed.floor_background(raw), block)
        rec["native"]["markable"] = why is None
        rec["native"]["refusal"] = why
        print(f"--- {name}: native (floored) capacity {rec['native']['capacity_floored']} (need {need}) "
              f"-> {'MARKABLE' if why is None else 'refused'}", flush=True)

        chosen = None
        for k in args.scales:
            up = nearest(raw, k)
            for vname, img in (("plain", up), ("bg_floor16", bg_floor(up)[0])):
                cap = capacity(img)
                ok = min(cap) >= need
                rec["share"].append({"scale": k, "variant": vname, "size": list(img.shape),
                                     "capacity": cap, "markable": ok})
                print(f"    {k}x {vname:<10} {img.shape[1]}x{img.shape[0]} capacity {cap} "
                      f"-> {'markable' if ok else 'too small'}", flush=True)
                if ok and chosen is None:
                    chosen = (k, vname, img, up)
        if chosen is None:
            doc["slices"].append(rec)
            continue

        k, vname, cover, up = chosen
        orig_roi = embed.roi_from_image(up).astype(bool)        # diagnostic region of the share copy
        got, why = try_mark(cover, block)
        if got is None:
            rec["run"] = {"scale": k, "variant": vname, "refusal": why}
            doc["slices"].append(rec)
            continue
        marked, info = got
        diff = np.abs(marked.astype(int) - up.astype(int))
        run = {"scale": k, "variant": vname, "size": list(cover.shape),
               "max_change_inside_original_roi": int(diff[orig_roi].max()) if orig_roi.any() else 0,
               "background_pixels_floored": int(np.sum(cover != up)),
               **{f"mark_{a}": b for a, b in rri.compare(up, marked).items()},
               "round_trip_tag_ok": bool(info["round_trip_tag_ok"]), "channels": []}
        wrong = extract.recover(marked, bytes([0xA5]) * 16, declared_shape=cover.shape,
                                codeword=info["codeword"])
        run["wrong_key_tag_pass"] = bool(wrong.tag_ok)
        line = []
        for cname, label, fn, _scale, _note in rri.CHANNELS:
            t1 = time.time()
            received = fn(marked)
            r = extract.recover(received, embed.HUB_KEY, declared_shape=cover.shape,
                                codeword=info["codeword"])
            exact = bool(np.array_equal(np.asarray(r.bits, dtype=np.uint8),
                                        np.asarray(block, dtype=np.uint8)))
            run["channels"].append({"condition": cname, "received_shape": list(received.shape),
                                    "exact": exact, "tag_ok": bool(r.tag_ok),
                                    "seconds": round(time.time() - t1, 1)})
            line.append(f"{cname}:{'Y' if exact and r.tag_ok else 'n'}")
        print(f"    RUN {k}x {vname}: roi_change={run['max_change_inside_original_roi']} "
              f"psnr={run.get('mark_psnr_db')} " + " ".join(line), flush=True)
        rec["run"] = run
        doc["slices"].append(rec)

    doc["runtime_s"] = round(time.time() - t0, 1)
    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    out = RESULTS / f"mri256_{date}.json"
    out.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"wrote {out} in {doc['runtime_s']} s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
