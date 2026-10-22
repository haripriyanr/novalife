#!/usr/bin/env python3
"""Generate synthetic chest-radiograph-shaped test images for Phase A.

No real patient data, and none ever requested: the shapes that matter to the
measurement (dark field, bright lung-shaped ellipses, fine texture, a film
margin) are drawn procedurally from a fixed seed, so every run is identical.

Run with the project venv:

    .venv/bin/python tools/phase_a_platforms/make_test_image.py

Outputs (PNG, lossless, grayscale) land in tools/phase_a_platforms/test_images/.

For each size two files are written:

    synthetic_chest_<size>.png          the untouched, lossless reference
    synthetic_chest_<size>_master.jpg   the copy that gets sent to the phone

The master is a baseline JPEG carrying fabricated metadata (no patient data, no
device data: the strings are all literal "SYNTHETIC ..." values). It exists
because "did the platform strip the metadata" can only be measured if the file
that leaves the hospital carries metadata.
"""
from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

import numpy as np
from PIL import Image

OUT_DIR = Path(__file__).resolve().parent / "test_images"
SEED = 20261011
SIZES = (512, 1024)
MARGIN_FRACTION = 0.06  # black film strip at the top and bottom, like a hard copy
MASTER_QUALITY = 92     # the marked export in docs/algorithm.md is high quality

# Fabricated, obviously non-patient metadata for the sendable master.
# Deliberately ASCII-only and IFD0-only, so any decoder reads it.
FABRICATED_TAGS: dict[int, object] = {
    0x010E: "SYNTHETIC TEST IMAGE - NOT A PATIENT",
    0x010F: "SYNTHETIC",
    0x0110: "TEST-FIXTURE",
    0x0112: 1,  # Orientation: top-left, so a platform that bakes in a flip is visible
    0x0131: "make_test_image.py",
    0x0132: "2026:10:11 00:00:00",
    0x013B: "SYNTHETIC",
    0x8298: "SYNTHETIC TEST FIXTURE - NOT A PATIENT",
}


def smooth_noise(rng: np.random.Generator, shape: tuple[int, int], octaves: int = 5) -> np.ndarray:
    """Value noise summed over a few frequencies, normalised to [0, 1].

    Stands in for anatomical texture: flat overall, dense high-frequency detail.
    """
    out = np.zeros(shape, dtype=np.float64)
    amp = 1.0
    for _ in range(octaves):
        low = 4
        grid = rng.random((low + 1, low + 1))
        # Bilinear upsample of a tiny random grid (no new dependency).
        ys = np.linspace(0, low, shape[0])
        xs = np.linspace(0, low, shape[1])
        top = np.interp(xs, np.arange(low + 1), grid[0]).reshape(1, -1)
        bot = np.interp(xs, np.arange(low + 1), grid[1]).reshape(1, -1)
        w = np.interp(ys, np.arange(low + 1), np.arange(low + 1)).reshape(-1, 1)
        layer = top * (1 - w) + bot * w
        out += layer * amp
        amp *= 0.5
        low *= 2
    out -= out.min()
    if out.max() > 0:
        out /= out.max()
    return out


def radiograph_like(size: int, seed: int) -> np.ndarray:
    """A synthetic 'chest film': dark background, bright lung ellipses, ribs, texture."""
    rng = np.random.default_rng(seed + size)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    nx = (xx / (size - 1)) * 2.0 - 1.0
    ny = (yy / (size - 1)) * 2.0 - 1.0

    img = np.zeros((size, size), dtype=np.float64)

    # Bright lung-shaped ellipse fields, left and right of a darker mediastinum.
    for cx in (-0.42, 0.42):
        d = ((nx - cx) / 0.34) ** 2 + ((ny + 0.05) / 0.46) ** 2
        img += np.clip(1.0 - d, 0.0, 1.0) ** 1.5

    # Spine: a vertical bright column down the centre, behind the lung fields.
    d = (nx / 0.055) ** 2 + ((ny + 0.03) / 0.9) ** 2
    img += 0.8 * np.clip(1.0 - d, 0.0, 1.0)

    # Ribs: sinusoidal arcs across both hemithoraces.
    for k in range(7):
        phase = -0.55 + 0.16 * k
        curve = phase + 0.13 * np.sin(nx * 2.4)
        band = np.exp(-((ny - curve) ** 2) / (2 * 0.0075 ** 2)) * np.clip(np.abs(nx) * 1.35, 0, 1)
        img += 0.5 * band

    # Fine texture and a small amount of film grain.
    img = 0.72 * img + 0.28 * smooth_noise(rng, (size, size))
    img += 0.02 * rng.standard_normal((size, size))

    img = np.clip(img, 0.0, img.max() if img.max() > 0 else 1.0)
    img = img / img.max() * 205.0  # keep the peak below 255: no clipped white

    # Black film margin strip top and bottom, as on a printed radiograph.
    m = int(size * MARGIN_FRACTION)
    img[:m, :] = 0.0
    img[size - m :, :] = 0.0

    # Round trip through a JPEG at q100 so the master is a raster a chat app
    # would accept, then keep the PNG as the untouched reference.
    return img


def build_synthetic_exif(tags: dict[int, object]) -> bytes:
    """Build a minimal, valid Exif (TIFF, big-endian) blob for one IFD.

    No patient data and none ever: every value is fabricated for the test. The
    point is that a platform decides what to keep, and "did it strip the
    metadata" can only be measured if the original carries metadata.

    `tags` maps a tag number to an ASCII string (type 2) or an int (type 3,
    SHORT). Returns the TIFF part that follows the six "Exif\\0\\0" bytes,
    ready for `Image.save(..., exif=...)`.
    """
    fields = []  # (tag, type, count, value bytes)
    blob = bytearray()
    for tag, value in sorted(tags.items()):
        if isinstance(value, str):
            raw = value.encode("ascii") + b"\x00"
            fields.append((tag, 2, len(raw), bytes(raw)))
        elif isinstance(value, bool) or not isinstance(value, int):
            raise TypeError(f"tag 0x{tag:04X} must be str or int, got {type(value).__name__}")
        elif 0 <= value < 65536:
            fields.append((tag, 3, 1, struct.pack(">HH", value, 0)))
        else:
            fields.append((tag, 4, 1, struct.pack(">II", value, 0)))

    ifd_size = 2 + 12 * len(fields) + 4
    data_area = 8 + ifd_size  # 8-byte TIFF header, then the IFD, then the value area
    placements = []  # (tag, type, count, inline-or-offset value bytes, spill)
    for tag, ftype, count, raw in fields:
        if len(raw) <= 4:
            placements.append((tag, ftype, count, raw.ljust(4, b"\x00"), None))
        else:
            placements.append((tag, ftype, count, struct.pack(">I", data_area), bytes(raw)))
            data_area += len(raw) + (len(raw) % 2)  # TIFF pads to even boundaries

    out = bytearray()
    out += b"MM"
    out += struct.pack(">HI", 42, 8)
    out += struct.pack(">H", len(fields))
    for tag, ftype, count, value_field, _ in placements:
        out += struct.pack(">HHI", tag, ftype, count) + value_field
    out += struct.pack(">I", 0)  # no next IFD
    assert len(out) == 8 + ifd_size, f"IFD size {len(out)} != computed {8 + ifd_size}"
    for _, _, _, _, spill in placements:
        if spill is not None:
            out += spill
            if len(out) % 2:
                out += b"\x00"
    return bytes(out)


def sha256_prefix(path: Path, chars: int = 16) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:chars]


def main() -> None:
    ap = argparse.ArgumentParser(description="Build the synthetic Phase A test images.")
    ap.add_argument("--quality", type=int, default=MASTER_QUALITY,
                    help=f"JPEG quality for the sendable master (default {MASTER_QUALITY})")
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parent.parent.parent
    # Pillow's exif= keyword wants the whole APP1 payload, signature included.
    exif_blob = b"Exif\x00\x00" + build_synthetic_exif(FABRICATED_TAGS)
    for size in SIZES:
        arr = radiograph_like(size, SEED)
        img = Image.fromarray(np.rint(arr).astype(np.uint8), mode="L")

        png_path = OUT_DIR / f"synthetic_chest_{size}.png"
        img.save(png_path, optimize=True)

        master_path = OUT_DIR / f"synthetic_chest_{size}_master.jpg"
        img.save(master_path, "JPEG", quality=args.quality, subsampling="4:4:4",
                 exif=exif_blob)

        for p in (png_path, master_path):
            print(f"{p.relative_to(root)}: {img.width}x{img.height} L, "
                  f"{p.stat().st_size} bytes, sha256:{sha256_prefix(p)}")
    print()
    print("Send the _master.jpg file. Keep the .png untouched as the original;")
    print("record its sha256 so a re-save of the original is impossible to miss.")


if __name__ == "__main__":
    main()
