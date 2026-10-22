"""Old (HEAD) vs new recovery on the phantom covers, on the conditions my change touches.

The gate edit can only matter when the pilot residual test fails.  This prints, per
condition, the verdict for both versions plus whether the gate was satisfied -- so the
"nothing that passed regressed" claim is measured, not argued.
"""
import subprocess
import sys

import numpy as np

HUB = "/run/media/user/DATA/repos/embedded_proj/novalife_hub"
sys.path.insert(0, HUB + "/tools/tag_reference")
import os; os.makedirs("/tmp/opencode", exist_ok=True)
sys.path.insert(0, HUB + "/tools/stego_research/sims")

src = subprocess.run(["git", "show", "HEAD:tools/tag_reference/extract.py"],
                     cwd=HUB, capture_output=True, text=True, check=True).stdout
open("/tmp/opencode/extract_old.py", "w").write(src)
sys.path.insert(0, "/tmp/opencode")

import embed, extract, extract_old, tag_block
import run_demo as demo

CONDS = [
    ("none", demo.atk_none),
    ("jpeg_q50", demo.atk_jpeg(50)),
    ("jpeg_q40", demo.atk_jpeg(40)),
    ("resize_050", demo.atk_resize(0.50)),
    ("resize_075", demo.atk_resize(0.75)),
    ("resize_150", demo.atk_resize(1.50)),
    ("resize_200", demo.atk_resize(2.00)),
    ("screenshot_like", demo.atk_screenshot),
    ("crop_corner_25", demo.atk_crop_corner(0.25)),
]

n_diff = 0
for cseed in [7010, 7011, 7012, 7013, 7014]:
    cover, roi = embed.make_cover(cseed)
    block = tag_block.build_block(embed.HUB_KEY, tag_block.CURRENT_VERSION,
                                  embed.DEMO_HUB_ID, tag_block.new_handle(cseed))
    marked, info = embed.mark(cover, roi, block)
    line = []
    for name, fn in CONDS:
        recv = fn(marked)
        out = []
        for mod in (extract_old, extract):
            r = mod.recover(recv, embed.HUB_KEY, declared_shape=cover.shape,
                            codeword=info["codeword"])
            exact = bool(np.array_equal(np.asarray(r.bits, np.uint8),
                                        np.asarray(block, np.uint8)))
            out.append(r.tag_ok and exact)
        if out[0] != out[1]:
            n_diff += 1
        line.append(f"{name}={'Y' if out[0] else 'n'}->{'Y' if out[1] else 'n'}")
    print(f"cover {cseed}: " + " ".join(line))

print(f"\nconditions whose verdict changed old->new: {n_diff}")
