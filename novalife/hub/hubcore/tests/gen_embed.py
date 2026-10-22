#!/usr/bin/env python3
"""Golden data for the embedder (module B).  Oracle: tools/tag_reference/embed.py.

Writes tests/golden/embed_unit.bin and tests/golden/embed_e2e.bin.  Format: a stream of
little-endian int64 words ("i") and raw byte runs ("b", no padding); the C reader
(tests/test_embed.c, tests/test_embed_e2e.c) mirrors it call for call and checks the section
magics, so any desync fails loudly.
Run: novalife_hub/.venv/bin/python hubcore/tests/gen_embed.py [--skip-e2e]
"""
from __future__ import annotations

import math
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools" / "tag_reference"))
sys.path.insert(0, str(ROOT / "tools" / "stego_research" / "sims"))
import embed  # noqa: E402
from tag_block import build_block  # noqa: E402

G = HERE / "golden"
G.mkdir(exist_ok=True)
MRI = Path("/home/user/novalife_covers/mri256")


class W:
    def __init__(self):
        self.parts: list[bytes] = []

    def i(self, *vals):
        for v in vals:
            v = int(v)
            self.parts.append(struct.pack("<Q" if v >= 1 << 63 else "<q", v))

    def d(self, v):
        self.parts.append(struct.pack("<d", float(v)))

    def b(self, data):
        if isinstance(data, np.ndarray):
            data = data.tobytes()
        self.parts.append(bytes(data))

    def save(self, path):
        Path(path).write_bytes(b"".join(self.parts))
        print(f"wrote {path} ({sum(map(len, self.parts))} bytes)")


def u8(a):
    return np.ascontiguousarray(np.asarray(a).astype(np.uint8))


# --------------------------------------------------------------------------- unit goldens
def unit(rng) -> None:
    w = W()

    # --- A: roi_cut on raw statistics ------------------------------------------------
    cases = []
    for n in (1, 2, 3, 4, 16, 100, 4096, 65536, 1 << 20):
        for _ in range(60):
            kind = rng.integers(0, 5)
            if kind == 0:
                a = rng.integers(0, 256, n)
            elif kind == 1:
                a = np.where(rng.random(n) < rng.random(), 0, rng.integers(0, 256, n))
            elif kind == 2:
                a = np.clip(rng.normal(rng.integers(0, 256), rng.integers(0, 80), n), 0, 255)
            elif kind == 3:
                a = np.full(n, rng.integers(0, 256))
            else:
                a = np.where(rng.random(n) < 0.02, 255, rng.integers(0, 3, n))
            a = a.astype(np.int64)
            cases.append((n, int(a.sum()), int((a * a).sum())))
    for n in (1 << 24, (1 << 24) - 1, 4096 * 4000):   # extreme sizes with consistent stats
        for v in (0, 1, 16, 128, 255):
            cases.append((n, v * n, v * v * n))
        s = 255 * (n // 2)
        cases.append((n, s, 255 * 255 * (n // 2)))
        s = 255 * (n // 100)
        cases.append((n, s, 255 * 255 * (n // 100)))
        cases.append((n, 255 * 3, 255 * 255 * 3))
    cases.append((0, 0, 0))
    w.i(0xA1, len(cases))
    for n, s, q in cases:
        w.i(n, s, q, embed.roi_cut(n, s, q))

    # --- B: images: roi_from_image, floor_background, masks ----------------------------
    img_cases = []
    shapes = [(8, 8), (16, 24), (32, 32), (48, 64), (64, 64), (96, 80), (128, 128), (60, 100),
              (7, 9), (33, 17)]
    for k in range(70):
        h, wd = shapes[k % len(shapes)]
        kind = rng.integers(0, 6)
        if kind == 0:
            im = rng.integers(0, 256, (h, wd))
        elif kind == 1:  # bright blob on black
            yy, xx = np.mgrid[0:h, 0:wd]
            blob = ((yy - h / 2) ** 2 + (xx - wd / 2) ** 2) < (min(h, wd) / 3) ** 2
            im = np.where(blob, rng.integers(120, 250, (h, wd)), rng.integers(0, 8, (h, wd)))
        elif kind == 2:  # clipped margin
            im = rng.integers(60, 200, (h, wd))
            im[: h // 4] = 0
            im[:, -(wd // 5):] = 255
        elif kind == 3:
            im = np.clip(rng.normal(100, 20, (h, wd)), 0, 255)
        elif kind == 4:
            im = np.full((h, wd), rng.integers(0, 256))
        else:  # many values around the stats floor 16
            im = rng.integers(10, 24, (h, wd))
        img_cases.append(u8(im))
    w.i(0xB1, len(img_cases))
    for k, im in enumerate(img_cases):
        h, wd = im.shape
        has_valid = k % 3 == 0
        valid = None
        if has_valid:
            valid = np.ones((h, wd), np.uint8)
            m = k % 9
            if m == 0:
                valid[:, wd * 2 // 3:] = 0
            elif m == 3:
                valid[: h // 2, :] = 0
                valid[:, : wd // 4] = 0
            else:
                valid = (rng.random((h, wd)) < 0.6).astype(np.uint8)
            if k == 30:
                valid[:] = 0
        # ll_shape: native, sometimes mismatched (bigger / smaller)
        lh, lw = (h // 2) // 4 * 4, (w_ := wd // 2) // 4 * 4
        if k % 7 == 3:
            lh, lw = lh + 8, lw + 4
        if k % 7 == 5:
            lh, lw = max(4, lh - 4), max(4, lw - 4)
        if lh == 0 or lw == 0:
            lh, lw = 4, 4
        ll_shape = (lh, lw)
        nbh, nbw = lh // 4, lw // 4
        rb, rl = embed.roi_masks(ll_shape, im, valid=valid)
        w.i(h, wd, lh, lw, int(has_valid))
        w.b(im)
        if has_valid:
            w.b(valid)
        w.b(u8(embed.roi_from_image(im, valid=valid)))
        w.b(u8(embed.floor_background(im)))
        w.b(u8(rb))
        w.b(u8(rl))
        w.b(u8(embed.clipped_blocks(ll_shape, im)))
        w.b(u8(embed.placement_blocks(ll_shape, im, valid=valid)))
        w.b(u8(embed.blocked_blocks(ll_shape, im, coverage=valid)))
        if has_valid:
            w.b(u8(embed.undercovered_blocks(ll_shape, valid)))

    # --- C: region capacities -------------------------------------------------------
    caps = []
    for nbh, nbw in [(4, 4), (8, 8), (16, 20), (32, 32), (64, 64), (1, 1), (10, 3)]:
        for dens in (0.0, 0.1, 0.5, 0.9, 1.0):
            caps.append((nbh, nbw, rng.random((nbh, nbw)) < dens))
    w.i(0xC1, len(caps))
    for nbh, nbw, bl in caps:
        ls = (nbh * 4, nbw * 4)
        w.i(nbh, nbw)
        w.b(u8(bl))
        c = embed.region_capacities(embed.block_universe(ls), bl, ls)
        w.i(*c)

    # --- D: placement_permute ----------------------------------------------------------
    keys = [bytes(rng.integers(0, 256, 16, dtype=np.uint8)) for _ in range(5)]
    keys.append(embed.HUB_KEY)
    keys.append(bytes(16))
    perm_cases = []
    for key in keys:
        for m in (1, 2, 3, 4, 5, 255, 256, 257, 1000, 1024, 1025, 4096, 4097, 16384, 37000):
            if m <= 300:
                slots = list(range(m))
            else:
                slots = [int(s) for s in rng.integers(0, m, 120)] + [0, m - 1]
            perm_cases.append((key, m, slots))
    w.i(0xD1, len(perm_cases))
    for key, m, slots in perm_cases:
        w.b(key)
        w.i(m, len(slots))
        for s in slots:
            w.i(s, embed.placement_permute(key, m, s))

    # --- E: placement_map ---------------------------------------------------------------
    pm_cases = []
    for nbh, nbw in [(16, 16), (24, 24), (32, 32), (16, 40), (64, 64), (9, 20), (8, 8), (17, 33)]:
        for dens in (0.0, 0.3, 0.7, 0.9, 0.97):
            for erasure in (0, 1):
                key = bytes(rng.integers(0, 256, 16, dtype=np.uint8))
                bl = rng.random((nbh, nbw)) < dens
                pm_cases.append((key, nbh, nbw, bl, erasure))
    w.i(0xE1, len(pm_cases))
    for key, nbh, nbw, bl, erasure in pm_cases:
        ls = (nbh * 4, nbw * 4)
        w.b(key)
        w.i(nbh, nbw, erasure)
        w.b(u8(bl))
        for r in range(4):
            try:
                order = embed.placement_map(key, ls, r, bl, 256, None, bool(erasure))
                w.i(0)
                for pos in order:
                    w.i(-1 if pos is None else (pos[0] // 4) * nbw + pos[1] // 4)
            except ValueError:
                w.i(1)

    # --- F: integer helpers -----------------------------------------------------------------
    vs = [0, 1, 2, 3, 4, 8, 9, 15, 16, 17, (1 << 31) - 1, 1 << 31, (1 << 32) - 1, 1 << 32,
          (1 << 53) - 1, 1 << 53, (1 << 62) - 1, 1 << 62, (1 << 63) - 1, (1 << 63), (1 << 64) - 1]
    for k in (1, 2, 3, 255, 256, 65535, 65536, (1 << 31) - 1, 1 << 31, (1 << 32) - 1):
        vs += [k * k - 1, k * k, k * k + 1]
    vs += [int(x) for x in rng.integers(0, 1 << 62, 300)]
    vs += [int(x) for x in rng.integers(0, 1 << 31, 300)]
    vs += list(range(0, 600))
    w.i(0xF1, len(vs))
    for v in vs:
        w.i(v)
        w.b(struct.pack("<Q", math.isqrt(v)))
    stds = list(range(0, 2000)) + [int(x) for x in rng.integers(0, 1 << 32, 200)]
    w.i(0xF2, len(stds))
    for s in stds:
        w.i(s, embed.qim_delta(s))

    lv_cases = []
    for k in range(120):
        lh, lw = int(rng.integers(1, 40)), int(rng.integers(1, 40))
        kind = k % 4
        if kind == 0:
            ll = rng.integers(-300, 700, (lh, lw))
        elif kind == 1:
            ll = np.full((lh, lw), rng.integers(-50, 400))
        elif kind == 2:
            ll = rng.integers(-2000000, 2000000, (lh, lw))
        else:
            ll = rng.integers(0, 4, (lh, lw)) * rng.integers(-1000, 1000)
        ll = ll.astype(np.int32)
        pos = [(int(rng.integers(-5, lh + 5)), int(rng.integers(-5, lw + 5))) for _ in range(40)]
        lv_cases.append((ll, pos))
    w.i(0xF3, len(lv_cases))
    for ll, pos in lv_cases:
        lh, lw = ll.shape
        w.i(lh, lw, len(pos))
        w.b(ll)
        for r, c in pos:
            w.i(r, c, embed.local_variance(ll, r, c), embed.local_std(ll, r, c))

    # --- G: block arithmetic -----------------------------------------------------------------
    blk_cases = []
    for k in range(4000):
        kind = k % 5
        if kind == 0:
            x = rng.integers(-40, 400, (4, 4))
        elif kind == 1:
            x = rng.integers(-3, 4, (4, 4))
        elif kind == 2:
            x = rng.integers(-100000, 100000, (4, 4))
        elif kind == 3:
            x = np.full((4, 4), rng.integers(-200, 200))
        else:
            x = (embed.HADAMARD * rng.integers(-60, 60)) + rng.integers(-2, 3, (4, 4))
        delta = int(64 + 2 * rng.integers(0, 400))
        blk_cases.append((x.astype(np.int32), int(rng.integers(0, 2)), delta))
    w.i(0x61, len(blk_cases))
    for x, bit, delta in blk_cases:
        v = embed.block_projection(x)
        q = embed.quantize_block(x, bit, delta)
        assert np.abs(q).max() < 2 ** 31
        b, l = embed.read_block_llr(x, delta)
        w.b(x)
        w.i(bit, delta, v, embed.embed_error(v, bit, delta))
        w.b(q.astype(np.int32))
        w.i(b)
        w.d(l)
        w.d(embed.block_confidence(x, delta))
        # read back of the quantised block
        b2, l2 = embed.read_block_llr(q, delta)
        w.i(b2)
        w.d(l2)

    # --- H: read_block on a band --------------------------------------------------------------
    rb_cases = []
    for k in range(40):
        lh, lw = int(rng.integers(4, 40)), int(rng.integers(4, 40))
        ll = rng.integers(-100, 600, (lh, lw)).astype(np.int32)
        pos = [(int(rng.integers(0, lh - 3)), int(rng.integers(0, lw - 3))) for _ in range(30)]
        rb_cases.append((ll, pos))
    w.i(0x71, len(rb_cases))
    for ll, pos in rb_cases:
        lh, lw = ll.shape
        w.i(lh, lw, len(pos))
        w.b(ll)
        for r, c in pos:
            d = embed.qim_delta(embed.local_std(ll, r, c))
            b, l = embed.read_block_llr(ll[r:r + 4, c:c + 4], d)
            w.i(r, c, d, b)
            w.d(l)
    w.i(0xFF)
    w.save(G / "embed_unit.bin")


# --------------------------------------------------------------------------- end-to-end
def nearest2x(a):
    return np.repeat(np.repeat(a, 2, axis=0), 2, axis=1)


def e2e(rng) -> None:
    covers: list[np.ndarray] = []
    drawn: list[np.ndarray | None] = []
    cases = []  # (name, cover_idx, key, bits)

    def add_cover(a, dr=None):
        covers.append(u8(a))
        drawn.append(None if dr is None else u8(dr))
        return len(covers) - 1

    # phantom, 3 handles
    cover, roi = embed.make_cover()
    ci = add_cover(cover, roi)
    for hnd in (0x1234567812345678, 0xDEADBEEFCAFEF00D, 0x0000000000000001):
        cases.append((f"phantom_{hnd:016x}", ci, embed.HUB_KEY,
                      build_block(embed.HUB_KEY, 1, embed.DEMO_HUB_ID, hnd)))
    # phantom with a different key
    k2 = bytes(rng.integers(0, 256, 16, dtype=np.uint8))
    cases.append(("phantom_key2", ci, k2, build_block(k2, 1, 0x123, 0x0F0F0F0F0F0F0F0F)))

    # MRI slices
    for jp in sorted(MRI.glob("*.jpg")):
        raw = np.asarray(Image.open(jp).convert("L"), dtype=np.uint8)
        fl = embed.floor_background(raw)
        stem = jp.stem
        for tag, im in (("raw", raw), ("floored", fl), ("floored2x", nearest2x(fl)),
                        ("raw2x", nearest2x(raw))):
            ci = add_cover(im)
            hnd = int(rng.integers(1, 1 << 62))
            cases.append((f"mri_{stem}_{tag}", ci, embed.HUB_KEY,
                          build_block(embed.HUB_KEY, 1, embed.DEMO_HUB_ID, hnd)))
    # random synthetic clipped margin: refused, then repaired by floor_background
    rr = rng.integers(60, 200, (320, 400)).astype(np.uint8)
    rr[:60] = 0
    rr[:, :50] = 0
    rr[:, -40:] = 255
    ci = add_cover(rr)
    cases.append(("clipped_margin", ci, embed.HUB_KEY,
                  build_block(embed.HUB_KEY, 1, embed.DEMO_HUB_ID, 77)))
    ci = add_cover(embed.floor_background(rr))
    cases.append(("clipped_margin_floored", ci, embed.HUB_KEY,
                  build_block(embed.HUB_KEY, 1, embed.DEMO_HUB_ID, 78)))
    # clipped black margin around a textured disc, 400x400
    yy, xx = np.mgrid[0:400, 0:400]
    disc = ((yy - 200) ** 2 + (xx - 200) ** 2) < 110 ** 2
    im = np.where(disc, rng.integers(110, 235, (400, 400)), 0).astype(np.uint8)
    ci = add_cover(im)
    cases.append(("black_margin_disc", ci, embed.HUB_KEY,
                  build_block(embed.HUB_KEY, 1, embed.DEMO_HUB_ID, 79)))
    ci = add_cover(embed.floor_background(im))
    cases.append(("black_margin_disc_floored", ci, embed.HUB_KEY,
                  build_block(embed.HUB_KEY, 1, embed.DEMO_HUB_ID, 80)))
    # noise images (no ROI structure), mid-gray; also tiny and flat ones
    for nm, shp, lo, hi in (("noise_256", (256, 256), 80, 170), ("noise_wide", (192, 640), 90, 160),
                            ("tiny_64", (64, 64), 80, 160), ("small_128", (128, 128), 90, 160)):
        ci = add_cover(rng.integers(lo, hi, shp).astype(np.uint8))
        cases.append((nm, ci, embed.HUB_KEY,
                      build_block(embed.HUB_KEY, 1, embed.DEMO_HUB_ID, int(rng.integers(1, 1 << 40)))))
    for nm, val in (("flat_255", 255), ("flat_128", 128), ("flat_0", 0)):
        ci = add_cover(np.full((256, 256), val, np.uint8))
        cases.append((nm, ci, embed.HUB_KEY,
                      build_block(embed.HUB_KEY, 1, embed.DEMO_HUB_ID, 5)))
    # an odd-sized-LL-grid case (LL not a multiple of 4): 250x246 -> 125x123
    ci = add_cover(rng.integers(90, 170, (250, 246)).astype(np.uint8))
    cases.append(("noise_odd_ll", ci, embed.HUB_KEY,
                  build_block(embed.HUB_KEY, 1, embed.DEMO_HUB_ID, 99)))
    # a 512x512 bench image (floored MRI at 2x) is already in the list (mri_*_floored2x)

    w = W()
    w.i(0xE2E, len(covers), len(cases))
    for a, dr in zip(covers, drawn):
        w.i(a.shape[0], a.shape[1], 0 if dr is None else 1)
        w.b(a)
        if dr is not None:
            w.b(dr)
    n_ok = n_ref = 0
    for k, (name, ci, key, bits) in enumerate(cases):
        cov = covers[ci]
        dr = drawn[ci]
        nb = name.encode()
        w.i(len(nb))
        w.b(nb)
        w.i(ci)
        w.b(key)
        w.b(u8(bits))
        h, wd = cov.shape
        drawn_arr = dr if dr is not None else np.zeros_like(cov)
        try:
            marked, info = embed.mark(cov, drawn_arr, bits, key)
        except ValueError as exc:
            n_ref += 1
            lls = (h // 2, w_ := wd // 2)
            rb, _ = embed.roi_masks(lls, cov)
            clip = embed.clipped_blocks(lls, cov)
            uni = embed.block_universe(lls)
            avail = embed.region_capacities(uni, rb | clip, lls)
            assert avail[0] < 256, "refusal but capacity ok?"
            clip_only = embed.region_capacities(uni, clip, lls)[0]
            roi_only = embed.region_capacities(uni, rb, lls)[0]
            assert f"available {avail[0]}; ignoring the ROI taint {clip_only}, ignoring the clipping taint {roi_only}." in str(exc), str(exc)
            w.i(1)
            w.i(*avail)
            w.i(clip_only, roi_only)
            print(f"[{k+1}/{len(cases)}] {name}: refused avail={avail} clip_only={clip_only} roi_only={roi_only}")
            continue
        n_ok += 1
        w.i(0)
        w.b(u8(marked))
        w.i(info["max_abs_change_inside_drawn_roi"], info["max_abs_change_inside_algorithm_roi"],
            info["max_abs_change_outside_roi"])
        w.d(info["mean_abs_change_outside_roi"])
        w.i(info["support_rule_violations"])
        w.i(*info["blocks_available_per_region"])
        w.i(*info["blocks_blocked_by_clipping_per_region"])
        w.i(info["blocks_used_per_region"], info["copies_written"], info["pixels_clipped_after_inverse"])
        w.i(*info["ll_shape"])
        w.d(info["drawn_vs_algorithm_roi_jaccard"])
        w.b(u8(info["codeword"]))
        nbw = info["ll_shape"][1] // 4
        pl = np.full((4, 256), -1, np.int32)
        for c, order in enumerate(info["placements"]):
            for i, (br, bc) in enumerate(order):
                pl[c, i] = (br // 4) * nbw + bc // 4
        w.b(pl)
        print(f"[{k+1}/{len(cases)}] {name}: ok copies={info['copies_written']} "
              f"avail={info['blocks_available_per_region']} tag_ok={info['round_trip_tag_ok']}")
    w.i(0xFF)
    w.save(G / "embed_e2e.bin")
    print(f"e2e: {n_ok} marked, {n_ref} refused")


if __name__ == "__main__":
    rng = np.random.default_rng(20261022)
    unit(rng)
    if "--skip-e2e" not in sys.argv:
        e2e(np.random.default_rng(20261023))
