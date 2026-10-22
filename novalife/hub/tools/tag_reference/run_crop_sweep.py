"""Crop sweep after the erasure + pilot-residual fix: phantom covers and the real scan.

Conditions: control, corner crops, symmetric crops, and crop+JPEG (a crop that then goes
through a chat-app re-encode).  Prints one line per case, unbuffered, so progress is visible.
"""
import os
import sys
import time

import numpy as np
from PIL import Image

HUB = "/run/media/user/DATA/repos/embedded_proj/novalife_hub"
sys.path.insert(0, HUB + "/tools/tag_reference")
sys.path.insert(0, HUB + "/tools/stego_research/sims")

import embed, extract, tag_block  # noqa: E402


def corner(a, f):
    return a[int(a.shape[0] * f):, int(a.shape[1] * f):]


def sym(a, f):
    return a[int(a.shape[0] * f):int(a.shape[0] * (1 - f)),
             int(a.shape[1] * f):int(a.shape[1] * (1 - f))]


def jpeg(a, q):
    import io
    buf = io.BytesIO()
    Image.fromarray(np.ascontiguousarray(a)).save(buf, "JPEG", quality=q, subsampling=0)
    buf.seek(0)
    return np.asarray(Image.open(buf).convert("L"), dtype=np.uint8)


CASES = [
    ("none", lambda a: a),
    ("corner 5%", lambda a: corner(a, 0.05)),
    ("corner 10%", lambda a: corner(a, 0.10)),
    ("corner 25%", lambda a: corner(a, 0.25)),
    ("corner 40%", lambda a: corner(a, 0.40)),
    ("symmetric 5%", lambda a: sym(a, 0.05)),
    ("symmetric 10%", lambda a: sym(a, 0.10)),
    ("corner 25% + q75", lambda a: jpeg(corner(a, 0.25), 75)),
]

results = []
for cseed in (7010, 7011, 7012):
    cover, roi = embed.make_cover(cseed)
    blk = tag_block.build_block(embed.HUB_KEY, tag_block.CURRENT_VERSION,
                                embed.DEMO_HUB_ID, tag_block.new_handle(cseed))
    marked, info = embed.mark(cover, roi, blk)
    print(f"--- cover {cseed} {cover.shape[1]}x{cover.shape[0]} "
          f"capacity {info['blocks_available_per_region']}", flush=True)
    for name, fn in CASES:
        recv = np.ascontiguousarray(fn(marked))
        t0 = time.time()
        r = extract.recover(recv, embed.HUB_KEY, declared_shape=cover.shape,
                            codeword=info["codeword"])
        exact = bool(np.array_equal(np.asarray(r.bits, np.uint8), np.asarray(blk, np.uint8)))
        ok = bool(r.tag_ok and exact)
        results.append((cseed, name, ok))
        print(f"   {name:<16} {recv.shape[1]:>4}x{recv.shape[0]:<4} {time.time() - t0:6.1f}s "
              f"tag={'PASS' if r.tag_ok else 'FAIL'} exact={exact} "
              f"{r.accepted.label[:44]!r}", flush=True)

# the real scan, cropped only (no resize): declared 2048x1154
real = np.asarray(Image.open(os.environ.get("NOVALIFE_REAL_SCAN", "/home/user/novalife_covers/brave_scan.jpg")).convert("L")
                  .resize((2048, 1154), Image.LANCZOS), dtype=np.uint8)
norm = np.clip(np.round(16 + real.astype(np.float64) * (235 - 16) / 255.0), 0, 255).astype(np.uint8)
blk = tag_block.build_block(embed.HUB_KEY, tag_block.CURRENT_VERSION,
                            embed.DEMO_HUB_ID, tag_block.new_handle(20261019))
marked, info = embed.mark(norm, embed.roi_from_image(norm), blk)
for name, fn in (("none", lambda a: a), ("corner 10%", lambda a: corner(a, 0.10)),
                 ("corner 25%", lambda a: corner(a, 0.25))):
    recv = np.ascontiguousarray(fn(marked))
    t0 = time.time()
    r = extract.recover(recv, embed.HUB_KEY, declared_shape=norm.shape,
                        codeword=info["codeword"])
    exact = bool(np.array_equal(np.asarray(r.bits, np.uint8), np.asarray(blk, np.uint8)))
    print(f"--- real scan  {name:<16} {recv.shape[1]:>4}x{recv.shape[0]:<4} "
          f"{time.time() - t0:6.1f}s tag={'PASS' if r.tag_ok else 'FAIL'} exact={exact} "
          f"{r.accepted.label[:44]!r}", flush=True)

tot = len(results)
ok = sum(1 for _c, _n, o in results if o)
print(f"\nphantom crop sweep: {ok}/{tot} exact tag recovery", flush=True)
for name, _ in CASES:
    row = [o for _c, n, o in results if n == name]
    print(f"   {name:<16} {sum(row)}/{len(row)}", flush=True)
