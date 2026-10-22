"""Old (HEAD) vs new (working tree) recovery on the benchmark's real channels."""
import os
import io
import sys

import numpy as np
from PIL import Image

HUB = "/run/media/user/DATA/repos/embedded_proj/novalife_hub"
sys.path.insert(0, HUB + "/tools/tag_reference")
sys.path.insert(0, HUB + "/tools/stego_research/sims")

import embed, extract, extract_old, tag_block

real = np.asarray(Image.open(os.environ.get("NOVALIFE_REAL_SCAN", "/home/user/novalife_covers/brave_scan.jpg")).convert("L")
                  .resize((2048, 1154), Image.LANCZOS), dtype=np.uint8)
norm = np.clip(np.round(16 + real.astype(np.float64) * (235 - 16) / 255.0),
               0, 255).astype(np.uint8)
blk = tag_block.build_block(embed.HUB_KEY, tag_block.CURRENT_VERSION,
                            embed.DEMO_HUB_ID, tag_block.new_handle(20261019))
marked, info = embed.mark(norm, embed.roi_from_image(norm), blk)


def chat(long_edge, q):
    h = round(long_edge * marked.shape[0] / marked.shape[1])
    down = np.asarray(Image.fromarray(marked).resize((long_edge, h), Image.LANCZOS),
                      dtype=np.uint8)
    buf = io.BytesIO()
    Image.fromarray(down).save(buf, "JPEG", quality=q)
    buf.seek(0)
    return np.asarray(Image.open(buf).convert("L"), dtype=np.uint8)


cases = [(2048, 75), (1600, 90), (1600, 75), (1600, 50), (1280, 85), (1280, 75)]
print(f"{'channel':>14} | {'old':^28} | {'new':^28}")
for w, q in cases:
    recv = chat(w, q)
    row = []
    for mod in (extract_old, extract):
        r = mod.recover(recv, embed.HUB_KEY, declared_shape=tuple(norm.shape),
                        codeword=info["codeword"])
        exact = bool(np.array_equal(r.bits, blk))
        ber = ("--" if r.region_hard_ber is None
               else f"{np.mean(r.region_hard_ber):.3f}")
        row.append(f"{'PASS' if r.tag_ok and exact else 'fail':>4} ber={ber}")
    print(f"{w}px q{q:<3} | {row[0]:^28} | {row[1]:^28}")
