#!/usr/bin/env python3
"""Golden IWT vectors.  Binary: u32 count, then per case: i32 h, i32 w, img int32[h*w],
LL,LH,HL,HH int32[(h/2)*(w/2)] each, clipped inverse (uint8->int32) int32[h*w]."""
import sys, struct
from pathlib import Path
import numpy as np
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "tools" / "stego_research" / "sims"))
import iwt_lifting as iw
rng = np.random.default_rng(5)
cases = []
def add(img): cases.append(np.asarray(img, dtype=np.int32))
for (h, w) in [(2, 2), (2, 8), (8, 2), (4, 4), (6, 10), (16, 16), (30, 18), (64, 32), (33*2, 17*2), (128, 96), (256, 256), (512, 512)]:
    add(rng.integers(0, 256, (h, w)))                       # pixels
    add(rng.integers(-32768, 32768, (h, w)))                # full signed 16-bit range
    if h * w <= 70000:
        add(rng.choice([-32768, 32767, 0, 255, -1, 1], (h, w)))   # extremes / floor-sensitive negatives
        add(rng.integers(-(1 << 28), 1 << 28, (h, w)))      # large, within wrap-free range
add(np.zeros((16, 16))); add(np.full((16, 16), 255)); add(np.full((16, 16), -32768)); add(np.full((8, 8), -1))
add(np.tile(np.array([0, 255]), (16, 8)))                   # alternating
add(np.add.outer(np.arange(64), np.arange(64)) * 3)         # ramp
# wrap-around behaviour of numpy int32 (overflow) -- documented equal to C unsigned wrap
add(rng.integers(-(1 << 31), 1 << 31, (8, 8), dtype=np.int64))
(HERE / "golden").mkdir(exist_ok=True)
with open(HERE / "golden" / "iwt.bin", "wb") as f:
    f.write(struct.pack("<I", len(cases)))
    for img in cases:
        h, w = img.shape
        LL, (LH, HL, HH) = iw.iwt2d_53(img)
        # clipped inverse (what Python iiwt2d_53 returns) of the subbands
        inv = iw.iiwt2d_53(LL, (LH, HL, HH)).astype(np.int32)
        f.write(struct.pack("<ii", h, w))
        for a in (img, LL, LH, HL, HH, inv):
            f.write(np.ascontiguousarray(a, dtype="<i4").tobytes())
print(len(cases), "iwt cases")
