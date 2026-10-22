#!/usr/bin/env python3
"""Self-test for the Phase A damage harness.

Builds a known damage, runs report_damage.py on it, and checks that the
harness reports it correctly. This is a check on the MEASURING INSTRUMENT, not
a platform measurement: every number it prints comes from a synthetic original
that this script damaged itself, with the damage recorded here. It says so in
its own output.

The damage matches the scenario the project cares about: a share-resolution
export downscaled to a 1600 px long edge and then re-encoded by a JPEG encoder
at quality 72, which is the class of thing a chat platform does.

Run with the project venv:

    .venv/bin/python tools/phase_a_platforms/selftest.py

Writes the original, the damaged copy and the report into verification/.
Exit code is 0 only if every check passes.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TOOL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL_DIR))

from make_test_image import (  # noqa: E402
    FABRICATED_TAGS,
    OUT_DIR,
    SEED,
    build_synthetic_exif,
    radiograph_like,
)
from report_damage import _DCT, block_dct, build_report  # noqa: E402

DEFAULT_VERIFY_DIR = TOOL_DIR / "verification"

# The known damage, stated before anything runs.
ORIG_SIZE = 2048          # synthetic original, long edge 2048 px
ORIG_QUALITY = 92         # the original is a JPEG master, like the real send
TARGET_LONG_EDGE = 1600   # downscaled to this, like a share-resolution export
QUALITY = 72              # re-encoded at this quality
SUBSAMPLING = "4:2:0"     # chroma subsampling the re-encode uses
PLATFORM_LABEL = "selftest_known_damage"

# The test fixture is grayscale, so a JPEG of it has a single component and
# there is no chroma plane to subsample. This is the label the parser should
# return for it, and it is what the main checks expect.
GRAYSCALE_LABEL = "4:4:4 (single component, grayscale)"


def make_original(out_path: Path) -> Image.Image:
    """A sendable master: synthetic radiograph as a JPEG with fabricated EXIF.

    Same construction as make_test_image.py's _master.jpg, so the self-test
    exercises the same path the owner's phone will see.
    """
    arr = radiograph_like(ORIG_SIZE, SEED)
    img = Image.fromarray(np.rint(arr).astype(np.uint8), mode="L")
    payload = b"Exif\x00\x00" + build_synthetic_exif(FABRICATED_TAGS)
    img.save(out_path, "JPEG", quality=ORIG_QUALITY, subsampling="4:4:4", exif=payload)
    return img


def make_damaged_copy(original: Image.Image, out_path: Path,
                      long_edge: int, quality: int, subsampling: str) -> tuple[int, int]:
    """Downscale to the given long edge and re-encode as JPEG, no metadata."""
    w, h = original.size
    if w >= h:
        new = (long_edge, max(1, round(h * long_edge / w)))
    else:
        new = (max(1, round(w * long_edge / h)), long_edge)
    copy = original.convert("L").resize(new, resample=Image.Resampling.LANCZOS)
    copy.save(out_path, "JPEG", quality=quality, subsampling=subsampling)
    return new


def check_subsampling_labels(rgb_source: Image.Image, out_dir: Path) -> list[tuple[str, str, bool]]:
    """Check the SOF subsampling reader on colour encodes, where it means something.

    The main fixture is grayscale, so its JPEG has one component and no chroma
    to subsample. These three colour encodes of the same pixels are what prove
    the parser tells 4:2:0, 4:4:4 and 4:2:2 apart.
    """
    from jpeg_probe import parse_jpeg  # noqa: PLC0415

    checks: list[tuple[str, str, bool]] = []
    for label, sub in (("4:2:0", "4:2:0"), ("4:4:4", "4:4:4"), ("4:2:2", "4:2:2")):
        p = out_dir / f"subsampling_control_{label.replace(':', 'x')}.jpg"
        rgb_source.convert("RGB").resize((512, 512), resample=Image.Resampling.LANCZOS) \
            .save(p, "JPEG", quality=80, subsampling=sub)
        rep = parse_jpeg(p.read_bytes())
        measured = rep.get("subsampling_label")
        comps = rep.get("components") or []
        checks.append((
            f"colour encode at {label} is read back as {label}",
            f"parser says '{measured}' from sampling "
            + ", ".join(f"{c['h_sampling']}x{c['v_sampling']}" for c in comps),
            measured == label,
        ))
    return checks


def check_dct_math() -> list[tuple[str, str, bool]]:
    """Self-consistency of the coefficient domain, checked on random blocks."""
    rng = np.random.default_rng(SEED)
    x = rng.random((8, 8)) * 255.0 - 128.0
    orth = np.allclose(_DCT @ _DCT.T, np.eye(8), atol=1e-12)
    round_trip = np.allclose(_DCT.T @ (_DCT @ x @ _DCT.T) @ _DCT, x, atol=1e-9)

    # DC of a constant block must be 8 * (level - 128): for an orthonormal
    # DCT-II, X[0,0] = (1/8) * sum of all 64 samples.
    flat = np.full((8, 8), 130.0)
    dc_ok = abs(block_dct(flat)[0, 0, 0, 0] - 8.0 * 2.0) < 1e-9

    return [
        ("DCT matrix is orthonormal", f"||C C^T - I|| max {np.abs(_DCT @ _DCT.T - np.eye(8)).max():.2e}", orth),
        ("DCT round trip reproduces the block", f"max error {np.abs(_DCT.T @ (_DCT @ x @ _DCT.T) @ _DCT - x).max():.2e}", round_trip),
        ("DC of a constant block is 8 x (level - 128)", "block_dct(const 130)[0,0] == 16", dc_ok),
    ]


def main() -> int:
    ap = argparse.ArgumentParser(description="Self-test the Phase A damage harness.")
    ap.add_argument("--out", default=str(DEFAULT_VERIFY_DIR),
                    help=f"where to write the fixture and the report (default {DEFAULT_VERIFY_DIR})")
    args = ap.parse_args()

    out_dir = Path(args.out).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    root = TOOL_DIR.parent.parent

    print()
    print("PHASE A HARNESS SELF-TEST - known damage, not a platform measurement")
    print("-" * 78)
    print(f"  original              {ORIG_SIZE}x{ORIG_SIZE} JPEG q{ORIG_QUALITY} "
          f"with fabricated EXIF (seed {SEED})")
    print(f"  applied damage        long edge -> {TARGET_LONG_EDGE}, JPEG q{QUALITY}, metadata dropped")
    print(f"  expected scale        {TARGET_LONG_EDGE / ORIG_SIZE}")

    original_path = out_dir / f"selftest_original_{ORIG_SIZE}_q{ORIG_QUALITY}.jpg"
    master = make_original(original_path)

    damaged_path = out_dir / f"selftest_damaged_q{QUALITY}_{TARGET_LONG_EDGE}.jpg"
    new_size = make_damaged_copy(master, damaged_path, TARGET_LONG_EDGE, QUALITY, SUBSAMPLING)
    print(f"  damaged copy written  {damaged_path.name} at {new_size[0]}x{new_size[1]}")

    rows = build_report(original_path, damaged_path, PLATFORM_LABEL)
    json_path = out_dir / f"{PLATFORM_LABEL}_report.json"
    json_path.write_text(json.dumps(rows, indent=2) + "\n")

    g = rows["geometry"]
    cj = rows["container"]["received_jpeg"]
    est = ((cj.get("quant_tables") or {}).get("0") or {}).get("quality_estimate") or {}
    bands = rows["coefficient_domain"]["band_change"]
    meta = rows["metadata"]["tag_diff"]

    def near(a: float | None, b: float, tol: float) -> bool:
        return a is not None and abs(a - b) <= tol

    checks: list[tuple[str, str, bool]] = [
        ("scale factor", f"measured {g['scale_x']} vs expected {TARGET_LONG_EDGE / ORIG_SIZE}",
         near(g["scale_x"], TARGET_LONG_EDGE / ORIG_SIZE, 1e-6)),
        ("uniform scale (no aspect distortion)", f"x {g['scale_x']} vs y {g['scale_y']}",
         bool(g["uniform_scale"])),
        ("received dimensions", f"measured {g['received_width']}x{g['received_height']} vs expected {new_size[0]}x{new_size[1]}",
         (g["received_width"], g["received_height"]) == tuple(new_size)),
        ("JPEG coding mode", f"{cj.get('sof_coding')}, progressive={cj.get('progressive')}",
         cj.get("sof_coding") == "baseline_dct" and cj.get("progressive") is False),
        ("chroma subsampling (grayscale fixture)",
         f"measured '{cj.get('subsampling_label')}' - a grayscale JPEG has no chroma plane",
         cj.get("subsampling_label") == GRAYSCALE_LABEL),
        ("quality factor estimate", f"measured {est.get('estimated')} vs applied {QUALITY} "
                                    f"(Annex K match, tolerance 3)",
         near(est.get("estimated"), QUALITY, 3.0)),
        ("metadata stripped", f"{len(meta.get('present_in_original_absent_from_received') or [])} of "
                              f"{meta.get('count_in_original')} tags dropped by the re-encode",
         len(meta.get("present_in_original_absent_from_received") or []) == meta.get("count_in_original")),
        ("pixel PSNR is finite and plausible", f"{rows['pixel_domain']['psnr_db']} dB",
         (rows["pixel_domain"]["psnr_db"] or 0.0) > 20.0),
        ("DC band survives (change < 5% of the band)",
         f"{bands['dc']['change_to_original_pct']}%",
         (bands["dc"]["change_to_original_pct"] or 100.0) < 5.0),
        ("mid band is where the real damage lands (change > low)",
         f"mid {bands['mid']['change_to_original_pct']}% vs low {bands['low']['change_to_original_pct']}%",
         (bands["mid"]["change_to_original_pct"] or 0.0) > (bands["low"]["change_to_original_pct"] or 0.0)),
        ("high band is largely destroyed (change > mid)",
         f"high {bands['high']['change_to_original_pct']}% vs mid {bands['mid']['change_to_original_pct']}%",
         (bands["high"]["change_to_original_pct"] or 0.0) > (bands["mid"]["change_to_original_pct"] or 0.0)),
        ("band magnitudes decay in the expected order (low > mid > high)",
         f"{bands['low']['mean_abs_original']} > {bands['mid']['mean_abs_original']} > {bands['high']['mean_abs_original']}",
         bands["low"]["mean_abs_original"] > bands["mid"]["mean_abs_original"] > bands["high"]["mean_abs_original"]),
    ]
    checks += check_subsampling_labels(master, out_dir)
    checks += check_dct_math()

    width = max(len(name) for name, _, _ in checks)
    for name, detail, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name:<{width}}  {detail}")

    print()
    print(f"  wrote {json_path.relative_to(root)}")
    print(f"  wrote {damaged_path.relative_to(root)}")
    print(f"  wrote {original_path.relative_to(root)}")

    failed = [name for name, _, ok in checks if not ok]
    print("-" * 78)
    if failed:
        print(f"  {len(failed)} of {len(checks)} checks FAILED: {', '.join(failed)}")
        return 1
    print(f"  all {len(checks)} checks passed - the harness detects the known damage")
    print("  (this is a self-test of the instrument; it is not evidence about any platform)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
