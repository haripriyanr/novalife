"""Real-image benchmark: a real cardiac MRI as the cover, pushed through
chat-app-shaped channels.

The G1 matrix (`run_matrix.py`) uses procedural phantoms so the ROI has a ground truth.  This
one answers the question a reviewer actually asks: *does it work on a real scan, after the image
has been through a chat app?*

It found three things the phantom matrix could not.

1. **A minimum markable size.**  The payload needs 4 regions x 256 eligible 8x8 LL blocks
   outside the ROI, and the pilot grid removes about half the universe.  At the native
   500x282 (a web-scale thumbnail) the scan carries **no** tag at all: 2-4 eligible blocks per
   region against 256 required.  The capacity table reports where it starts to fit.

2. **A clipped-black failure mode, and its cause.**  On the raw scan the tag is placed in the
   MRI's black margin -- the ROI mask pushes it out of the bright subject -- where the pixel
   data is clipped at 0.  JPEG turns those flat near-zero blocks into exact zeros, the decoder
   then reads a constant, and the hard BER goes to ~0.54 in **all four regions**, i.e. worse
   than a coin flip, after even a near-lossless re-encode.  The run below re-runs the identical
   benchmark with **only the black level moved from 0 to 16**: the tag then passes q90/q70/q50.

   The phantom never caught this because `embed.make_cover` deliberately puts fine texture in
   the margin ("so the embeddable area is not flat") and its margin sits at 22, not 0.  That is
   a property of the test image, and it is why a real cover matters.

3. **What a chat app does.**  The channels are **MODELLED**, not real sends: downscale to the
   app's long-edge cap, JPEG re-encode, EXIF strip.  A modelled channel is not a platform
   measurement; only `tools/phase_a_platforms/` produces that, and it needs the owner's phone.

The image is NOT committed (see `tools/stego_research/covers/README.md`): it is passed by path
and its SHA-256 is recorded so the run is comparable.

    novalife_hub/.venv/bin/python tools/tag_reference/run_real_image.py --image <path> [--seeds N]
"""

from __future__ import annotations

import os
import argparse
import hashlib
import io
import json
import platform
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
from iwt_lifting import iwt2d_53  # noqa: E402

import run_demo as demo  # noqa: E402
import run_matrix as matrix  # noqa: E402
from run_demo import compare, sha256_bytes  # noqa: E402

RESULTS_DIR = HERE.parents[1] / "results"
SCHEMA = "novalife/real_image_benchmark/v2"

DEFAULT_IMAGE = os.environ.get("NOVALIFE_REAL_SCAN", "/home/user/novalife_covers/brave_scan.jpg")
DEFAULT_HANDLE_SEEDS = [20261019 + 100 * i for i in range(5)]

CAPACITY_PROBE_EDGES = [282, 565, 848, 1130, 1600, 1800, 2048]
RENDER_LONG_EDGE = 2048

# The three covers the benchmark compares.  `black_lifted` changes exactly one thing compared
# with `raw` -- the pixel black level.  If the clipped-black hypothesis is right, the same image
# must behave completely differently, and that is what makes the diagnosis a measurement.
# `normalised_safe_range` is the *product* answer: an intake normalisation that puts the
# non-diagnostic area inside a range with head-room at both clipping boundaries, so nothing is
# clipped anywhere and the mark has room to move.
BLACK_LIFT = 16
SAFE_LO, SAFE_HI = 16, 235


def _normalise_safe_range(c: np.ndarray) -> np.ndarray:
    c = c.astype(np.float64)
    lo, hi = float(c.min()), float(c.max())
    if hi <= lo:
        return np.full(c.shape, SAFE_LO, dtype=np.uint8)
    return np.clip(np.round(SAFE_LO + (c - lo) * (SAFE_HI - SAFE_LO) / (hi - lo)),
                   0, 255).astype(np.uint8)


VARIANTS = [
    ("raw", "the scan as delivered; large areas of the margin are clipped at 0",
     lambda c: c),
    (f"black_lifted_{BLACK_LIFT}",
     f"identical image with the black level lifted by {BLACK_LIFT} (no clipping at 0)",
     lambda c: np.clip(c.astype(np.int32) + BLACK_LIFT, 0, 255).astype(np.uint8)),
    (f"normalised_safe_range_{SAFE_LO}_{SAFE_HI}",
     f"the scan mapped onto [{SAFE_LO},{SAFE_HI}] -- the intake normalisation this benchmark "
     f"recommends, with head-room at both clipping boundaries",
     _normalise_safe_range),
]


# --------------------------------------------------------------------------- #
# geometry helpers
# --------------------------------------------------------------------------- #


def _resize_long_edge(img: np.ndarray, edge: int) -> np.ndarray:
    """Resize so the long edge is exactly `edge` (up or down); force even dimensions."""
    h, w = img.shape
    s = edge / max(h, w)
    nw, nh = max(2, int(round(w * s))), max(2, int(round(h * s)))
    out = np.asarray(Image.fromarray(img).resize((nw, nh), Image.LANCZOS), dtype=np.uint8)
    return out[: out.shape[0] - out.shape[0] % 2, : out.shape[1] - out.shape[1] % 2]


def _fit_long_edge(img: np.ndarray, edge: int) -> np.ndarray:
    """Downscale so the long edge is at most `edge`; never upscale."""
    if max(img.shape) <= edge:
        return img
    return _resize_long_edge(img, edge)


def _jpeg(img: np.ndarray, quality: int, subsampling: int = 0) -> np.ndarray:
    buf = io.BytesIO()
    Image.fromarray(img).save(buf, "JPEG", quality=quality, subsampling=subsampling)
    buf.seek(0)
    return np.asarray(Image.open(buf).convert("L"), dtype=np.uint8)


def chat_channel(long_edge: int, quality: int):
    def fn(img: np.ndarray) -> np.ndarray:
        return _jpeg(_fit_long_edge(img, long_edge), quality)
    return fn


CHANNELS = [
    ("none", "no attack (lossless round trip)", demo.atk_none, (1.0, 1.0), "the control"),
    ("chat_standard_1600_q75",
     "MODELLED chat app, standard: long edge -> 1600, JPEG q75, EXIF stripped",
     chat_channel(1600, 75), (None, None), "the common case"),
    ("chat_hd_1600_q90",
     "MODELLED chat app, HD: long edge -> 1600, JPEG q90, EXIF stripped",
     chat_channel(1600, 90), (None, None), "same size cap, higher quality"),
    ("chat_small_1280_q85",
     "MODELLED chat app, small profile: long edge -> 1280, JPEG q85",
     chat_channel(1280, 85), (None, None), "a smaller delivery profile"),
    ("jpeg_q50", "JPEG quality 50 at full size", demo.atk_jpeg(50), (1.0, 1.0),
     "requantisation, same geometry"),
    ("jpeg_q40", "JPEG quality 40 at full size", demo.atk_jpeg(40), (1.0, 1.0),
     "aggressive requantisation"),
    ("screenshot_like", "screenshot-like: resize 0.75x then JPEG Q80", demo.atk_screenshot,
     (0.75, 0.75), "resample and re-encode together"),
    ("awgn_sigma2", "AWGN sigma 2", demo.atk_awgn(2.0), (1.0, 1.0), "pixel-domain noise"),
    ("crop_corner_25", "crop 25% off the top and left", demo.atk_crop_corner(0.25), (1.0, 1.0),
     "the open case: a periodic grid cannot locate a crop"),
]


# --------------------------------------------------------------------------- #
# capacity and clipping -- the two diagnostics that explain the result
# --------------------------------------------------------------------------- #


def capacity_table(gray: np.ndarray) -> list[dict]:
    rows = []
    for edge in CAPACITY_PROBE_EDGES:
        g = _resize_long_edge(gray, edge)
        ll, _ = iwt2d_53(g.astype(np.int32))
        ll_shape = tuple(ll.shape)
        roi_blocks, _ = embed.roi_masks(ll_shape, g)
        universe = embed.block_universe(ll_shape)
        cap = embed.region_capacities(universe, roi_blocks, ll_shape)
        rows.append({
            "long_edge": edge,
            "shape": [int(g.shape[0]), int(g.shape[1])],
            "ll_shape": [int(ll_shape[0]), int(ll_shape[1])],
            "universe": len(universe),
            "roi_block_fraction": round(float(roi_blocks.mean()), 4),
            "roi_pixel_fraction": round(float(embed.roi_from_image(g).mean()), 4),
            "capacity_per_region": [int(c) for c in cap],
            "min_capacity": int(min(cap)),
            "blocks_per_region_required": int(embed.BLOCKS_PER_REGION),
            "fits": bool(min(cap) >= embed.BLOCKS_PER_REGION),
        })
    return rows


def clipping_diagnostic(cover: np.ndarray, marked: np.ndarray, placements) -> dict:
    """How much of the marked data sits on a clipped (0 or 255) pixel floor?

    A placement block whose 16x16 pixel support is flat and at the clipping level cannot
    hold the mark: the uint8 reconstruction clips the write away, and a codec turns the
    block into an exact constant.
    """
    mins, means, flat, clipped = [], [], 0, 0
    for order in placements:
        for br, bc in order:
            sup = marked[2 * br:2 * br + 16, 2 * bc:2 * bc + 16]
            if sup.size == 0:
                continue
            mins.append(int(sup.min()))
            means.append(float(sup.mean()))
            if sup.min() == 0 or sup.max() == 255:
                clipped += 1
            if int(sup.max()) - int(sup.min()) <= 1:
                flat += 1
    n = len(mins)
    mins_a = np.asarray(mins)
    return {
        "n_blocks": n,
        "support_pixel_min_median": float(np.median(mins_a)) if n else None,
        "support_pixel_mean_median": round(float(np.median(means)), 2) if n else None,
        "blocks_touching_a_clipping_level": clipped,
        "blocks_touching_a_clipping_level_fraction": round(clipped / n, 4) if n else None,
        "blocks_essentially_flat": flat,
        "blocks_essentially_flat_fraction": round(flat / n, 4) if n else None,
        "note": ("a flat block at the clipping level (pixel min 0 or max 255, range <= 1) "
                 "cannot hold the mark through a re-encode: the codec makes it a constant"),
    }


# --------------------------------------------------------------------------- #
# the run
# --------------------------------------------------------------------------- #


def _git_rev() -> tuple[str | None, bool | None]:
    """The reference revision, so two benchmark runs can be attributed to code versions."""
    try:
        import subprocess

        def run(*a):
            return subprocess.run(["git", "-C", str(HERE), *a], capture_output=True,
                                  text=True, timeout=10).stdout.strip()
        return run("rev-parse", "--short", "HEAD") or None, bool(run("status", "--porcelain"))
    except Exception:
        return None, None


def main() -> int:
    ap = argparse.ArgumentParser(description="Real-image chat-app benchmark (software reference).")
    ap.add_argument("--image", type=str, default=DEFAULT_IMAGE)
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--long-edge", type=int, default=RENDER_LONG_EDGE)
    ap.add_argument("--label", type=str, default="",
                    help="suffix for the output filenames, e.g. --label prefix / postfix")
    ap.add_argument("--no-qr", action="store_true")
    args = ap.parse_args()

    src = Path(args.image)
    if not src.is_file():
        print(f"ERROR: no such image: {src}", file=sys.stderr)
        return 2
    if (matrix.segno is None or matrix.zbar_decode is None) and not args.no_qr:
        print("WARNING: segno/pyzbar missing -> QR baseline skipped", file=sys.stderr)
        args.no_qr = True

    started = time.time()
    rev, dirty = _git_rev()
    raw = src.read_bytes()
    gray_img = Image.open(io.BytesIO(raw)).convert("L")
    native = gray_img.size  # (w, h)

    base = _resize_long_edge(np.asarray(gray_img, dtype=np.uint8), args.long_edge)
    print(f"image     : {src}")
    print(f"sha256    : {sha256_bytes(raw)}")
    print(f"native    : {native[0]}x{native[1]}; marked render {base.shape[1]}x{base.shape[0]}")

    caps = capacity_table(np.asarray(gray_img, dtype=np.uint8))
    min_viable = min((c["long_edge"] for c in caps if c["fits"]), default=None)
    for c in caps:
        print(f"  long_edge {c['long_edge']:5d} -> capacity {c['capacity_per_region']} "
              f"min {c['min_capacity']:4d} need {c['blocks_per_region_required']} "
              f"{'FITS' if c['fits'] else 'no'}")
    print(f"minimum viable long edge: {min_viable}")

    handle_seeds = DEFAULT_HANDLE_SEEDS[: args.seeds]
    variants_out = []
    all_rows: list[dict] = []
    fa_unmarked = {"attempts": 0, "passes": 0}

    for vname, vdesc, vfn in VARIANTS:
        cover = vfn(base)
        drawn = embed.roi_from_image(cover)
        print(f"\n=== variant {vname}: marked {cover.shape[1]}x{cover.shape[0]}, "
              f"algorithm ROI {drawn.mean() * 100:.1f}% of pixels")

        rows: list[dict] = []
        roi_changes, support_violations, fidelity = [], [], []
        clip = {}
        rt_ber, rt_ok = [], []
        avail: list[int] = []
        fa_wrong = {"attempts": 0, "passes": 0}
        cannot_mark: str | None = None

        try:
            embed.mark(cover, drawn,
                       tag_block.build_block(embed.HUB_KEY, tag_block.CURRENT_VERSION,
                                             embed.DEMO_HUB_ID, tag_block.new_handle(0)))
        except ValueError as exc:
            # The reference now refuses to mark an image it cannot mark *survivably* rather
            # than emitting a tag that dies at the first re-encode.  That refusal is a
            # result, not a crash: record it and move to the next variant.
            cannot_mark = str(exc)
            print(f"  REFUSED to mark: {cannot_mark}")
            lsh = (cover.shape[0] // 2, cover.shape[1] // 2)
            cl = embed.clipped_blocks(lsh, cover)
            uni = embed.block_universe(lsh)
            nb = len(uni)
            cnt = sum(1 for br, bc in uni
                      if cl[br // embed.DCT_BLOCK, bc // embed.DCT_BLOCK])
            clip = {
                "n_blocks": nb,
                "blocks_touching_a_clipping_level": int(cnt),
                "blocks_touching_a_clipping_level_fraction": round(cnt / nb, 4) if nb else None,
                "blocks_essentially_flat": None,
                "blocks_essentially_flat_fraction": None,
                "support_pixel_min_median": None,
                "support_pixel_mean_median": None,
                "note": ("cover-level count over the whole universe; no placements exist because "
                         "marking was refused"),
            }

        if cannot_mark is None:
            plain = extract.recover(cover, embed.HUB_KEY, declared_shape=cover.shape)
            fa_unmarked["attempts"] += 1
            fa_unmarked["passes"] += int(bool(plain.tag_ok))

        for hseed in ((handle_seeds) if cannot_mark is None else ()):
            handle = tag_block.new_handle(hseed)
            block = tag_block.build_block(embed.HUB_KEY, tag_block.CURRENT_VERSION,
                                          embed.DEMO_HUB_ID, handle)
            marked, info = embed.mark(cover, drawn, block)
            roi_changes.append(int(info["max_abs_change_inside_algorithm_roi"]))
            support_violations.append(int(info["support_rule_violations"]))
            fidelity.append({**compare(cover, marked), "handle_seed": hseed})
            rt_ber.append(info["round_trip_region_ber"])
            rt_ok.append(bool(info["round_trip_tag_ok"]))
            avail.append(info["blocks_available_per_region"])
            clip = clipping_diagnostic(cover, marked, info["placements"])

            wrong = extract.recover(marked, bytes([0xA5]) * 16, declared_shape=cover.shape,
                                    codeword=info["codeword"])
            fa_wrong["attempts"] += 1
            fa_wrong["passes"] += int(bool(wrong.tag_ok))

            qr_img = (None if args.no_qr
                      else matrix.make_qr_baseline(marked, matrix.qr_payload(handle)))

            line = []
            for name, label, fn, true_scale, note in CHANNELS:
                received = fn(marked)
                rec = extract.recover(received, embed.HUB_KEY, declared_shape=cover.shape,
                                      codeword=info["codeword"])
                exact = bool(np.array_equal(np.asarray(rec.bits, dtype=np.uint8),
                                            np.asarray(block, dtype=np.uint8)))
                row = {
                    "variant": vname, "handle_seed": hseed, "handle": f"0x{handle:016x}",
                    "condition": name,
                    "received_shape": [int(received.shape[0]), int(received.shape[1])],
                    "exact": exact, "tag_ok": bool(rec.tag_ok),
                    "accepted": rec.accepted.label,
                    "failures": [f for f in (getattr(rec, "failures", []) or [])][:4],
                    "pilot_trusted": bool(rec.pilot["trusted"]),
                    "pilot_scale": [rec.pilot["scale_rows"], rec.pilot["scale_cols"]],
                    "region_hard_ber": (None if rec.region_hard_ber is None
                                        else [round(float(b), 4) for b in rec.region_hard_ber]),
                    **compare(marked, received),
                }
                if qr_img is not None:
                    row["qr_decoded"] = matrix.qr_payload(handle) in matrix.decode_qr(fn(qr_img))
                rows.append(row)
                all_rows.append(row)
                line.append(f"{name}:{'Y' if exact and rec.tag_ok else 'n'}")
            print(f"  seed {hseed}: " + " ".join(line))

        summary = []
        for name, label, _fn, true_scale, note in (CHANNELS if cannot_mark is None else ()):
            rs = [r for r in rows if r["condition"] == name]
            n = len(rs)
            s = {
                "condition": name, "label": label, "note": note,
                "true_scale": [true_scale[0], true_scale[1]], "n": n,
                "exact": sum(1 for r in rs if r["exact"]),
                "tag_pass": sum(1 for r in rs if r["tag_ok"]),
                "exact_rate": round(sum(1 for r in rs if r["exact"]) / n, 4) if n else None,
                "mean_psnr_db": matrix.mean_or_none([r["psnr_db"] for r in rs]),
                "mean_ssim": matrix.mean_or_none([r["ssim"] for r in rs]),
                "mean_region_ber": matrix.mean_or_none(
                    [b for r in rs if r["region_hard_ber"] for b in r["region_hard_ber"]]),
            }
            if not args.no_qr:
                s["qr_decoded"] = sum(1 for r in rs if r.get("qr_decoded"))
                s["qr_rate"] = round(s["qr_decoded"] / n, 4) if n else None
            summary.append(s)

        variants_out.append({
            "variant": vname,
            "description": vdesc,
            "cannot_mark": cannot_mark,
            "marked_shape": [int(cover.shape[0]), int(cover.shape[1])],
            "algorithm_roi_pixel_fraction": round(float(drawn.mean()), 4),
            "blocks_available_per_region": avail[0] if avail else None,
            "round_trip_tag_ok": rt_ok,
            "round_trip_region_ber": rt_ber,
            "clipping": clip,
            "roi": {
                "max_abs_change_inside_algorithm_roi": max(roi_changes) if roi_changes else None,
                "support_rule_violations": max(support_violations) if support_violations else None,
                "n_marks": len(roi_changes),
                "zero_everywhere": bool(roi_changes) and all(v == 0 for v in roi_changes),
            },
            "fidelity": {
                "mean_psnr_db": matrix.mean_or_none([f["psnr_db"] for f in fidelity]),
                "mean_ssim": matrix.mean_or_none([f["ssim"] for f in fidelity]),
                "per_handle": fidelity,
            },
            "false_accept_wrong_key": fa_wrong,
            "channels": summary,
        })

    doc = {
        "schema": SCHEMA,
        "generated_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "runtime_seconds": round(time.time() - started, 1),
        "provenance": {
            "kind": "software reference, Python; no board, no FPGA, no real platform send",
            "reference_revision": rev,
            "reference_tree_dirty": dirty,
            "image_path": str(src),
            "image_sha256": sha256_bytes(raw),
            "image_native_shape": [native[1], native[0]],
            "image_note": ("a publicly available illustrative cardiac MRI, supplied by the owner "
                           "from a web image search (2026-10-19). De-identified, not a hospital "
                           "record, no patient data. NOT committed to the repo -- see "
                           "tools/stego_research/covers/README.md; passed by path and pinned by "
                           "SHA-256 so the run is comparable."),
            "channels_note": ("MODELLED chat-app channels, NOT real sends: long-edge downscale + "
                              "JPEG re-encode + EXIF strip. Only tools/phase_a_platforms/ can "
                              "measure a real platform, and it needs the owner's phone."),
            "python": platform.python_version(),
            "numpy": np.__version__,
            "pillow": Image.__version__,
            "segno": None if matrix.segno is None else matrix.segno.__version__,
            "qr_decoder": "pyzbar + libzbar" if matrix.zbar_decode is not None else None,
        },
        "cover_render": {
            "native_shape": [native[1], native[0]],
            "marked_shape": [int(base.shape[0]), int(base.shape[1])],
            "long_edge": int(max(base.shape)),
            "reason": ("the payload needs 4 x BLOCKS_PER_REGION eligible LL blocks outside the "
                       "ROI and the pilot grid removes about half the universe; the native "
                       "thumbnail is far too small (see the capacity table)"),
        },
        "capacity": {
            "blocks_per_region_required": int(embed.BLOCKS_PER_REGION),
            "regions": int(embed.N_REGIONS),
            "pilot_interval_g": int(embed.PILOT_INTERVAL_G),
            "min_viable_long_edge": min_viable,
            "table": caps,
        },
        "parameters": {
            "handle_seeds": handle_seeds,
            "variants": [v[0] for v in VARIANTS],
            "channels": [c[0] for c in CHANNELS],
            "thresholds": ("NOT YET AGREED with the professor; this file reports rates and does "
                           "not declare pass/fail"),
        },
        "false_accept_unmarked_image": {
            "attempts": fa_unmarked["attempts"], "passes": fa_unmarked["passes"]},
        "false_accept_theoretical_per_attempt": 2.0 ** -48,
        "variants": variants_out,
        "rows": all_rows,
    }

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    suffix = "" if args.seeds >= len(DEFAULT_HANDLE_SEEDS) else f"_s{args.seeds}"
    if args.label:
        suffix += f"_{args.label}"
    json_path = RESULTS_DIR / f"real_image_benchmark_{date}{suffix}.json"
    md_path = RESULTS_DIR / f"real_image_benchmark_{date}{suffix}.md"
    json_path.write_text(json.dumps(doc, indent=2, default=str))
    md_path.write_text(write_markdown(doc))
    print(f"\nwrote {json_path}\nwrote {md_path}")

    for v in variants_out:
        print("\n" + "=" * 78)
        print(f"variant {v['variant']}: {v['description']}")
        print(f"{'condition':<24} {'tag pass':>9} {'exact':>7} {'QR':>5}  mean PSNR/SSIM")
        for s in v["channels"]:
            qr = f"{s.get('qr_decoded', 0)}/{s['n']}" if not args.no_qr else "-"
            print(f"{s['condition']:<24} {s['tag_pass']:>4}/{s['n']:<4} {s['exact']:>4}/{s['n']:<2} "
                  f"{qr:>5}  {s['mean_psnr_db']} dB / {s['mean_ssim']}")
        c = v["clipping"]
        print(f"  clipping: {c['blocks_touching_a_clipping_level']}/{c['n_blocks']} placement "
              f"blocks touch a clipping level "
              f"({100*c['blocks_touching_a_clipping_level_fraction']:.1f}%)")
    return 0


# --------------------------------------------------------------------------- #
# report
# --------------------------------------------------------------------------- #


def _clip_bullet(c: dict | None) -> str:
    """One bullet for the clipping diagnostic, safe when marking was refused."""
    if not c or not c.get("n_blocks"):
        return "- **clipping diagnostic**: not available"
    frac = c.get("blocks_touching_a_clipping_level_fraction")
    txt = (f"- **clipping diagnostic**: {c['blocks_touching_a_clipping_level']}/"
           f"{c['n_blocks']} blocks ({100 * frac:.1f}%) touch a pixel clipped at 0 or 255")
    if c.get("blocks_essentially_flat_fraction") is not None:
        txt += (f"; {c['blocks_essentially_flat']} "
                f"({100 * c['blocks_essentially_flat_fraction']:.1f}%) are essentially flat; "
                f"median support pixel min {c['support_pixel_min_median']:.0f}, median support "
                f"mean {c['support_pixel_mean_median']:.0f}")
    if c.get("note"):
        txt += f" ({c['note']})"
    return txt


def write_markdown(doc: dict) -> str:
    p, cap = doc["provenance"], doc["capacity"]
    L: list[str] = []
    a = L.append
    a("# Real-image benchmark — a real cardiac MRI through chat-app-shaped channels")
    a("")
    a(f"*Generated {doc['generated_utc']} in {doc['runtime_seconds']} s. "
      f"Schema `{doc['schema']}`; reference `{p.get('reference_revision')}`"
      f"{' (working tree dirty)' if p.get('reference_tree_dirty') else ''}.*")
    a("")
    a("> **Software reference only.** No board, no FPGA, no real platform send. The chat-app")
    a("> channels are **MODELLED** from documented behaviour, not measured on a phone.")
    a("")
    a("## Headline")
    a("")
    a(f"- The native scan ({p['image_native_shape'][1]}x{p['image_native_shape'][0]}) **cannot")
    a(f"  carry the tag at all**: a few eligible LL blocks per region against "
      f"{cap['blocks_per_region_required']} required. It is marked here at ")
    a(f"  **{doc['cover_render']['marked_shape'][1]}x{doc['cover_render']['marked_shape'][0]}** "
      f"(minimum viable long edge on this scan: **{cap['min_viable_long_edge']} px**).")
    for v in doc["variants"]:
        if v.get("cannot_mark"):
            a(f"- **`{v['variant']}`: the reference REFUSES to mark it.**")
            a("  " + _clip_bullet(v["clipping"])[2:].strip())
            a(f"  Reason recorded by `embed.mark`: *{v['cannot_mark']}*")
        else:
            fails = [s["condition"] for s in v["channels"] if s["tag_pass"] < s["n"]]
            ok = sum(1 for s in v["channels"] if s["tag_pass"] == s["n"])
            a(f"- **`{v['variant']}`: marked, and the tag survives {ok}/{len(v['channels'])}")
            a(f"  channels** (lossless control "
              f"{'passes' if v['round_trip_tag_ok'] else 'FAILS'} at region BER "
              f"{v['round_trip_region_ber'][0]})."
              + (f" Fails: {', '.join('`' + c + '`' for c in fails)}."
                 if fails else " Every channel passes."))
    a("")
    a("The phantom covers never caught the clipping failure because `embed.make_cover` puts")
    a("deliberate texture in its margin (\"so the embeddable area is not flat\") and its margin")
    a("sits at 22, not 0. That is a property of the test image, not of the algorithm.")
    a("")
    a("## The image")
    a("")
    a(f"- path `{p['image_path']}` (not committed; see "
      "`tools/stego_research/covers/README.md`)")
    a(f"- sha256 `{p['image_sha256']}`")
    a(f"- {p['image_note']}")
    a("")
    a("## Capacity study — why the size had to change")
    a("")
    a(f"Payload: {cap['regions']} regions x **{cap['blocks_per_region_required']}** eligible LL")
    a(f"blocks (one per codeword bit); the pilot grid every {cap['pilot_interval_g']} LL")
    a("coefficients removes roughly half the universe.")
    a("")
    a("| long edge | shape | LL | universe | ROI blocks | capacity/region | min | fits |")
    a("|---|---|---|---|---|---|---|---|")
    for c in cap["table"]:
        a(f"| {c['long_edge']} | {c['shape'][1]}x{c['shape'][0]} | "
          f"{c['ll_shape'][0]}x{c['ll_shape'][1]} | {c['universe']} | "
          f"{c['roi_block_fraction']:.3f} | {c['capacity_per_region']} | "
          f"{c['min_capacity']} | {'**yes**' if c['fits'] else 'no'} |")
    a("")
    a("## The variants")
    a("")
    for v in doc["variants"]:
        a(f"### `{v['variant']}` — {v['description']}")
        a("")
        if v.get("cannot_mark"):
            a("**`embed.mark` refused this input.** It will not emit a tag it cannot prove")
            a("survives a single re-encode:")
            a("")
            a("```")
            a(v["cannot_mark"])
            a("```")
            a("")
            a(f"- marked at {v['marked_shape'][1]}x{v['marked_shape'][0]}; the algorithm ROI is "
              f"{v['algorithm_roi_pixel_fraction'] * 100:.1f}% of pixels")
            a(_clip_bullet(v["clipping"]))
            a("- no channels were run: there is no marked image to attack")
            a("")
            continue
        a(f"- marked at {v['marked_shape'][1]}x{v['marked_shape'][0]}; the algorithm ROI is "
          f"{v['algorithm_roi_pixel_fraction'] * 100:.1f}% of pixels; eligible blocks per region "
          f"{v['blocks_available_per_region']} against "
          f"{cap['blocks_per_region_required']} needed")
        a(f"- lossless round trip: tag OK {v['round_trip_tag_ok']}, region BER "
          f"{v['round_trip_region_ber'][0]}")
        a(_clip_bullet(v["clipping"]))
        a(f"- marking cost: PSNR **{v['fidelity']['mean_psnr_db']} dB**, SSIM "
          f"**{v['fidelity']['mean_ssim']}**")
        a(f"- ROI: max change inside the algorithm ROI over {v['roi']['n_marks']} marks = "
          f"**{v['roi']['max_abs_change_inside_algorithm_roi']}**"
          f"{' (zero everywhere)' if v['roi']['zero_everywhere'] else ' (NOT zero)'}; "
          f"pixel-support violations {v['roi']['support_rule_violations']}")
        a(f"- false accept with the wrong key: {v['false_accept_wrong_key']['passes']} PASS in "
          f"{v['false_accept_wrong_key']['attempts']} attempts")
        a("")
        hdr = ("| condition | what it is | tag PASS | exact 128-bit | mean PSNR | mean SSIM | "
               "mean region BER |")
        sep = "|---|---|---|---|---|---|---|"
        if any("qr_decoded" in s for s in v["channels"]):
            hdr += " QR |"
            sep += "---|"
        a(hdr)
        a(sep)
        for s in v["channels"]:
            qr = f" {s.get('qr_decoded')}/{s['n']} |" if "qr_decoded" in s else ""
            a(f"| `{s['condition']}` | {s['note']} | **{s['tag_pass']}/{s['n']}** | "
              f"{s['exact']}/{s['n']} | {s['mean_psnr_db']} | {s['mean_ssim']} | "
              f"{s['mean_region_ber']} |{qr}")
        a("")
    a("## False accept")
    a("")
    a(f"- never-marked image: {doc['false_accept_unmarked_image']['passes']} PASS in "
      f"{doc['false_accept_unmarked_image']['attempts']}")
    a("- theoretical per attempt: 2^-48; the stated server rate limit bounds online guessing")
    a("")
    a("## Thresholds")
    a("")
    a(doc["parameters"]["thresholds"])
    a("")
    a("## What this run does and does not show")
    a("")
    a("- **Does**: measure a real de-identified scan end to end, locate a failure mode the")
    a("  synthetic covers hid because they were built to be embeddable, and isolate the cause")
    a("  with a one-variable experiment (black level 0 -> "
      f"{BLACK_LIFT}).")
    a("- **Does not**: prove anything about a real WhatsApp/Telegram send. That is Phase A")
    a("  (`tools/phase_a_platforms/`), which needs the owner's phone and reports on real files.")
    a("- The reference now **refuses** an input it cannot mark survivably (`embed.clipped_blocks`")
    a("  plus the loud `ValueError` in `embed.mark`) instead of silently emitting a dead tag. It")
    a("  goes further than refusing: clipped blocks are tainted alongside the ROI in *both* the")
    a("  encoder and the decoder (`embed.blocked_blocks`), so a frame with enough clean area is")
    a("  marked in the clean area rather than in a clipped margin.")
    a("- The clipping taint is **bit-identical on every phantom cover** (proven, not assumed:")
    a("  same masks, same capacity, same marked-image SHA-256, same BER and the same tag verdict")
    a("  against the previous revision), so `results/tag_matrix_2026-10-19.*` still stands.")
    a("- The product-side fix for a clipped input is **amplitude normalisation at intake** of the")
    a("  non-diagnostic area; the transform itself is unchanged. Not a product change yet.")
    a("- The marked render is large; a real chat app's downscale is modelled with Pillow")
    a("  LANCZOS, and a phone's encoder is not Pillow.")
    a("")
    a("## Provenance")
    a("")
    a(f"- reference revision `{p.get('reference_revision')}`"
      f"{' (working tree dirty)' if p.get('reference_tree_dirty') else ''}")
    for k in ("python", "numpy", "pillow", "segno", "qr_decoder"):
        a(f"- {k}: `{p[k]}`")
    a("- generation: `novalife_hub/.venv/bin/python tools/tag_reference/run_real_image.py "
      "--image <path> [--label <suffix>]`")
    a("")
    return "\n".join(L)


if __name__ == "__main__":
    raise SystemExit(main())
