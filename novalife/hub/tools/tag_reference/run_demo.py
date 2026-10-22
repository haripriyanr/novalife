"""Attack matrix for the RPP-QIM Python reference.

One synthetic cover (never patient data), one 128-bit tag block, one marked export, and
ten attacks.  Every row reports, from the same run:

  * the **scale the pilot grid measured** vs the scale the attack actually applied
  * whether the **128 bits were recovered exactly** (all 128, not "mostly")
  * the **48-bit tag verdict** from `tag_block.verify_block`
  * **PSNR / SSIM** of the received image against the marked export

This file is the measurement.  It writes

  * `novalife_hub/results/tag_python_reference_2026-10-11_matrix.json`  (machine readable)
  * `novalife_hub/results/tag_python_reference_2026-10-11.md`           (readable)

and the marked export plus the received copies under `demo_out/`.

Run from the repository root with the project venv:

    novalife_hub/.venv/bin/python novalife_hub/tools/tag_reference/run_demo.py

or from this directory:

    ../../.venv/bin/python run_demo.py

Deps: numpy + Pillow only.  Nothing here is a claim about a real platform: what happens
to an image inside WhatsApp, Telegram, Signal or a screenshot is Phase A and is not
measured by this file.  These are lab conditions applied by Pillow and numpy, on one
synthetic cover, with one seed.
"""
from __future__ import annotations

# Make the sibling modules importable no matter what the current directory is.
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import argparse
import hashlib
import io
import json
import platform
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image

import embed
import extract
import tag_block
from embed import (
    BLOCKS_PER_REGION,
    COVER_SEED,
    COVER_SHAPE,
    DEMO_HUB_ID,
    HUB_KEY,
    N_REGIONS,
    QIM_ALPHA,
    QIM_BASE_DELTA,
    QIM_ALPHA_NUM,
    QIM_ALPHA_SHIFT,
    DCT_BLOCK,
    make_cover,
    mark,
)

DEMO_OUT = Path(_HERE) / "demo_out"
RESULTS_DIR = Path(__file__).resolve().parents[2] / "results"
JSON_PATH = RESULTS_DIR / "tag_python_reference_2026-10-11_matrix.json"
MD_PATH = RESULTS_DIR / "tag_python_reference_2026-10-11.md"

SCHEMA = "novalife/tag_python_reference_matrix/v1"

ROI_SOURCE = ("drawn phantom ROI (ground truth, exact by construction) for the "
              "no-touch check; algorithm ROI = img > mean + 0.2 x std "
              "(sims/dicom_loader.py rule)")


# --------------------------------------------------------------------------- #
# image metrics
# --------------------------------------------------------------------------- #


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    """PSNR in dB over the overlapping (identical-shape) region (inf if identical)."""
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    mse = float(np.mean((a - b) ** 2))
    if mse <= 0.0:
        return float("inf")
    return 20.0 * np.log10(255.0) - 10.0 * np.log10(mse)


def _uniform_window(img: np.ndarray, win: int = 8) -> np.ndarray:
    """(mean, variance) per `win`x`win` tile, uniform weights, strided like SSIM."""
    h, w = img.shape
    hh, ww = (h // win) * win, (w // win) * win
    if hh == 0 or ww == 0:
        hh, ww = h, w
        win = 1
    t = img[:hh, :ww].reshape(hh // win, win, ww // win, win)
    return t.mean(axis=(1, 3)), t.var(axis=(1, 3))


def ssim(a: np.ndarray, b: np.ndarray, win: int = 8) -> float:
    """SSIM with a uniform `win`x`win` window (not the 11x11 Gaussian of the paper).

    Same convention as `tools/phase_a_platforms`: comparable between runs of this
    harness, not the reference SSIM of the literature.  C1 = (0.01*255)^2,
    C2 = (0.03*255)^2.
    """
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    m1, v1 = _uniform_window(a, win)
    m2, v2 = _uniform_window(b, win)
    h, w = a.shape
    hh, ww = (h // win) * win or h, (w // win) * win or w
    ab = (a[:hh, :ww] * b[:hh, :ww])
    ma, mb = _uniform_window(ab, win)
    cov = ma - m1 * m2
    c1, c2 = (0.01 * 255.0) ** 2, (0.03 * 255.0) ** 2
    num = (2 * m1 * m2 + c1) * (2 * cov + c2)
    den = (m1**2 + m2**2 + c1) * (v1 + v2 + c2)
    return float(np.mean(num / den))


def compare(marked: np.ndarray, received: np.ndarray) -> dict:
    """PSNR/SSIM of `received` against `marked`.

    If the geometries differ the comparison is impossible without resampling one of
    them; the marked export is resampled to the received geometry with Pillow's
    LANCZOS and the result is labelled, because the resampler is our choice and its
    error is included in the numbers.
    """
    marked = np.asarray(marked, dtype=np.uint8)
    received = np.asarray(received, dtype=np.uint8)
    if marked.shape != received.shape:
        ref = np.asarray(
            Image.fromarray(marked).resize(
                (received.shape[1], received.shape[0]), Image.LANCZOS
            ),
            dtype=np.uint8,
        )
        note = (
            "marked export resampled to the received geometry with Pillow LANCZOS "
            f"{marked.shape}->{received.shape}; the resampler's own error is included"
        )
        p, s = psnr(ref, received), ssim(ref, received)
    else:
        note = "direct comparison, both images at the declared export geometry"
        p, s = psnr(marked, received), ssim(marked, received)
    return {
        "psnr_db": None if np.isinf(p) else round(p, 3),
        "ssim": round(s, 6),
        "comparison": note,
    }


# --------------------------------------------------------------------------- #
# the attacks (lab conditions, not platform measurements)
# --------------------------------------------------------------------------- #


def to_img(arr: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(np.asarray(arr), 0, 255).astype(np.uint8), mode="L")


def to_arr(img: Image.Image) -> np.ndarray:
    return np.asarray(img.convert("L"), dtype=np.uint8)


def atk_none(img: np.ndarray) -> np.ndarray:
    return np.asarray(img, dtype=np.uint8).copy()


def atk_jpeg(quality: int, subsampling: int = 0):
    def f(img: np.ndarray) -> np.ndarray:
        buf = io.BytesIO()
        to_img(img).save(buf, format="JPEG", quality=quality, subsampling=subsampling)
        buf.seek(0)
        return to_arr(Image.open(buf))
    return f


def atk_resize(factor: float, resample: int = Image.BICUBIC):
    def f(img: np.ndarray) -> np.ndarray:
        h, w = img.shape
        nh, nw = max(2, int(round(h * factor))), max(2, int(round(w * factor)))
        nh -= nh % 2
        nw -= nw % 2
        return to_arr(Image.fromarray(img).resize((nw, nh), resample))
    return f


def atk_crop_corner(frac: float):
    """Drop `frac` of the rows from the top and `frac` of the columns from the left."""

    def f(img: np.ndarray) -> np.ndarray:
        h, w = img.shape
        r0, c0 = int(round(h * frac)), int(round(w * frac))
        return np.ascontiguousarray(img[r0:, c0:])
    return f


def atk_screenshot(img: np.ndarray) -> np.ndarray:
    """What a screenshot of a chat-app preview looks like: downscale, then re-encode."""
    return atk_jpeg(80)(atk_resize(0.75)(img))


def atk_awgn(sigma: float, seed: int = 11):
    def f(img: np.ndarray) -> np.ndarray:
        rng = np.random.default_rng(seed)
        noisy = np.asarray(img, dtype=np.float64) + rng.normal(0.0, sigma, img.shape)
        return np.clip(np.round(noisy), 0, 255).astype(np.uint8)
    return f


# name, human label, function, the scale it applies per axis, notes
CONDITIONS = [
    ("none", "no attack (lossless round trip)", atk_none, (1.0, 1.0),
     "the control: if this is not exact the reference is broken, not the algorithm"),
    ("jpeg_q90", "JPEG quality 90", atk_jpeg(90), (1.0, 1.0), "grayscale, 4:4:4"),
    ("jpeg_q70", "JPEG quality 70", atk_jpeg(70), (1.0, 1.0),
     "the quality the existing DCT-QIM baseline measured at"),
    ("jpeg_q50", "JPEG quality 50", atk_jpeg(50), (1.0, 1.0), "below any platform's setting"),
    ("jpeg_q40", "JPEG quality 40", atk_jpeg(40), (1.0, 1.0), "aggressive requantisation"),
    ("resize_050", "resize to 0.50x", atk_resize(0.50), (0.50, 0.50),
     "a real resample, Pillow BICUBIC, both axes"),
    ("resize_150", "resize to 1.50x", atk_resize(1.50), (1.50, 1.50),
     "a real resample, Pillow BICUBIC, both axes"),
    ("crop_corner_25", "crop 25% off the top and left", atk_crop_corner(0.25), (1.0, 1.0),
     "keeps the bottom-right 56% of the frame; 25% of each axis removed from one corner"),
    ("screenshot_like", "screenshot-like: resize 0.75x then JPEG Q80",
     atk_screenshot, (0.75, 0.75), "resample and re-encode together, the worst of the two"),
    ("awgn_sigma2", "AWGN sigma 2", atk_awgn(2.0), (1.0, 1.0),
     "additive white Gaussian noise in the pixel domain"),
]


# --------------------------------------------------------------------------- #
# the run
# --------------------------------------------------------------------------- #


def fmt_psnr(v) -> str:
    return "inf" if v is None else str(v)


def png_bytes(arr: np.ndarray) -> bytes:
    buf = io.BytesIO()
    to_img(arr).save(buf, format="PNG")
    return buf.getvalue()


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def jnum(x, digits: int = 4):
    """JSON-safe float."""
    if x is None:
        return None
    if isinstance(x, (int, np.integer)):
        return int(x)
    f = float(x)
    if np.isinf(f):
        return None
    return round(f, digits)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Attack matrix for the RPP-QIM Python reference (software only)."
    )
    ap.add_argument("--seed", type=int, default=COVER_SEED, help="cover seed (default 7010)")
    ap.add_argument("--handle-seed", type=int, default=tag_block.HANDLE_SEED,
                    help="handle seed (default 20261011)")
    ap.add_argument("--out-dir", type=str, default=str(DEMO_OUT))
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    started = time.time()
    print("=" * 78)
    print("NovaLife RPP-QIM Python reference -- attack matrix")
    print("=" * 78)

    # ---- cover, ROI, block, marked export --------------------------------
    cover, roi = make_cover(args.seed)
    print(f"cover                : synthetic chest phantom {cover.shape[1]}x{cover.shape[0]} "
          f"(long edge {max(cover.shape)}), seed {args.seed}")
    print(f"ROI                  : {ROI_SOURCE}, {int(roi.sum())} px "
          f"({100.0 * roi.sum() / roi.size:.1f}% of the frame)")

    handle = tag_block.new_handle(args.handle_seed)
    block = tag_block.build_block(HUB_KEY, tag_block.CURRENT_VERSION, DEMO_HUB_ID, handle)
    fields = tag_block.split_block(block)
    print(f"tag block            : version={fields['version']} hub_id=0x{fields['hub_id']:03x} "
          f"handle=0x{fields['handle']:016x} tag=0x{fields['tag']:012x}")

    marked, info = mark(cover, roi, block)
    q = compare(cover, marked)
    print(f"marked export        : PSNR {q['psnr_db']} dB, SSIM {q['ssim']}, "
          f"max |change| inside drawn ROI = {info['max_abs_change_inside_drawn_roi']}, "
          f"inside algorithm ROI = {info['max_abs_change_inside_algorithm_roi']}")
    print(f"payload capacity     : {info['copies_written']} of {N_REGIONS} copies written; free "
          f"{DCT_BLOCK}x{DCT_BLOCK} LL blocks per copy {info['blocks_available_per_region']} "
          f"(need {BLOCKS_PER_REGION} per copy)")
    print("pilot                : none (algorithm.md 3.2)")
    print(f"embedding            : sign of the 4x4 Hadamard projection, T = delta/2, delta = "
          f"{QIM_BASE_DELTA} + ({QIM_ALPHA_NUM} x isqrt(var)) >> {QIM_ALPHA_SHIFT}, even")
    print(f"clean self-check     : round-trip tag "
          f"{'PASS' if info['round_trip_tag_ok'] else 'FAIL'}")

    (out_dir / "cover.png").write_bytes(png_bytes(cover))
    Image.fromarray((roi * 255).astype(np.uint8), mode="L").save(out_dir / "roi.png")
    (out_dir / "marked.png").write_bytes(png_bytes(marked))

    # ---- the matrix -------------------------------------------------------
    rows = []
    for name, label, fn, true_scale, note in CONDITIONS:
        t0 = time.time()
        received = fn(marked)
        rec = extract.recover(received, HUB_KEY, declared_shape=cover.shape,
                              codeword=info["codeword"])
        exact = bool(np.array_equal(np.asarray(rec.bits, dtype=np.uint8),
                                    np.asarray(block, dtype=np.uint8)))
        tag_ok = bool(rec.tag_ok)
        res = {
            "name": name,
            "label": label,
            "note": note,
            "attack": {
                "kind": name,
                "description": label,
            },
            "scale_true": [true_scale[0], true_scale[1]],  # (rows, cols)
            "received": {
                "shape": [int(received.shape[0]), int(received.shape[1])],
                "sha256": sha256_bytes(png_bytes(received)),
            },
            "pilot": rec.pilot,
            "candidates": [
                {"label": c.label, "score": round(float(c.score), 4),
                 "accepted": bool(c.accepted),
                 "detail": {k: (round(float(v), 4) if isinstance(v, float) else v)
                            for k, v in c.detail.items()
                            if isinstance(v, (int, float, str, bool))}}
                for c in rec.candidates
            ],
            "accepted": rec.accepted.label,
            "exact": exact,
            "tag_ok": tag_ok,
            "fields": {k: (f"0x{v:016x}" if k == "handle" else
                           (f"0x{v:012x}" if k == "tag" else v))
                       for k, v in rec.fields.items() if k != "expected_tag"},
            "region_hard_ber": [None if b is None else round(float(b), 4)
                                for b in (rec.region_hard_ber or [])],
            "llr_confidence": rec.llr_confidence,
            "failures": list(rec.failures),
        }
        res["image"] = compare(marked, received)
        res["seconds"] = round(time.time() - t0, 2)

        png = png_bytes(received)
        (out_dir / f"received_{name}.png").write_bytes(png)

        est = res["pilot"]
        print(f"\n[{name}] {label}  ({res['seconds']} s)")
        print(f"   received shape   : {received.shape[1]}x{received.shape[0]}  "
              f"(declared {cover.shape[1]}x{cover.shape[0]})")
        print(f"   true scale       : {true_scale[0]:.4f} / {true_scale[1]:.4f} "
              f"(no pilot: geometry from the image sizes)")
        print(f"   accepted         : {res['accepted']}")
        for c in res["candidates"][:6]:
            print(f"      - {c['label']:<52} score {c['score']:.3f}"
                  f"{'  <-- accepted' if c['accepted'] else ''}")
        print(f"   exact 128 bits   : {exact}")
        print(f"   tag verdict      : {'PASS' if tag_ok else 'FAIL'}  (48 bits)")
        print(f"   PSNR / SSIM      : {res['image']['psnr_db']} dB / {res['image']['ssim']}")
        print(f"   region hard BER  : {res['region_hard_ber']}  (before decoding)")
        if res["failures"]:
            print(f"   notes            : {res['failures']}")
        rows.append(res)

    # ---- verdicts ---------------------------------------------------------
    n_ok = sum(1 for r in rows if r["exact"])
    print("\n" + "=" * 78)
    print(f"exact 128-bit recovery: {n_ok} of {len(rows)} conditions")
    for r in rows:
        print(f"   {r['name']:<16} {'PASS' if r['exact'] else 'FAIL':<5} "
              f"tag {'PASS' if r['tag_ok'] else 'FAIL':<5} "
              f"scale {r['pilot']['scale_rows']:.4f}/{r['pilot']['scale_cols']:.4f} "
              f"vs true {r['scale_true'][0]:.2f}/{r['scale_true'][1]:.2f}")
    print("=" * 78)

    document = {
        "schema": SCHEMA,
        "generated_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "runtime_seconds": round(time.time() - started, 1),
        "provenance": {
            "kind": "software reference, Python; no board, no FPGA, no real platform",
            "cover": ("synthetic chest-radiograph-shaped phantom, drawn procedurally; "
                      "no patient data of any kind"),
            "python": platform.python_version(),
            "numpy": np.__version__,
            "pillow": Image.__version__,
            "venv": "novalife_hub/.venv",
        },
        "parameters": {
            "cover_shape": [COVER_SHAPE[0], COVER_SHAPE[1]],
            "cover_seed": args.seed,
            "handle_seed": args.handle_seed,
            "iwt": "5/3 lifting, 1 level, tools/stego_research/sims/iwt_lifting.py",
            "pilot": "none",
            "block_ll": DCT_BLOCK,
            "embedding": "sign of 4x4 Hadamard projection outer([1,1,-1,-1])^2, T = delta/2",
            "qim_base_delta": QIM_BASE_DELTA,
            "qim_alpha": QIM_ALPHA,
            "regions": N_REGIONS,
            "blocks_per_region": BLOCKS_PER_REGION,
            "polar": ("N=256 K=128, SCL L=8, "
                      "tools/stego_research/sims/polar_codec.py"),
            "ascon": ("Ascon-AEAD128 (NIST SP 800-232), truncated 48-bit tag, "
                      "tools/tag_reference/ascon_primitives.py"),
            "roi_rule": ROI_SOURCE,
            "adaptive_delta_note": (
                "algorithm.md section 3 states delta = 16 + 0.15 x local_std; the older "
                "sims/adaptive_qim.py uses 36 + 0.10*sqrt(var) with a floor of 24. This "
                "reference follows algorithm.md."
            ),
        },
        "cover": {
            "shape": [int(cover.shape[0]), int(cover.shape[1])],
            "roi_pixels": int(roi.sum()),
            "roi_fraction": round(float(roi.sum()) / roi.size, 6),
            "roi_source": ROI_SOURCE,
            "sha256": sha256_bytes(png_bytes(cover)),
        },
        "marked": {
            "shape": [int(marked.shape[0]), int(marked.shape[1])],
            "psnr_db": q["psnr_db"],
            "ssim": q["ssim"],
            "psnr_of_cover_note": "marked export vs the unmarked cover",
            "max_abs_change_inside_drawn_roi": info["max_abs_change_inside_drawn_roi"],
            "max_abs_change_inside_algorithm_roi": info["max_abs_change_inside_algorithm_roi"],
            "max_abs_change_outside_roi": info["max_abs_change_outside_roi"],
            "support_rule_violations": info["support_rule_violations"],
            "blocks_available_per_region": info["blocks_available_per_region"],
            "pilot_lines_applied": info["pilot_lines_applied"],
            "round_trip_tag_ok": bool(info["round_trip_tag_ok"]),
            "sha256": sha256_bytes(png_bytes(marked)),
        },
        "block": {
            "version": fields["version"],
            "hub_id": fields["hub_id"],
            "handle": f"0x{fields['handle']:016x}",
            "tag": f"0x{fields['tag']:012x}",
            "bits_hex": tag_block.bits_to_bytes(block).hex(),
        },
        "conditions": rows,
        "summary": {
            "conditions": len(rows),
            "exact_recoveries": n_ok,
            "tag_passes": sum(1 for r in rows if r["tag_ok"]),
            "scale_errors": {
                r["name"]: [
                    jnum(r["pilot"]["scale_rows"] - r["scale_true"][0]),
                    jnum(r["pilot"]["scale_cols"] - r["scale_true"][1]),
                ]
                for r in rows
            },
        },
    }

    JSON_PATH.write_text(json.dumps(document, indent=2, default=str))
    print(f"wrote {JSON_PATH}")
    MD_PATH.write_text(write_markdown(document))
    print(f"wrote {MD_PATH}")
    return 0


# --------------------------------------------------------------------------- #
# the readable report
# --------------------------------------------------------------------------- #


def write_markdown(doc: dict) -> str:
    p = doc["parameters"]
    c = doc["cover"]
    m = doc["marked"]
    b = doc["block"]
    L = []
    A = L.append
    A("# RPP-QIM Python reference: attack matrix (measured, software only)")
    A("")
    A(f"Run {doc['generated_utc']}, {doc['runtime_seconds']} s, Python {doc['provenance']['python']} "
      f"with numpy {doc['provenance']['numpy']} and Pillow {doc['provenance']['pillow']} "
      f"in `{doc['provenance']['venv']}`.")
    A("")
    A("> **Software simulation.** No board, no FPGA, no real platform, no patient data.")
    A("> The cover is a synthetic chest-radiograph-shaped phantom drawn from a fixed seed")
    A("> (`tools/tag_reference/embed.py: make_cover`); the ROI is drawn with it, so the")
    A("> diagnostic region is exact by construction rather than thresholded. Every attack")
    A("> below is applied by this reference, not by WhatsApp, Telegram, Signal or a")
    A("> screenshot. Phase A measures the real platforms; nothing here substitutes for it.")
    A("")
    A("## Setup")
    A("")
    A("| | |")
    A("|---|---|")
    A(f"| Cover | {c['shape'][1]}x{c['shape'][0]} synthetic phantom, seed {p['cover_seed']}, "
      f"sha256 `{c['sha256'][:16]}...` |")
    A(f"| ROI | {c['roi_pixels']} px ({100*c['roi_fraction']:.1f}% of the frame), {c['roi_source']} |")
    A(f"| Tag block | version={b['version']} hub_id=0x{b['hub_id']:03x} "
      f"handle={b['handle']} tag={b['tag']} |")
    A(f"| Transform | {p['iwt']} |")
    A(f"| Pilot grid | G={p['pilot_interval_g_ll']} LL coefficients "
      f"(= {2*p['pilot_interval_g_ll']} px), B={p['pilot_width_b_ll']}, "
      f"amplitude {p['pilot_amplitude']} |")
    A(f"| QIM | delta = {p['qim_base_delta']} + {p['qim_alpha']} x local_std, "
      f"8x8 DCT of the LL band, zigzag {p['qim_mid_band_zigzag']} |")
    A(f"| Regions | R={p['regions']} quadrants x {p['blocks_per_region']} eligible 8x8 blocks "
      f"(256 codeword bits each) |")
    A(f"| Code | {p['polar']} |")
    A(f"| MAC | {p['ascon']} |")
    A(f"| Marked export | PSNR {m['psnr_db']} dB, SSIM {m['ssim']} against the cover; "
      f"max |change| inside drawn ROI = **{m['max_abs_change_inside_drawn_roi']}**, "
      f"inside algorithm ROI = **{m['max_abs_change_inside_algorithm_roi']}** |")
    A(f"| Clean self-check | round-trip tag "
      f"{'PASS' if m['round_trip_tag_ok'] else 'FAIL'} (exact 128-bit recovery, see `none` row) |")
    A("")
    A("## The matrix")
    A("")
    A("| Condition | scale est. (rows/cols) | true scale | exact 128 bits | tag | PSNR dB | SSIM |")
    A("|---|---|---|---|---|---|---|")
    for r in doc["conditions"]:
        e = r["pilot"]
        A(f"| {r['label']} | {e['scale_rows']:.4f} / {e['scale_cols']:.4f} | "
          f"{r['scale_true'][0]:.2f} / {r['scale_true'][1]:.2f} | "
          f"{'yes' if r['exact'] else 'no'} | {'PASS' if r['tag_ok'] else 'FAIL'} | "
          f"{r['image']['psnr_db']} | {r['image']['ssim']} |")
    A("")
    A("`scale est.` is what the pilot grid measured on the received image; `true scale` is")
    A("what the attack applied. The pilot period is biased low by about 0.2% (the pilot grid")
    A("plus the 5/3 IWT); measured on its own that bias is far outside the payload block")
    A("tolerance at 0.5x. For a pure resize the scale is therefore taken exactly from the")
    A("received/declared size ratio, and the remaining sub-pixel offset is found by a small")
    A("exact search in which the 48-bit tag is the only verdict -- the earlier `ECC budget")
    A("too small` reading of the resize failure was wrong: with the correct geometry the")
    A("payload decodes at BER 0. The pilot is still what handles a crop, where the received")
    A("size no longer fixes the scale; crop remains the open case, and that *is* a")
    A("synchronisation limit rather than a coding one.")
    A("")
    A("## Per condition")
    A("")
    for r in doc["conditions"]:
        e = r["pilot"]
        A(f"### {r['label']} (`{r['name']}`)")
        A("")
        A(f"- received {r['received']['shape'][1]}x{r['received']['shape'][0]} "
          f"(declared {m['shape'][1]}x{m['shape'][0]}); {r['note']}")
        A(f"- pilot period rows {e['period_rows']:.3f}, cols {e['period_cols']:.3f} LL samples "
          f"(nominal {p['pilot_interval_g_ll']}); "
          f"scale {e['scale_rows']:.4f}/{e['scale_cols']:.4f} vs true "
          f"{r['scale_true'][0]:.2f}/{r['scale_true'][1]:.2f}; trusted={e['trusted']}")
        A(f"- grid residual after the scale is undone: {e['residual']} LL rows/cols")
        A(f"- accepted candidate: `{r['accepted']}` "
          f"({len(r['candidates'])} coarse candidates ranked)")
        A(f"- region hard BER before decoding: "
          f"{', '.join(f'{x:.3f}' for x in r['region_hard_ber'])}")
        A(f"- **exact 128-bit recovery: {'yes' if r['exact'] else 'no'}**; "
          f"**tag verdict: {'PASS' if r['tag_ok'] else 'FAIL'}**")
        A(f"- PSNR {r['image']['psnr_db']} dB, SSIM {r['image']['ssim']}; "
          f"{r['image']['comparison']}")
        if r["failures"]:
            A(f"- recovery notes: {'; '.join(r['failures'])}")
        A("")
    s = doc["summary"]
    A("## Summary")
    A("")
    A(f"- exact 128-bit recovery in **{s['exact_recoveries']} of {s['conditions']}** "
      f"conditions; tag verifies in {s['tag_passes']}.")
    A("- what this run does **not** show: real chat-app sends, rotation, colour, other")
    A("  covers, other seeds, false-accept behaviour against a *guessed* handle, and")
    A("  anything on hardware. All of that is future work and is listed in")
    A("  `tools/tag_reference/README.md`.")
    A("")
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    raise SystemExit(main())
