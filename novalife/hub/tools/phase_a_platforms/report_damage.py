#!/usr/bin/env python3
"""Phase A platform damage report.

Compares an ORIGINAL image with the copy that came back after a chat app,
and reports what the platform did to it:

  * pixel dimensions, aspect ratio and the exact scale factor
  * container format, baseline vs progressive JPEG, quantisation tables and an
    Annex-K quality estimate, chroma subsampling
  * EXIF / XMP / ICC / COM survival, tag by tag, including orientation
  * pixel-domain damage: PSNR, SSIM, RMSE, max absolute difference
  * coefficient-domain damage: mean absolute change per DCT band (DC, low,
    mid, high), which is what a watermark designer needs to see

Everything reported is measured from the two files on disk. The quality factor
is the one estimated number, and it says so. Nothing here assumes a platform's
behaviour: run it once per platform and let the files speak.

Usage:
    .venv/bin/python tools/phase_a_platforms/report_damage.py \\
        --original test_images/synthetic_chest_512_master.jpg \\
        --received phone_returns/image_20261011.jpg \\
        --platform whatsapp_image
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from jpeg_probe import (  # noqa: E402
    ZIGZAG_TO_NATURAL,
    IDENTITY_TAGS,
    ORIENTATION_VALUES,
    parse_jpeg,
)

TOOL_DIR = Path(__file__).resolve().parent
DEFAULT_OUT = TOOL_DIR / "results"

# Comparison mode: RGB if either image carries colour, grayscale otherwise.
COLOUR_MODES = {"RGB", "RGBA", "RGBX", "CMYK", "YCbCr", "LAB", "HSV", "P", "PA", "La"}

# DCT bands by zigzag index. The embedding domain in docs/algorithm.md is the
# mid-band of the 8x8 DCT, so "mid" is defined to line up with that: the band
# around zigzag 10-26. DC and the strongest low-frequency coefficients are the
# "low" band; the top-right triangle that JPEG throws away first is "high".
BANDS: dict[str, range] = {
    "dc": range(0, 1),
    "low": range(1, 10),
    "mid": range(10, 27),
    "high": range(27, 64),
}

SSIM_WINDOW = 8
RESAMPLER = Image.Resampling.BICUBIC
RESAMPLER_NAME = "PIL BICUBIC"


# ---------------------------------------------------------------- file facts


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def detect_format(path: Path | None, with_img: Image.Image | None) -> str:
    if with_img is not None and with_img.format:
        return with_img.format.upper()
    if path is None:
        return "unknown"
    magic = path.read_bytes()[:12]
    for name, sig in (("JPEG", b"\xff\xd8\xff"), ("PNG", b"\x89PNG\r\n\x1a\n"),
                      ("GIF", b"GIF87a"), ("GIF", b"GIF89a"), ("TIFF", b"II*\x00"),
                      ("TIFF", b"MM\x00*"), ("WEBP", b"RIFF"), ("BMP", b"BM")):
        if magic.startswith(sig):
            return name
    return "unknown"


def load_image(path: Path) -> Image.Image:
    """Open an image and force the pixel data to be loaded."""
    img = Image.open(path)
    img.load()
    return img


# ---------------------------------------------------------------- pixel metrics


def to_comparison_array(img: Image.Image, colour: bool) -> np.ndarray:
    if colour:
        return np.asarray(img.convert("RGB"), dtype=np.uint8)
    return np.asarray(img.convert("L"), dtype=np.uint8)


def luminance(img: Image.Image) -> np.ndarray:
    arr = np.asarray(img.convert("L"), dtype=np.uint8)
    return arr


def psnr(a: np.ndarray, b: np.ndarray) -> float | None:
    mse = float(np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2))
    if mse == 0.0:
        return None  # infinite
    return 10.0 * math.log10(255.0 * 255.0 / mse)


def box_mean(x: np.ndarray, w: int) -> np.ndarray:
    """Mean of x over a w x w window at every pixel, numpy only.

    Integral image (double cumsum) plus a symmetrically padded border, which is
    the same border handling scipy.ndimage.uniform_filter uses by default
    (checked: identical in the interior to 1e-12, identical at the borders to
    1e-9). It replaces the SciPy call so the Phase A harness stays on numpy and
    Pillow, the only libraries the project venv guarantees.
    """
    if w <= 1:
        return x.astype(np.float64, copy=True)
    pad = w // 2
    p = np.pad(x.astype(np.float64), pad, mode="symmetric")
    integral = np.cumsum(np.cumsum(p, axis=0), axis=1)
    # Shift by one so integral[y, x] is the sum of p[:y, :x].
    integral = np.pad(integral, ((1, 0), (1, 0)))
    h, wd = x.shape
    y0 = np.arange(h)[:, None]
    y1 = y0 + w
    x0 = np.arange(wd)[None, :]
    x1 = x0 + w
    return (integral[y1, x1] - integral[y0, x1] - integral[y1, x0] + integral[y0, x0]) / float(w * w)


def ssim_windowed(a: np.ndarray, b: np.ndarray) -> float:
    """Windowed SSIM over an 8x8 uniform window, mean over the whole image.

    Standard SSIM with C1=(0.01*L)^2, C2=(0.03*L)^2, L=255, the same constants
    the project's baseline experiment uses. Two deliberate approximations,
    reported rather than hidden: the window is an 8x8 uniform box instead of
    the 11x11 Gaussian of the SSIM paper, and the mean is taken over the whole
    image rather than with the paper's strided windows. numpy alone is enough -
    no SciPy, no new dependency for Phase A.
    """
    x = a.astype(np.float64)
    y = b.astype(np.float64)
    c1 = (0.01 * 255.0) ** 2
    c2 = (0.03 * 255.0) ** 2
    mu_x = box_mean(x, SSIM_WINDOW)
    mu_y = box_mean(y, SSIM_WINDOW)
    var_x = box_mean(x * x, SSIM_WINDOW) - mu_x * mu_x
    var_y = box_mean(y * y, SSIM_WINDOW) - mu_y * mu_y
    cov = box_mean(x * y, SSIM_WINDOW) - mu_x * mu_y
    num = (2.0 * mu_x * mu_y + c1) * (2.0 * cov + c2)
    den = (mu_x * mu_x + mu_y * mu_y + c1) * (var_x + var_y + c2)
    m = num / den
    m = np.clip(m, -1.0, 1.0)
    return float(np.mean(m))


# ---------------------------------------------------------------- DCT


def dct_matrix() -> np.ndarray:
    c = np.zeros((8, 8), dtype=np.float64)
    for k in range(8):
        for n in range(8):
            c[k, n] = math.sqrt(1.0 / 8.0) if k == 0 else 0.5
            c[k, n] *= math.cos(math.pi * (2 * n + 1) * k / 16.0)
    return c


_DCT = dct_matrix()


def block_dct(gray: np.ndarray) -> np.ndarray:
    """8x8 block DCT-II of a level-shifted grayscale image.

    Returns an (H8, W8, 8, 8) array of per-block coefficients, where H8/W8 are
    the block counts. The level shift of -128 matches the YCbCr conversion JPEG
    does, so the DC coefficient means what it means in JPEG.
    """
    shifted = gray.astype(np.float64) - 128.0
    h, w = shifted.shape
    bh, bw = h // 8, w // 8
    usable = shifted[: bh * 8, : bw * 8]
    blocks = usable.reshape(bh, 8, bw, 8).transpose(0, 2, 1, 3)
    return _DCT @ blocks @ _DCT.T


def band_masks() -> dict[str, np.ndarray]:
    """Boolean 8x8 masks for each DCT band, keyed by band name."""
    masks = {}
    for name, zs in BANDS.items():
        mask = np.zeros((8, 8), dtype=bool)
        for z in zs:
            nat = ZIGZAG_TO_NATURAL[z]
            mask[nat // 8, nat % 8] = True
        masks[name] = mask
    return masks


def band_report(orig_coef: np.ndarray, recv_coef: np.ndarray) -> dict[str, Any]:
    """Mean absolute coefficient change per band, plus how big each band is."""
    out: dict[str, Any] = {}
    masks = band_masks()
    n_blocks = orig_coef.shape[0] * orig_coef.shape[1]
    for name, mask in masks.items():
        o = orig_coef[:, :, mask]
        r = recv_coef[:, :, mask]
        delta = r - o
        mean_abs_orig = float(np.mean(np.abs(o)))
        mean_abs_change = float(np.mean(np.abs(delta)))
        out[name] = {
            "coefficients_per_block": int(mask.sum()),
            "coefficients_compared": int(o.size),
            "mean_abs_original": round(mean_abs_orig, 4),
            "mean_abs_received": round(float(np.mean(np.abs(r))), 4),
            "mean_abs_change": round(mean_abs_change, 4),
            "rmse_change": round(float(np.sqrt(np.mean(delta ** 2))), 4),
            "change_to_original_pct": round(100.0 * mean_abs_change / mean_abs_orig, 2) if mean_abs_orig > 1e-9 else None,
            "mean_signed_change": round(float(np.mean(delta)), 4),
        }
    out["blocks_compared"] = int(n_blocks)
    return out


# ---------------------------------------------------------------- metadata


def metadata_summary(jpeg_report: dict[str, Any] | None, pil_img: Image.Image | None, is_jpeg: bool) -> dict[str, Any]:
    if jpeg_report is None:
        return {"parsed": False, "exif_present": False,
                "reason": "container is not a JPEG; no SOF/APP parsing applies"}

    summary: dict[str, Any] = {
        "parsed": True,
        "app_segments": jpeg_report.get("app_segments", []),
        "com_segments": jpeg_report.get("com_segments", []),
        "xmp_present": jpeg_report.get("xmp_present", False),
        "icc_profile_present": jpeg_report.get("icc_profile_present", False),
    }
    exif = jpeg_report.get("exif")
    if exif is None:
        summary["exif_present"] = False
        summary["tag_count"] = 0
        summary["tag_names"] = []
        summary["ifd_entry_counts"] = {}
        summary["identity_tags"] = {name: "absent" for name in IDENTITY_TAGS}
        summary["orientation"] = None
        summary["orientation_meaning"] = None
        return summary

    names = list(exif.get("tag_names", []))
    present = set(names)
    summary["exif_present"] = True
    summary["tag_count"] = exif.get("total_tags", len(names))
    summary["tag_names"] = names
    summary["ifd_entry_counts"] = {ifd["name"]: ifd["entry_count"] for ifd in exif.get("ifds", [])}
    summary["exif_parse_errors"] = exif.get("errors", [])
    summary["orientation"] = exif.get("orientation")
    summary["orientation_meaning"] = exif.get("orientation_meaning")
    summary["identity_tags"] = {
        name: ("present" if name in present else "absent") for name in IDENTITY_TAGS
    }
    return summary


def tag_diff(orig_meta: dict[str, Any], recv_meta: dict[str, Any]) -> dict[str, Any]:
    """Tag names present in each file, and the ones the platform dropped.

    'absent' here means absent from the received copy while present in the
    original. A tag the platform ADDED is listed separately, because a phone
    can and does write its own metadata.
    """
    o_names = [n for n in (orig_meta.get("tag_names") or [])] if orig_meta.get("parsed") else []
    r_names = [n for n in (recv_meta.get("tag_names") or [])] if recv_meta.get("parsed") else []
    o_set, r_set = set(o_names), set(r_names)
    return {
        "tags_in_original": o_names,
        "tags_in_received": r_names,
        "count_in_original": len(o_names),
        "count_in_received": len(r_names),
        "present_in_both": sorted(o_set & r_set),
        "present_in_original_absent_from_received": sorted(o_set - r_set),
        "present_in_received_absent_from_original": sorted(r_set - o_set),
        "explanation": ("present_in_original_absent_from_received is what the "
                        "platform stripped; present_in_received_absent_from_original "
                        "is what it added"),
    }


def identity_verdict(orig_meta: dict[str, Any], recv_meta: dict[str, Any]) -> dict[str, Any]:
    """Which patient/device-identifying tags survived, if any existed at all."""
    def present_tags(meta: dict[str, Any]) -> list[str]:
        if not meta.get("parsed") or not meta.get("exif_present"):
            return []
        return [name for name, state in meta.get("identity_tags", {}).items() if state == "present"]

    orig_present = present_tags(orig_meta)
    recv_present = present_tags(recv_meta)
    return {
        "in_original": orig_present,
        "in_received": recv_present,
        "surviving": [name for name in orig_present if name in recv_present],
        "stripped": [name for name in orig_present if name not in recv_present],
        "note": ("the original carried no identifying tags, so nothing was "
                 "available to strip; the received copy may have added its own"),
    }


# ---------------------------------------------------------------- report


def build_report(original_path: Path, received_path: Path, platform: str) -> dict[str, Any]:
    rows: dict[str, Any] = {}

    o_bytes = original_path.read_bytes()
    r_bytes = received_path.read_bytes()
    o_jpeg = parse_jpeg(o_bytes)
    r_jpeg = parse_jpeg(r_bytes)

    o_img = load_image(original_path)
    r_img = load_image(received_path)

    colour = (o_img.mode in COLOUR_MODES) or (r_img.mode in COLOUR_MODES)
    o_arr = to_comparison_array(o_img, colour)
    r_arr = to_comparison_array(r_img, colour)
    # ---- provenance
    rows["provenance"] = {
        "claim": "measured",
        "measured_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "platform_label": platform,
        "original": {
            "path": str(original_path),
            "sha256": sha256_file(original_path),
            "bytes": len(o_bytes),
        },
        "received": {
            "path": str(received_path),
            "sha256": sha256_file(received_path),
            "bytes": len(r_bytes),
        },
        "byte_identical": o_bytes == r_bytes,
        "tool": "report_damage.py",
        "dependencies": ["python3 stdlib", "numpy", "Pillow"],
    }

    # ---- geometry
    o_w, o_h = o_img.size
    r_w, r_h = r_img.size
    rows["geometry"] = {
        "claim": "measured",
        "original_width": o_w,
        "original_height": o_h,
        "original_aspect": round(o_w / o_h, 6) if o_h else None,
        "received_width": r_w,
        "received_height": r_h,
        "received_aspect": round(r_w / r_h, 6) if r_h else None,
        "scale_x": round(r_w / o_w, 6) if o_w else None,
        "scale_y": round(r_h / o_h, 6) if o_h else None,
        "uniform_scale": abs((r_w / o_w) - (r_h / o_h)) < 1e-6 if o_w and o_h else None,
        "aspect_preserved": (r_w / r_h == o_w / o_h) if o_w and o_h and r_w and r_h else None,
        "pixels_original": int(o_arr.shape[0] * o_arr.shape[1]),
        "pixels_received": int(r_arr.shape[0] * r_arr.shape[1]),
        "pixel_ratio": round((r_w * r_h) / (o_w * o_h), 6) if o_w and o_h else None,
    }

    # ---- container and JPEG structure
    def jpeg_section(jrep: dict[str, Any], img: Image.Image, data: bytes) -> dict[str, Any]:
        if not jrep.get("is_jpeg"):
            return {
                "is_jpeg": False,
                "format_detected": detect_format(None, img),
                "note": "no SOI marker; JPEG-specific fields do not apply",
            }
        sec: dict[str, Any] = {
            "is_jpeg": True,
            "format_detected": detect_format(None, img),
            "sof_coding": jrep.get("sof"),
            "progressive": jrep.get("progressive"),
            "sof_size": jrep.get("sof_size"),
            "components": jrep.get("components"),
            "subsampling_label": jrep.get("subsampling_label"),
            "subsampling_components": jrep.get("subsampling"),
            "restart_interval": jrep.get("restart_interval"),
            "scan_count": jrep.get("scan_count", 0),
            "truncated": jrep.get("truncated"),
            "structure_notes": jrep.get("notes", []),
        }
        qts = {}
        for tid, t in (jrep.get("quant_tables") or {}).items():
            qts[tid] = {
                "grid_natural_order": t["grid"],
                "quality_estimate": (jrep.get("quality_estimates") or {}).get(f"table_{tid}"),
            }
        sec["quant_tables"] = qts
        return sec

    rows["container"] = {
        "claim": "measured",
        "original_format": detect_format(original_path, o_img),
        "received_format": detect_format(received_path, r_img),
        "original_mode": o_img.mode,
        "received_mode": r_img.mode,
        "comparison_mode": ("colour: luminance for the headline metrics, "
                           "per-channel numbers reported alongside"
                           if colour else "grayscale"),
        "original_jpeg": jpeg_section(o_jpeg, o_img, o_bytes),
        "received_jpeg": jpeg_section(r_jpeg, r_img, r_bytes),
    }

    # ---- metadata
    o_meta = metadata_summary(o_jpeg if o_jpeg.get("is_jpeg") else None, o_img, True)
    r_meta = metadata_summary(r_jpeg if r_jpeg.get("is_jpeg") else None, r_img, True)
    rows["metadata"] = {
        "claim": "measured",
        "original": o_meta,
        "received": r_meta,
        "tag_diff": tag_diff(o_meta, r_meta),
        "identity_survival": identity_verdict(o_meta, r_meta),
        "orientation": {
            "original": o_meta.get("orientation"),
            "original_meaning": o_meta.get("orientation_meaning"),
            "received": r_meta.get("orientation"),
            "received_meaning": r_meta.get("orientation_meaning"),
            "expected_meaning_table": ORIENTATION_VALUES,
        },
    }

    # ---- pixel domain
    o_lum = luminance(o_img)
    r_lum = luminance(r_img)
    same_geometry = o_lum.shape == r_lum.shape
    if not same_geometry:
        aligned = np.asarray(
            o_img.convert("L").resize((r_img.size[0], r_img.size[1]), resample=RESAMPLER),
            dtype=np.uint8,
        )
        alignment = f"original resampled to the received geometry with {RESAMPLER_NAME}"
    else:
        aligned = o_lum
        alignment = "same geometry; direct comparison, no resampling"

    diff = aligned.astype(np.int16) - r_lum.astype(np.int16)
    rmse = float(np.sqrt(np.mean(diff.astype(np.float64) ** 2)))
    mx = int(np.max(np.abs(diff))) if diff.size else 0
    p = psnr(aligned, r_lum)
    ss = ssim_windowed(aligned, r_lum)
    changed = float(np.mean(diff != 0)) if diff.size else 0.0
    pixel_domain: dict[str, Any] = {
        "claim": "measured",
        "comparison_basis": alignment,
        "resampler": RESAMPLER_NAME,
        "space_compared": "luminance (ITU-R 601-2 luma) for every number below",
        "psnr_db": None if p is None else round(p, 4),
        "psnr_db_note": "None means the two arrays are identical (PSNR is infinite)",
        "ssim_windowed": round(ss, 6),
        "ssim_window": f"{SSIM_WINDOW}x{SSIM_WINDOW} uniform box",
        "ssim_note": ("uniform box window instead of the 11x11 Gaussian of the SSIM paper, "
                      "borders symmetrically padded, mean over the whole image; C1/C2 use "
                      "L=255. Comparable between runs of this harness, not the reference SSIM"),
        "rmse_levels": round(rmse, 4),
        "max_abs_diff_levels": mx,
        "mean_abs_diff_levels": round(float(np.mean(np.abs(diff))), 4) if diff.size else 0.0,
        "fraction_pixels_changed": round(changed, 6),
    }

    # Colour detail, when either file carries it: luminance alone hides a
    # chroma-only change, which is exactly what subsampling does.
    if colour:
        if same_geometry:
            o_rgb = np.asarray(o_img.convert("RGB"), dtype=np.uint8)
        else:
            o_rgb = np.asarray(
                o_img.convert("RGB").resize((r_img.size[0], r_img.size[1]), resample=RESAMPLER),
                dtype=np.uint8,
            )
        r_rgb = np.asarray(r_img.convert("RGB"), dtype=np.uint8)
        per_channel: dict[str, Any] = {}
        for idx, name in enumerate(("R", "G", "B")):
            a_ch, b_ch = o_rgb[:, :, idx], r_rgb[:, :, idx]
            d = a_ch.astype(np.int16) - b_ch.astype(np.int16)
            q = psnr(a_ch, b_ch)
            per_channel[name] = {
                "psnr_db": None if q is None else round(q, 4),
                "rmse_levels": round(float(np.sqrt(np.mean(d.astype(np.float64) ** 2))), 4),
                "max_abs_diff_levels": int(np.max(np.abs(d))) if d.size else 0,
                "mean_abs_diff_levels": round(float(np.mean(np.abs(d))), 4) if d.size else 0.0,
            }
        q_all = psnr(o_rgb, r_rgb)
        pixel_domain["colour"] = {
            "per_channel": per_channel,
            "psnr_all_channels_db": None if q_all is None else round(q_all, 4),
            "rmse_all_channels_levels": round(float(np.sqrt(np.mean((o_rgb.astype(np.float64) - r_rgb.astype(np.float64)) ** 2))), 4),
            "note": ("per-channel numbers exist because 4:2:0 subsampling destroys the "
                     "chroma channels and leaves the luma looking almost intact"),
        }
    rows["pixel_domain"] = pixel_domain

    # ---- coefficient domain
    # Compare in the received geometry, on the shared block grid. This is the
    # evidence for WHERE the platform destroyed information.
    gh = min(aligned.shape[0], r_lum.shape[0]) // 8 * 8
    gw = min(aligned.shape[1], r_lum.shape[1]) // 8 * 8
    o_coef = block_dct(aligned[:gh, :gw])
    r_coef = block_dct(r_lum[:gh, :gw])
    band = band_report(o_coef, r_coef)

    # A control that separates resampling from re-encoding. Both rows below are
    # measured on the ORIGINAL grid so they are directly comparable:
    #   resize only  - the original down to the received geometry and back up
    #                  with the same resampler, never re-encoded
    #   platform     - the received copy upscaled back to the original geometry
    # The difference between the two rows is what the platform's re-encoding
    # added on top of the resize.
    control_band = None
    platform_at_original = None
    control_desc = ("both measured at the original grid, so they are comparable: "
                    "'resize only' is the original downsampled to the received "
                    f"geometry and resampled back up with {RESAMPLER_NAME}, never "
                    "re-encoded; 'platform' is the received copy upscaled back "
                    "to the original geometry. The gap between them is what the "
                    "re-encode added on top of the resize")
    if (r_w, r_h) != (o_w, o_h):
        round_trip = np.asarray(
            o_img.convert("L").resize((r_w, r_h), resample=RESAMPLER)
                              .resize((o_w, o_h), resample=RESAMPLER),
            dtype=np.uint8,
        )
        ch = min(o_lum.shape[0], round_trip.shape[0]) // 8 * 8
        cw = min(o_lum.shape[1], round_trip.shape[1]) // 8 * 8
        control_band = band_report(block_dct(o_lum[:ch, :cw]), block_dct(round_trip[:ch, :cw]))

        back_up = np.asarray(
            r_img.convert("L").resize((o_w, o_h), resample=RESAMPLER),
            dtype=np.uint8,
        )
        platform_at_original = band_report(block_dct(o_lum[:ch, :cw]), block_dct(back_up[:ch, :cw]))
    else:
        control_desc = ("geometry is unchanged, so there is nothing to separate: "
                        "the received copy was compared directly on the original grid")

    rows["coefficient_domain"] = {
        "claim": "measured",
        "comparison_basis": alignment,
        "coordinate_system": "8x8 block DCT-II, orthonormal, level shift -128 (JPEG YCbCr convention)",
        "band_definitions": {name: f"zigzag {zs.start}..{zs.stop - 1}" for name, zs in BANDS.items()},
        "band_change": band,
        "control_at_original_grid": {
            "description": control_desc,
            "resize_only_bands": control_band,
            "platform_upscaled_bands": platform_at_original,
        },
        "note": ("coefficients come from re-DCT of the decoded pixels, so a "
                 "received JPEG is its stored coefficients plus the decoder's "
                 "rounding; small changes near the quantisation step are expected"),
    }

    # ---- one-line interpretation, computed from the measurements only
    rows["derived"] = {
        "scale_factor": rows["geometry"]["scale_x"],
        "dimension_change": "none" if (r_w, r_h) == (o_w, o_h) else f"{o_w}x{o_h} -> {r_w}x{r_h}",
        "dct_mid_change_to_original_pct": band["mid"]["change_to_original_pct"],
        "dct_high_change_to_original_pct": band["high"]["change_to_original_pct"],
    }
    return rows


# ---------------------------------------------------------------- output


def _fmt(v: Any, n: int = 4) -> str:
    if v is None:
        return "-"
    if isinstance(v, float):
        return f"{v:.{n}f}".rstrip("0").rstrip(".") if n else f"{v:.0f}"
    return str(v)


def print_table(rows: dict[str, Any]) -> None:
    g = rows["geometry"]
    c = rows["container"]
    p = rows["pixel_domain"]
    cd = rows["coefficient_domain"]
    m = rows["metadata"]

    def line(label: str, value: Any):
        print(f"  {label:<38} {value}")

    print()
    print(f"PLATFORM DAMAGE REPORT - {rows['provenance']['platform_label']}  (all values measured)")
    print("-" * 78)
    line("original", f"{g['original_width']}x{g['original_height']} "
                     f"aspect {_fmt(g['original_aspect'], 3)} "
                     f"[{c['original_format']}]")
    line("received", f"{g['received_width']}x{g['received_height']} "
                     f"aspect {_fmt(g['received_aspect'], 3)} "
                     f"[{c['received_format']}]")
    line("scale x / y (exact)", f"{_fmt(g['scale_x'], 6)} / {_fmt(g['scale_y'], 6)}")
    line("uniform scale", "yes" if g["uniform_scale"] else f"NO - anisotropic")
    line("pixel ratio", _fmt(g["pixel_ratio"], 4))
    print()

    rj = c["received_jpeg"]
    if rj.get("is_jpeg"):
        est = ((rj.get("quant_tables") or {}).get("0", {}) or {}).get("quality_estimate") or {}
        line("received JPEG coding", f"{rj.get('sof_coding')} "
                                     f"({'progressive' if rj.get('progressive') else 'not progressive'})")
        line("subsampling", rj.get("subsampling_label"))
        line("estimated quality factor", f"{est.get('estimated')} "
                                         f"(nearest 5: {est.get('round_to_nearest_5')}; "
                                         f"matched: {est.get('table_matched')}; "
                                         f"method: {est.get('method')})")
        line("quant tables present", ", ".join(sorted((rj.get("quant_tables") or {}).keys())) or "none")
    else:
        line("received JPEG coding", "not a JPEG")
    oj = c["original_jpeg"]
    if oj.get("is_jpeg"):
        est = ((oj.get("quant_tables") or {}).get("0", {}) or {}).get("quality_estimate") or {}
        line("original estimated quality", est.get("estimated"))
    print()

    line("EXIF in received", "present" if m["received"].get("exif_present") else "absent")
    line("EXIF tag count (orig / recv)", f"{m['original'].get('tag_count', 0)} / {m['received'].get('tag_count', 0)}")
    td = m.get("tag_diff", {})
    stripped = td.get("present_in_original_absent_from_received") or []
    added = td.get("present_in_received_absent_from_original") or []
    line("tags stripped by platform", ", ".join(stripped) if stripped else "none")
    line("tags added by platform", ", ".join(added) if added else "none")
    line("orientation (orig / recv)", f"{m['orientation']['original']} / {m['orientation']['received']}")
    surv = rows["metadata"]["identity_survival"]
    line("identifying tags surviving", ", ".join(surv["surviving"]) if surv["surviving"] else "none")
    line("XMP / ICC / COM in received",
         f"{'yes' if m['received'].get('xmp_present') else 'no'} / "
         f"{'yes' if m['received'].get('icc_profile_present') else 'no'} / "
         f"{len(m['received'].get('com_segments', []))}")
    print()

    line("PSNR (dB)", _fmt(p["psnr_db"], 3) if p["psnr_db"] is not None else "infinite (identical)")
    line("SSIM (8x8 window)", _fmt(p["ssim_windowed"], 4))
    line("RMSE (levels)", _fmt(p["rmse_levels"], 3))
    line("max abs diff (levels)", p["max_abs_diff_levels"])
    line("pixels changed", f"{_fmt(100 * p['fraction_pixels_changed'], 3)}%")
    col = p.get("colour")
    if col:
        per = col["per_channel"]
        ch = " ".join(f"{n} {_fmt(per[n]['psnr_db'], 2)}" for n in ("R", "G", "B"))
        line("PSNR per channel (dB)", ch)
        line("PSNR all channels (dB)", _fmt(col["psnr_all_channels_db"], 3))
    print()

    print("  coefficient domain - mean absolute change per DCT band")
    print(f"  {'band':<8}{'coefs/blk':>10}{'mean|orig|':>12}{'mean|change|':>14}{'change %':>10}")
    for name in ("dc", "low", "mid", "high"):
        b = cd["band_change"][name]
        print(f"  {name:<8}{b['coefficients_per_block']:>10}{b['mean_abs_original']:>12.4f}"
              f"{b['mean_abs_change']:>14.4f}"
              f"{('None' if b['change_to_original_pct'] is None else format(b['change_to_original_pct'], '.2f')):>10}")
    print(f"  blocks compared: {cd['band_change']['blocks_compared']}")
    ctrl = cd["control_at_original_grid"]
    if ctrl["resize_only_bands"]:
        print("  control at the original grid (resize only vs platform):")
        print(f"  {'band':<8}{'resize only':>14}{'platform':>14}")
        for name in ("dc", "low", "mid", "high"):
            print(f"  {name:<8}{ctrl['resize_only_bands'][name]['mean_abs_change']:>14.4f}"
                  f"{ctrl['platform_upscaled_bands'][name]['mean_abs_change']:>14.4f}")
    print("-" * 78)
    print()


def summary_markdown(rows: dict[str, Any]) -> str:
    g, c, m, p, cd = rows["geometry"], rows["container"], rows["metadata"], rows["pixel_domain"], rows["coefficient_domain"]
    prov = rows["provenance"]
    d = rows["derived"]
    lines: list[str] = []
    a = lines.append

    a(f"# Platform damage: {prov['platform_label']}")
    a("")
    a(f"Measured {prov['measured_at_utc']} by `report_damage.py`. Every number below is measured "
      f"from the two files listed; the only estimated value is the JPEG quality factor, and "
      f"it is labelled as an estimate.")
    a("")
    a("| Field | Value |")
    a("|---|---|")
    a(f"| original | {prov['original']['path']} |")
    a(f"| original sha256 | `{prov['original']['sha256']}` |")
    a(f"| received | {prov['received']['path']} |")
    a(f"| received sha256 | `{prov['received']['sha256']}` |")
    a(f"| byte-identical | {prov['byte_identical']} |")
    a(f"| original size | {g['original_width']}x{g['original_height']} px, aspect {g['original_aspect']}, {c['original_format']} |")
    a(f"| received size | {g['received_width']}x{g['received_height']} px, aspect {g['received_aspect']}, {c['received_format']} |")
    a(f"| scale factor x | {g['scale_x']} |")
    a(f"| scale factor y | {g['scale_y']} |")
    a(f"| uniform scale | {g['uniform_scale']} |")
    a(f"| pixel ratio | {g['pixel_ratio']} |")
    a("")

    a("## JPEG structure")
    a("")
    for label in ("original", "received"):
        sec = c[f"{label}_jpeg"]
        if not sec.get("is_jpeg"):
            a(f"- **{label}**: not a JPEG ({sec.get('format_detected')})")
            continue
        est0 = ((sec.get("quant_tables") or {}).get("0") or {}).get("quality_estimate") or {}
        a(f"- **{label}**: {sec.get('sof_coding')}"
          f" ({'progressive' if sec.get('progressive') else 'not progressive'}), "
          f"subsampling {sec.get('subsampling_label')}, "
          f"estimated quality {est0.get('estimated')} (estimated, method {est0.get('method')}, "
          f"matched {est0.get('table_matched')} table)")
        for tid, t in (sec.get("quant_tables") or {}).items():
            grid = t["grid_natural_order"]
            a(f"  - quant table {tid}:")
            for row in grid:
                a("    " + " ".join(f"{v:4d}" for v in row))
    a("")

    a("## Metadata")
    a("")
    a(f"- EXIF present in original: {m['original'].get('exif_present')}; in received: {m['received'].get('exif_present')}")
    a(f"- EXIF tag count: {m['original'].get('tag_count', 0)} -> {m['received'].get('tag_count', 0)}")
    td = m.get("tag_diff", {})
    if td:
        a(f"- tags present in the original but stripped by the platform: "
          f"{td.get('present_in_original_absent_from_received') or 'none'}")
        a(f"- tags present in the received copy but not in the original (added): "
          f"{td.get('present_in_received_absent_from_original') or 'none'}")
    if m["received"].get("tag_names"):
        a(f"- tags remaining in received: {', '.join(m['received']['tag_names'])}")
    if m["original"].get("tag_names"):
        a(f"- tags in original: {', '.join(m['original']['tag_names'])}")
    a(f"- orientation: {m['orientation']['original']} -> {m['orientation']['received']}"
      f" ({m['orientation']['received_meaning']})")
    surv = rows["metadata"]["identity_survival"]
    a(f"- identifying tags: in original {surv['in_original'] or 'none'}; "
      f"surviving {surv['surviving'] or 'none'}; stripped {surv['stripped'] or 'none'}")
    a(f"- XMP: {m['received'].get('xmp_present')}; ICC: {m['received'].get('icc_profile_present')}; "
      f"COM segments: {len(m['received'].get('com_segments', []))}")
    a("")

    a("## Pixel domain")
    a("")
    a(f"- comparison basis: {p['comparison_basis']}")
    a(f"- PSNR: {p['psnr_db']} dB")
    a(f"- SSIM: {p['ssim_windowed']} ({p['ssim_window']} window)")
    a(f"- RMSE: {p['rmse_levels']} levels; max abs diff: {p['max_abs_diff_levels']} levels")
    a(f"- fraction of pixels changed: {p['fraction_pixels_changed']}")
    col = p.get("colour")
    if col:
        per = col["per_channel"]
        a(f"- per channel (R/G/B) PSNR dB: "
          + " / ".join(str(per[n]["psnr_db"]) for n in ("R", "G", "B")))
        a(f"- PSNR over all channels: {col['psnr_all_channels_db']} dB")
        a(f"- {col['note']}")
    a("")

    a("## Coefficient domain")
    a("")
    a(f"- {cd['coordinate_system']}")
    a(f"- band definitions: {cd['band_definitions']}")
    a("")
    a("| Band | coefs/block | mean\\|orig\\| | mean\\|change\\| | change as % of original |")
    a("|---|---|---|---|---|")
    for name in ("dc", "low", "mid", "high"):
        b = cd["band_change"][name]
        pct = b["change_to_original_pct"]
        a(f"| {name} | {b['coefficients_per_block']} | {b['mean_abs_original']} | "
          f"{b['mean_abs_change']} | {'n/a' if pct is None else str(pct) + '%'} |")
    a("")
    a(f"- blocks compared: {cd['band_change']['blocks_compared']}")
    rc = cd["control_at_original_grid"]
    a(f"- control: {rc['description']}")
    for label in ("resize_only_bands", "platform_upscaled_bands"):
        bands = rc[label]
        if not bands:
            continue
        pretty = "resize only" if label.startswith("resize") else "platform (received, upscaled back)"
        a(f"  - {pretty}:")
        for name in ("dc", "low", "mid", "high"):
            b = bands[name]
            a(f"    - {name}: mean abs change {b['mean_abs_change']} "
              f"({b['change_to_original_pct']}% of the band's original magnitude)")
    a("")

    a("## What this says for the mark")
    a("")
    a(f"- the platform changed the geometry from {d['dimension_change']} "
      f"(uniform scale {d['scale_factor']})")
    a(f"- the mid band, where the algorithm embeds, changed by "
      f"{d['dct_mid_change_to_original_pct']}% of its original magnitude")
    a(f"- the high band changed by {d['dct_high_change_to_original_pct']}%")
    a("")
    a("Limitations: the resampler used for alignment is "
      f"{cd['comparison_basis'].split(' with ')[-1] if ' with ' in cd['comparison_basis'] else 'none'}; "
      "the platform's own resampler is unknown, so the coefficient numbers include any "
      "resampling difference as well as re-encoding. The quality factor is an Annex K match, "
      "not a value read from the file.")
    a("")
    return "\n".join(lines)


def slugify(name: str) -> str:
    out = "".join(ch.lower() if ch.isalnum() else "-" for ch in name.strip())
    while "--" in out:
        out = out.replace("--", "-")
    return out.strip("-") or "platform"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Report what a chat platform did to an image.")
    ap.add_argument("--original", required=True, help="the untouched original file")
    ap.add_argument("--received", required=True, help="the copy that came back from the platform")
    ap.add_argument("--platform", required=True, help="platform label, e.g. whatsapp_image")
    ap.add_argument("--out", default=str(DEFAULT_OUT), help=f"output directory (default {DEFAULT_OUT})")
    args = ap.parse_args(argv)

    original_path = Path(args.original).expanduser()
    received_path = Path(args.received).expanduser()
    if not original_path.is_file():
        print(f"error: original not found: {original_path}", file=sys.stderr)
        return 2
    if not received_path.is_file():
        print(f"error: received not found: {received_path}", file=sys.stderr)
        return 2

    rows = build_report(original_path, received_path, args.platform)
    print_table(rows)

    out_dir = Path(args.out).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    slug = slugify(args.platform)
    json_path = out_dir / f"{slug}_report.json"
    json_path.write_text(json.dumps(rows, indent=2) + "\n")
    md = summary_markdown(rows)
    # One summary per platform, so nothing is overwritten, plus SUMMARY.md as
    # the most recent run for whoever looks at the folder first.
    summary_path = out_dir / f"{slug}_SUMMARY.md"
    summary_path.write_text(md)
    latest_path = out_dir / "SUMMARY.md"
    latest_path.write_text(md)

    print(f"wrote {json_path}")
    print(f"wrote {summary_path}")
    print(f"wrote {latest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
