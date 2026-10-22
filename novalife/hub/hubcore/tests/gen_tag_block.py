#!/usr/bin/env python3
"""Golden tag-block vectors: build (bits), verify incl. single-bit-flip rejections and wrong keys."""
import sys
from pathlib import Path
import numpy as np
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "tools" / "tag_reference"))
import tag_block as tb
rng = np.random.default_rng(11)
def rb(n): return rng.integers(0, 256, n, dtype=np.uint8).tobytes()
def bstr(bits): return "".join(str(int(b)) for b in bits)
lines = []
for i in range(300):
    key = rb(16)
    ver = int(rng.integers(0, 16)); hub = int(rng.integers(0, 4096))
    handle = int.from_bytes(rb(8), "big")
    if i == 0: ver, hub, handle = 0, 0, 0
    if i == 1: ver, hub, handle = 15, 4095, (1 << 64) - 1
    blk = tb.build_block(key, ver, hub, handle)
    # B key ver hub handle bits128 : build
    lines.append(f"B {key.hex()} {ver} {hub} {handle} {bstr(blk)}")
    v = tb.verify_block(blk, key)
    assert v["tag_ok"]
    # V key bits ok ver hub handle tag expected : verify of intact block
    lines.append(f"V {key.hex()} {bstr(blk)} 1 {v['version']} {v['hub_id']} {v['handle']} {v['tag']} {v['expected_tag']}")
    # one random flipped bit (any of 128) -> must reject
    pos = int(rng.integers(0, 128)); bad = blk.copy(); bad[pos] ^= 1
    v = tb.verify_block(bad, key)
    assert not v["tag_ok"]
    lines.append(f"V {key.hex()} {bstr(bad)} 0 {v['version']} {v['hub_id']} {v['handle']} {v['tag']} {v['expected_tag']}")
    # wrong key
    k2 = rb(16); v = tb.verify_block(blk, k2)
    assert not v["tag_ok"]
    lines.append(f"V {k2.hex()} {bstr(blk)} 0 {v['version']} {v['hub_id']} {v['handle']} {v['tag']} {v['expected_tag']}")
# every single bit position flipped once on one block
key = rb(16); blk = tb.build_block(key, 1, 0x9A3, 0x0123456789ABCDEF)
for pos in range(128):
    bad = blk.copy(); bad[pos] ^= 1
    v = tb.verify_block(bad, key); assert not v["tag_ok"]
    lines.append(f"V {key.hex()} {bstr(bad)} 0 {v['version']} {v['hub_id']} {v['handle']} {v['tag']} {v['expected_tag']}")
(HERE / "golden").mkdir(exist_ok=True)
(HERE / "golden" / "tag_block.txt").write_text("\n".join(lines) + "\n")
print(len(lines), "tag_block golden lines")
