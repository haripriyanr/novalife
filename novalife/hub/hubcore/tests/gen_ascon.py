#!/usr/bin/env python3
"""Golden hub-path vectors for hubcore ascon: aead, mac_truncated, keystream (all from the Python)."""
import sys
from pathlib import Path
import numpy as np
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "tools" / "tag_reference"))
import ascon_primitives as ap
rng = np.random.default_rng(7)
def rb(n): return rng.integers(0, 256, n, dtype=np.uint8).tobytes()
def h(b): return b.hex() if b else "-"
lines = []
for _ in range(300):
    k, n = rb(16), rb(16)
    pt, ad = rb(int(rng.integers(0, 80))), rb(int(rng.integers(0, 80)))
    lines.append(f"E {h(k)} {h(n)} {h(pt)} {h(ad)} {h(ap.ascon_aead_encrypt(k, n, pt, ad))}")
for _ in range(200):
    k = rb(16); msg = rb(int(rng.integers(0, 300)))   # >256 total exercises the malloc path
    nb = int(rng.choice([8, 16, 48, 64, 128]))
    lines.append(f"M {h(k)} {h(msg)} {nb} {h(ap.mac_truncated(k, msg, nb))}")
for _ in range(100):
    k = rb(16); dom = rb(int(rng.integers(0, 40))); nb = int(rng.integers(0, 3000))
    lines.append(f"K {h(k)} {h(dom)} {nb} {h(ap.keystream(k, dom, nb))}")
(HERE / "golden").mkdir(exist_ok=True)
(HERE / "golden" / "ascon_hub.txt").write_text("\n".join(lines) + "\n")
print(len(lines), "ascon golden lines")
