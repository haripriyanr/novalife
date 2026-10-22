#!/usr/bin/env python3
"""Golden data for hubcore/extract.c: runs the PYTHON reference recover() on damaged marked images.

    novalife_hub/.venv/bin/python hubcore/tests/gen_extract.py [--jobs N] [--only COVER]

Writes tests/golden/extract_<cover>_<cond>.bin (raw uint8, row-major received image) and
tests/golden/extract_index.json with, per case: shape, declared shape, key, and the Python
verdict (tag_ok, 128 bits, accepted-candidate class, seconds).  The C test must reproduce the
verdict and the bits; it must not hard-code anything.
"""
import argparse, glob, json, os, sys, time
from concurrent.futures import ProcessPoolExecutor
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
TR = os.path.abspath(os.path.join(HERE, "..", "..", "tools", "tag_reference"))
sys.path.insert(0, TR)
sys.path.insert(0, os.path.abspath(os.path.join(TR, "..", "stego_research", "sims")))
import embed, extract, tag_block, run_demo as demo  # noqa: E402

GOLD = os.path.join(HERE, "golden")
MRI_DIR = "/home/user/novalife_covers/mri256"
WRONG_KEY = bytes([0xA5]) * 16

CONDS = [
    ("none", demo.atk_none), ("resize050", demo.atk_resize(0.50)), ("resize075", demo.atk_resize(0.75)),
    ("resize150", demo.atk_resize(1.50)), ("resize200", demo.atk_resize(2.00)),
    ("jpeg90", demo.atk_jpeg(90)), ("jpeg50", demo.atk_jpeg(50)),
    ("crop25", demo.atk_crop_corner(0.25)), ("crop10", demo.atk_crop_corner(0.10)),
    ("screenshot", demo.atk_screenshot), ("awgn2", demo.atk_awgn(2.0)),
]
def _sym(f):
    return lambda a: np.ascontiguousarray(a[int(a.shape[0] * f):int(a.shape[0] * (1 - f)),
                                            int(a.shape[1] * f):int(a.shape[1] * (1 - f))])


CONDS += [
    ("crop40", demo.atk_crop_corner(0.40)), ("cropsym5", _sym(0.05)), ("cropsym10", _sym(0.10)),
    ("crop25jpeg75", lambda a: demo.atk_jpeg(75)(demo.atk_crop_corner(0.25)(a))),
    ("jpeg40", demo.atk_jpeg(40)), ("resize060", demo.atk_resize(0.60)),
    ("resize125jpeg60", lambda a: demo.atk_jpeg(60)(demo.atk_resize(1.25)(a))),
]
COVERS = ["phantom", "mri_M_1", "mri_G_1"]


def make_cover(name):
    if name == "phantom":
        cover, roi = embed.make_cover()
        return cover, roi
    f = name.split("_", 1)[1]
    raw = np.asarray(Image.open(os.path.join(MRI_DIR, f + ".jpg")).convert("L"), dtype=np.uint8)
    up = np.repeat(np.repeat(raw, 2, axis=0), 2, axis=1)
    cover = embed.floor_background(up)
    return cover, embed.roi_from_image(up)


def cls(label):
    if label.startswith("rescale"): return "rescale"
    if label.startswith("residual crop 1.0x"): return "crop_corner"
    if label.startswith("residual crop 0.5x"): return "crop_symmetric"
    if label.startswith("identity"): return "identity"
    if label.startswith("declared geometry"): return "declared"
    return "other"


def hexbits(b):
    return "".join(str(int(x)) for x in np.asarray(b))


def run_case(args):
    cover_name, cond, kind = args
    cover, roi = make_cover(cover_name)
    seed = {"phantom": 20261022, "mri_M_1": 7, "mri_G_1": 9}[cover_name]
    block = tag_block.build_block(embed.HUB_KEY, 1, embed.DEMO_HUB_ID, tag_block.new_handle(seed))
    marked, info = embed.mark(cover, roi, block)
    fn = dict(CONDS).get(cond, demo.atk_none)
    if kind == "unmarked":
        recv = demo.atk_none(cover)
    else:
        recv = fn(marked)
    key = WRONG_KEY if kind == "wrongkey" else embed.HUB_KEY
    t = time.time()
    r = extract.recover(recv, key, cover.shape)
    dt = time.time() - t
    name = f"{cover_name}_{kind if kind != 'normal' else cond}"
    recv.astype(np.uint8).tofile(os.path.join(GOLD, f"extract_{name}.bin"))
    return {
        "name": name, "file": f"extract_{name}.bin", "cover": cover_name, "condition": cond,
        "kind": kind, "shape": [int(recv.shape[0]), int(recv.shape[1])],
        "declared": [int(cover.shape[0]), int(cover.shape[1])],
        "key": key.hex(), "true_bits": hexbits(block),
        "py_tag_ok": bool(r.tag_ok), "py_bits": hexbits(r.bits),
        "py_exact": bool(np.array_equal(np.asarray(r.bits), block)),
        "py_class": cls(r.accepted.label), "py_label": r.accepted.label,
        "py_seconds": round(dt, 1), "copies_written": info["copies_written"],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--only", default=None)
    a = ap.parse_args()
    os.makedirs(GOLD, exist_ok=True)
    jobs = []
    for c in COVERS:
        if a.only and c != a.only: continue
        for cond, _ in CONDS: jobs.append((c, cond, "normal"))
        jobs.append((c, "none", "wrongkey"))
        jobs.append((c, "none", "unmarked"))
    # longest first
    jobs.sort(key=lambda j: 0 if j[1].startswith("crop") else 1)
    out = []
    with ProcessPoolExecutor(a.jobs) as ex:
        for res in ex.map(run_case, jobs):
            print(res["name"], res["py_tag_ok"], res["py_exact"], res["py_class"], res["py_seconds"], flush=True)
            out.append(res)
    out.sort(key=lambda r: r["name"])
    path = os.path.join(GOLD, "extract_index.json" if not a.only else f"extract_index_{a.only}.json")
    json.dump(out, open(path, "w"), indent=1)
    print("wrote", path, len(out))
    write_txt(out, path.replace(".json", ".txt"))
    unit()


def write_txt(out, path):
    """Plain-text index for the C test: name file h w dh dw keyhex py_tag_ok py_class py_bits"""
    with open(path, "w") as f:
        for r in out:
            f.write(f"{r['name']} {r['file']} {r['shape'][0]} {r['shape'][1]} {r['declared'][0]} "
                    f"{r['declared'][1]} {r['key']} {int(r['py_tag_ok'])} {r['py_class']} "
                    f"{r['py_bits']}\n")


def unit():
    """resample_affine + restore's clip(round()) and coverage_map goldens (small images)."""
    from pilot_grid import resample_affine
    rng = np.random.default_rng(4242)
    cases = [  # ih, iw, ay, by, ax, bx, oh, ow  (beta in pixels, as restore passes 2*LL beta)
        (40, 50, 1.0, 0.0, 1.0, 0.0, 40, 50),          # identity, same shape
        (40, 50, 1.0, 0.0, 1.0, 0.0, 60, 70),          # identity map on a bigger frame
        (30, 36, 0.75, -0.5, 0.75, -0.5, 40, 48),      # rescale 0.75 with the fine offset
        (80, 90, 2.0, -0.5, 2.0, -0.5, 40, 45),        # downscale source by 2
        (20, 24, 0.5, -0.5, 0.5, -0.5, 40, 48),        # upscale source
        (30, 40, 1.0, 20.0, 1.0, 30.0, 40, 50),        # corner crop shift
        (30, 40, 1.0, 10.5, 1.0, 15.25, 40, 50),       # half-pixel crop shift
        (30, 40, 1.0, -7.0, 1.0, -9.0, 40, 50),        # negative shift: sy < -1 gives 0
        (33, 47, 0.8123, 0.37, 1.2371, -1.2, 29, 51),  # anisotropic
    ]
    lines = []
    blob = bytearray()
    for k, (ih, iw, ay, by, ax, bx, oh, ow) in enumerate(cases):
        img = rng.integers(0, 256, (ih, iw), dtype=np.uint8)
        out = np.clip(np.round(resample_affine(img, ay, by, ax, bx, (oh, ow))), 0, 255).astype(np.uint8)
        c = extract.Candidate("t", ay, by / 2.0, ax, bx / 2.0)
        cov = extract.coverage_map((ih, iw), c, (oh, ow)).astype(np.uint8)
        blob += img.tobytes() + out.tobytes() + cov.tobytes()
        lines.append(f"{ih} {iw} {ay!r} {by!r} {ax!r} {bx!r} {oh} {ow}")
    open(os.path.join(GOLD, "extract_resample.bin"), "wb").write(bytes(blob))
    open(os.path.join(GOLD, "extract_resample.txt"), "w").write("\n".join(lines) + "\n")
    print("wrote extract_resample.{bin,txt}", len(cases))


if __name__ == "__main__":
    main()
