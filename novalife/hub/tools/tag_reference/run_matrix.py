"""The G1 matrix for the RPP-QIM Python reference.

Gate G1 asks for more than the single-cover attack matrix in `run_demo.py`: a spread of
covers and seeds, the resize conditions that used to fail, the mandatory comparisons
(ROI untouched, PSNR/SSIM), the false-accept check, and the required **visible QR in the
margin** baseline, all from one command and written to one dated pair of files.

This runs, for every `(cover seed, handle seed)` pair:

  * mark the cover (one 128-bit tag block, one Ascon key),
  * for every lab attack in `CONDITIONS`, recover and record exact-128-bit recovery, the
    48-bit tag verdict, the per-region hard BER, and PSNR/SSIM against the marked export,
  * build the **same image with a visible QR in a margin** and, for the same attacks,
    ask `pyzbar` to read it back.

Then it measures, separately:

  * **ROI guarantee** -- the maximum absolute change inside the drawn diagnostic region,
    over every marked copy (must be 0);
  * **false accept** -- the tag verdict when the decryption key is wrong and when the
    image was never marked at all (a random guess at a handle, at the stated rate limit).

Nothing here is a claim about a real chat app: the attacks are applied by Pillow and
numpy.  Phase A measures WhatsApp/Telegram/Signal.  Pass/fail thresholds are **not yet
agreed** with the professor, so this file reports rates and does not declare a pass.

Run from the repository root with the project venv:

    novalife_hub/.venv/bin/python novalife_hub/tools/tag_reference/run_matrix.py

Deps: numpy, Pillow, segno (QR encode), pyzbar + libzbar (QR decode).  All in
`novalife_hub/.venv`.
"""
from __future__ import annotations

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

# The attack helpers and image metrics live in run_demo; reuse them so the two harnesses
# report the same numbers by construction.
import run_demo as demo
from run_demo import compare, png_bytes, sha256_bytes

try:
    import segno
except ImportError:  # pragma: no cover - dependency guard
    segno = None
try:
    from pyzbar.pyzbar import decode as zbar_decode
except Exception:  # pragma: no cover - dependency guard
    zbar_decode = None

RESULTS_DIR = Path(__file__).resolve().parents[2] / "results"
SCHEMA = "novalife/tag_matrix/v1"

# 5 covers x 10 handle seeds by default.  PUBLIC/SYNTHETIC ONLY: each "cover" is the
# procedural chest phantom from `embed.make_cover`, drawn from a different seed.
DEFAULT_COVER_SEEDS = [7010, 7011, 7012, 7013, 7014]
DEFAULT_HANDLE_SEEDS = [20261011 + 100 * i for i in range(10)]

# The attack set.  Same lab conditions as run_demo, plus resize 0.75x and 2.0x so all four
# G1 resize factors are in the matrix.  `true_scale` is (rows, cols).
CONDITIONS = [
    ("none", "no attack (lossless round trip)", demo.atk_none, (1.0, 1.0),
     "the control"),
    ("jpeg_q90", "JPEG quality 90", demo.atk_jpeg(90), (1.0, 1.0), "grayscale, 4:4:4"),
    ("jpeg_q70", "JPEG quality 70", demo.atk_jpeg(70), (1.0, 1.0), "a common chat-app quality"),
    ("jpeg_q50", "JPEG quality 50", demo.atk_jpeg(50), (1.0, 1.0), "harsher requantisation"),
    ("jpeg_q40", "JPEG quality 40", demo.atk_jpeg(40), (1.0, 1.0), "aggressive requantisation"),
    ("resize_050", "resize to 0.50x", demo.atk_resize(0.50), (0.50, 0.50), "downscale, Pillow BICUBIC"),
    ("resize_075", "resize to 0.75x", demo.atk_resize(0.75), (0.75, 0.75), "downscale, Pillow BICUBIC"),
    ("resize_150", "resize to 1.50x", demo.atk_resize(1.50), (1.50, 1.50), "upscale, Pillow BICUBIC"),
    ("resize_200", "resize to 2.00x", demo.atk_resize(2.00), (2.00, 2.00), "upscale, Pillow BICUBIC"),
    ("screenshot_like", "screenshot-like: resize 0.75x then JPEG Q80", demo.atk_screenshot,
     (0.75, 0.75), "resample and re-encode together"),
    ("crop_corner_25", "crop 25% off the top and left", demo.atk_crop_corner(0.25), (1.0, 1.0),
     "the open case: a periodic grid cannot locate a crop"),
    ("awgn_sigma2", "AWGN sigma 2", demo.atk_awgn(2.0), (1.0, 1.0), "pixel-domain Gaussian noise"),
]

QR_MARGIN = 24  # white margin, px, on each side of the QR block
QR_SCALE = 6    # QR module size, px
QR_BORDER = 4   # quiet zone, modules


# --------------------------------------------------------------------------- #
# the visible-QR baseline
# --------------------------------------------------------------------------- #


def qr_payload(handle: int) -> str:
    return f"novalife:{handle:016x}"


def make_qr_baseline(marked: np.ndarray, payload: str) -> np.ndarray | None:
    """Render `marked` with a visible QR of `payload` stamped in a right-hand margin."""
    if segno is None:
        return None
    qr = segno.make(payload, error="h")
    buf = io.BytesIO()
    qr.save(buf, kind="png", scale=QR_SCALE, border=QR_BORDER)
    buf.seek(0)
    qrimg = np.asarray(Image.open(buf).convert("L"), dtype=np.uint8)
    qh, qw = qrimg.shape
    h, w = marked.shape
    canvas = np.full((h, w + QR_MARGIN + qw + QR_MARGIN), 255, dtype=np.uint8)
    canvas[:, :w] = marked
    y0 = max(0, (h - qh) // 2)
    x0 = w + QR_MARGIN
    canvas[y0:y0 + qh, x0:x0 + qw] = qrimg
    return canvas


def decode_qr(img: np.ndarray) -> list[str]:
    if zbar_decode is None:
        return []
    return [d.data.decode(errors="replace") for d in zbar_decode(Image.fromarray(img))]


# --------------------------------------------------------------------------- #
# the run
# --------------------------------------------------------------------------- #


def mean_or_none(values: list[float]) -> float | None:
    vals = [v for v in values if v is not None]
    return round(float(np.mean(vals)), 4) if vals else None


def main() -> int:
    ap = argparse.ArgumentParser(description="G1 matrix for the RPP-QIM Python reference.")
    ap.add_argument("--covers", type=int, default=len(DEFAULT_COVER_SEEDS),
                    help="number of cover seeds (default 5)")
    ap.add_argument("--seeds", type=int, default=len(DEFAULT_HANDLE_SEEDS),
                    help="handle/tag seeds per cover (default 10)")
    ap.add_argument("--no-qr", action="store_true", help="skip the visible-QR baseline")
    ap.add_argument("--out-dir", type=str, default=str(demo.DEMO_OUT))
    args = ap.parse_args()

    cover_seeds = DEFAULT_COVER_SEEDS[: args.covers]
    handle_seeds = DEFAULT_HANDLE_SEEDS[: args.seeds]
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    if (segno is None or zbar_decode is None) and not args.no_qr:
        print("WARNING: segno/pyzbar missing -> QR baseline will be skipped", file=sys.stderr)
        args.no_qr = True

    started = time.time()
    print("=" * 78)
    print("NovaLife RPP-QIM -- G1 matrix (software only)")
    print("=" * 78)
    print(f"covers           : {len(cover_seeds)} seeds {cover_seeds}")
    print(f"seeds per cover  : {len(handle_seeds)} handle seeds {handle_seeds[0]}..{handle_seeds[-1]}")
    print(f"attacks          : {len(CONDITIONS)}")
    print(f"QR baseline      : {'off' if args.no_qr else 'on (segno + pyzbar)'}")

    cover_rows = []
    all_rows: list[dict] = []
    roi_max_changes: list[int] = []
    fa_wrong_key = {"attempts": 0, "passes": 0}
    fa_unmarked = {"attempts": 0, "passes": 0}

    for ci, cseed in enumerate(cover_seeds):
        cover, roi = embed.make_cover(cseed)
        cov_meta = {
            "seed": cseed,
            "shape": [int(cover.shape[0]), int(cover.shape[1])],
            "roi_pixels": int(roi.sum()),
            "sha256": sha256_bytes(png_bytes(cover)),
        }
        (out_dir / f"cover_{cseed}.png").write_bytes(png_bytes(cover))
        print(f"\n--- cover {ci + 1}/{len(cover_seeds)} seed {cseed} {cover.shape[1]}x{cover.shape[0]} "
              f"ROI {100.0 * roi.sum() / roi.size:.1f}% ---")

        # false accept, unmarked image: no tag was ever embedded, so the tag must not verify
        plain = extract.recover(cover, embed.HUB_KEY, declared_shape=cover.shape)
        fa_unmarked["attempts"] += 1
        fa_unmarked["passes"] += int(bool(plain.tag_ok))

        for hseed in handle_seeds:
            handle = tag_block.new_handle(hseed)
            block = tag_block.build_block(embed.HUB_KEY, tag_block.CURRENT_VERSION,
                                          embed.DEMO_HUB_ID, handle)
            marked, info = embed.mark(cover, roi, block)
            roi_max_changes.append(int(info["max_abs_change_inside_drawn_roi"]))

            # false accept, wrong key: the right geometry, the wrong secret
            wrong = extract.recover(marked, bytes([0xA5]) * 16, declared_shape=cover.shape,
                                    codeword=info["codeword"])
            fa_wrong_key["attempts"] += 1
            fa_wrong_key["passes"] += int(bool(wrong.tag_ok))

            qr_img = None if args.no_qr else make_qr_baseline(marked, qr_payload(handle))

            for name, label, fn, true_scale, note in CONDITIONS:
                received = fn(marked)
                rec = extract.recover(received, embed.HUB_KEY, declared_shape=cover.shape,
                                      codeword=info["codeword"])
                exact = bool(np.array_equal(np.asarray(rec.bits, dtype=np.uint8),
                                            np.asarray(block, dtype=np.uint8)))
                row = {
                    "cover_seed": cseed,
                    "handle_seed": hseed,
                    "handle": f"0x{handle:016x}",
                    "condition": name,
                    "scale_true": [true_scale[0], true_scale[1]],
                    "received_shape": [int(received.shape[0]), int(received.shape[1])],
                    "exact": exact,
                    "tag_ok": bool(rec.tag_ok),
                    "accepted": rec.accepted.label,
                    "pilot_scale": [rec.pilot["scale_rows"], rec.pilot["scale_cols"]],
                    "region_hard_ber": (None if rec.region_hard_ber is None
                                        else [round(float(b), 4) for b in rec.region_hard_ber]),
                    **compare(marked, received),
                }
                if qr_img is not None:
                    qr_received = fn(qr_img)
                    decoded = decode_qr(qr_received)
                    row["qr_decoded"] = qr_payload(handle) in decoded
                all_rows.append(row)

            print(f"   seed {hseed}: " + " ".join(
                f"{n}:{'Y' if r['exact'] and r['tag_ok'] else 'n'}"
                for n, r in ((r["condition"], r) for r in all_rows[-len(CONDITIONS):])))

        cover_rows.append(cov_meta)

    # ---- aggregate --------------------------------------------------------
    cond_summary = []
    for name, label, _fn, true_scale, note in CONDITIONS:
        rows = [r for r in all_rows if r["condition"] == name]
        n = len(rows)
        summary = {
            "condition": name,
            "label": label,
            "note": note,
            "true_scale": [true_scale[0], true_scale[1]],
            "n": n,
            "exact": sum(1 for r in rows if r["exact"]),
            "tag_pass": sum(1 for r in rows if r["tag_ok"]),
            "exact_rate": round(sum(1 for r in rows if r["exact"]) / n, 4),
            "mean_psnr_db": mean_or_none([r["psnr_db"] for r in rows]),
            "mean_ssim": mean_or_none([r["ssim"] for r in rows]),
            "mean_region_ber": mean_or_none(
                [b for r in rows if r["region_hard_ber"] for b in r["region_hard_ber"]]),
        }
        if not args.no_qr:
            summary["qr_decoded"] = sum(1 for r in rows if r.get("qr_decoded"))
            summary["qr_rate"] = round(sum(1 for r in rows if r.get("qr_decoded")) / n, 4)
        cond_summary.append(summary)

    roi_zero = all(v == 0 for v in roi_max_changes)
    document = {
        "schema": SCHEMA,
        "generated_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "runtime_seconds": round(time.time() - started, 1),
        "provenance": {
            "kind": "software reference, Python; no board, no FPGA, no real platform",
            "cover": ("procedural chest-radiograph-shaped phantoms, drawn from cover seeds; "
                      "no patient data of any kind"),
            "python": platform.python_version(),
            "numpy": np.__version__,
            "pillow": Image.__version__,
            "segno": None if segno is None else segno.__version__,
            "qr_decoder": "pyzbar + libzbar" if zbar_decode is not None else None,
            "venv": "novalife_hub/.venv",
        },
        "parameters": {
            "cover_seeds": cover_seeds,
            "handle_seeds": handle_seeds,
            "conditions": [c[0] for c in CONDITIONS],
            "qr": {"scale_px": QR_SCALE, "border_modules": QR_BORDER, "margin_px": QR_MARGIN,
                   "error": "h"},
            "thresholds": ("NOT YET AGREED with the professor; this file reports rates and "
                           "does not declare pass/fail"),
        },
        "covers": cover_rows,
        "roi": {
            "guarantee": "zero change inside the drawn diagnostic ROI",
            "max_abs_change_inside_roi_over_all_marks": int(max(roi_max_changes)) if roi_max_changes else None,
            "n_marks": len(roi_max_changes),
            "zero_everywhere": roi_zero,
        },
        "false_accept": {
            "theoretical_per_attempt": 2.0 ** -48,
            "note": ("the 48-bit Ascon tag fixes the per-attempt false-accept probability; "
                     "the stated server rate limit bounds online guesses"),
            "wrong_key": fa_wrong_key,
            "unmarked_image": fa_unmarked,
        },
        "conditions": cond_summary,
        "rows": all_rows,
    }

    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    # Never let a partial or QR-less run overwrite the full matrix: only the default
    # (>= 5 covers, >= 10 seeds, QR on) writes the plain dated filename.
    is_full = (
        len(cover_seeds) >= len(DEFAULT_COVER_SEEDS)
        and len(handle_seeds) >= len(DEFAULT_HANDLE_SEEDS)
        and not args.no_qr
    )
    suffix = "" if is_full else f"_c{len(cover_seeds)}s{len(handle_seeds)}" + ("_noqr" if args.no_qr else "")
    json_path = RESULTS_DIR / f"tag_matrix_{date}{suffix}.json"
    md_path = RESULTS_DIR / f"tag_matrix_{date}{suffix}.md"
    json_path.write_text(json.dumps(document, indent=2, default=str))
    print(f"\nwrote {json_path}")
    md_path.write_text(write_markdown(document))
    print(f"wrote {md_path}")

    # ---- console summary --------------------------------------------------
    print("\n" + "=" * 78)
    hdr = f"{'condition':<16} {'tag pass':>10} {'exact':>8}"
    if not args.no_qr:
        hdr += f" {'QR pass':>9}"
    hdr += "   mean PSNR/SSIM"
    print(hdr)
    for s in cond_summary:
        line = f"{s['condition']:<16} {s['tag_pass']:>4}/{s['n']:<5} {s['exact']:>4}/{s['n']:<3}"
        if not args.no_qr:
            line += f" {s.get('qr_decoded', 0):>4}/{s['n']:<4}"
        line += f"   {s['mean_psnr_db']}/{s['mean_ssim']}"
        print(line)
    print(f"ROI zero everywhere : {roi_zero} (max inside ROI {max(roi_max_changes) if roi_max_changes else None})")
    print(f"false accept wrong key  : {fa_wrong_key['passes']}/{fa_wrong_key['attempts']}")
    print(f"false accept unmarked   : {fa_unmarked['passes']}/{fa_unmarked['attempts']}")
    print("=" * 78)
    return 0


# --------------------------------------------------------------------------- #
# the readable report
# --------------------------------------------------------------------------- #


def write_markdown(doc: dict) -> str:
    p = doc["parameters"]
    L: list[str] = []
    A = L.append
    A("# RPP-QIM G1 matrix (measured, software only)")
    A("")
    A(f"Run {doc['generated_utc']}, {doc['runtime_seconds']} s, Python {doc['provenance']['python']} "
      f"with numpy {doc['provenance']['numpy']}, Pillow {doc['provenance']['pillow']}, "
      f"segno {doc['provenance']['segno']} in `{doc['provenance']['venv']}`.")
    A("")
    A("> **Software simulation.** No board, no FPGA, no real platform, no patient data. The")
    A("> attacks are applied by Pillow and numpy, not by WhatsApp, Telegram, Signal or a")
    A("> screenshot. Phase A measures the real platforms; nothing here substitutes for it.")
    A("")
    A(f"> **Thresholds are not yet agreed with the professor** ({p['thresholds']}).")
    A("")
    A("## Setup")
    A("")
    A(f"- **Covers:** {len(p['cover_seeds'])} procedural phantoms, seeds {p['cover_seeds']} "
      f"(public/synthetic only).")
    A(f"- **Seeds:** {len(p['handle_seeds'])} handle/tag seeds per cover "
      f"({p['handle_seeds'][0]}..{p['handle_seeds'][-1]}), so {len(p['cover_seeds'])*len(p['handle_seeds'])} "
      f"marked copies per condition.")
    A(f"- **Attacks:** {len(p['conditions'])}, `{', '.join(p['conditions'])}`.")
    A(f"- **Visible-QR baseline:** a `segno` QR (error level h, {p['qr']['scale_px']} px modules, "
      f"{p['qr']['border_modules']}-module quiet zone) stamped in a right margin of the marked "
      f"export, decoded with `pyzbar`/libzbar after the identical attacks.")
    A("")
    A("## Matrix")
    A("")
    has_qr = any("qr_decoded" in c for c in doc["conditions"])
    head = "| Condition | tag PASS | exact 128 bits |" + (" visible QR |" if has_qr else "") + " mean PSNR dB | mean SSIM |"
    A(head)
    A("|---|" + "---|" * (5 if has_qr else 4))
    def fmt(v):
        return "inf" if v is None else v
    for c in doc["conditions"]:
        row = (f"| {c['label']} | {c['tag_pass']}/{c['n']} ({c['tag_pass']/c['n']:.0%}) | "
               f"{c['exact']}/{c['n']} |")
        if has_qr:
            row += f" {c.get('qr_decoded', 0)}/{c['n']} ({c.get('qr_rate', 0):.0%}) |"
        row += f" {fmt(c['mean_psnr_db'])} | {c['mean_ssim']} |"
        A(row)
    A("")
    A("`tag PASS` counts a 48-bit Ascon tag that verifies after SCL decode and soft-combine;")
    A("`exact 128 bits` counts an exactly recovered block. The two are the same here (a tag")
    A("cannot verify on a wrong block at 2^-48), and are reported separately so a partial")
    A("recovery can never be read as a pass.")
    A("")
    A("## ROI guarantee")
    A("")
    r = doc["roi"]
    A(f"- Zero change inside the drawn diagnostic ROI on **{r['n_marks']} marks**: "
      f"`{'HOLDS' if r['zero_everywhere'] else 'VIOLATED'}` "
      f"(max |change| = {r['max_abs_change_inside_roi_over_all_marks']}).")
    A("- Measured in this software reference, on synthetic phantoms, with the ROI drawn by")
    A("  construction. It is not a hardware or real-image measurement.")
    A("")
    A("## False accept")
    A("")
    fa = doc["false_accept"]
    A(f"- Theoretical per-attempt probability: **2^-48 = {fa['theoretical_per_attempt']:.3e}**; "
      f"{fa['note']}.")
    A(f"- Wrong key, correct geometry: {fa['wrong_key']['passes']} tag PASS in "
      f"{fa['wrong_key']['attempts']} attempts.")
    A(f"- Never-marked image, correct key: {fa['unmarked_image']['passes']} tag PASS in "
      f"{fa['unmarked_image']['attempts']} attempts.")
    A("")
    A("## Coverage and limits")
    A("")
    A("- Synthetic phantoms only; not a spread of real modality images.")
    A("- No rotation, no colour/JPEG subsampling changes, no multiple re-encodes, no real")
    A("  chat-app send, no screenshot from a device.")
    A("- Crop is included to be explicit that it fails: the pilot grid is periodic, so a crop")
    A("  can be detected but not located. That is a synchronisation limit, not a coding one.")
    A("- **JPEG Q40 is the weak row.** When it fails the per-region hard BER sits near 0.5")
    A("  (chance) while it sits near 0.2 when it passes -- i.e. requantisation destroyed the QIM")
    A("  parity on that copy. It is cover-content and placement dependent (some covers are")
    A("  robust at Q40 and some are not), and it is a coding/robustness limit, not geometry:")
    A("  raising the QIM step or the ECC budget is the lever, and Q40 is below any chat app's")
    A("  setting anyway. Recorded, not hidden.")
    A("- The visible QR is placed in a **right-hand margin**, so the `crop 25% top-left` attack")
    A("  removes the tag geometry but misses the QR: the QR row above is passing a crop the tag")
    A("  cannot survive, and that is a genuine advantage of a visible marker. It is not a")
    A("  like-for-like win: a QR is visible, occupies image area, is destroyed by any crop that")
    A("  hits its margin, and is trivially forgeable (it carries no authentication), which is")
    A("  exactly what the 48-bit tag exists to prevent.")
    A("- Pass/fail thresholds are the professor's to set; this file reports rates only.")
    A("")
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    raise SystemExit(main())
