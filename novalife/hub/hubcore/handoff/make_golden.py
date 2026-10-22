"""Writes golden/ for run_golden.c from the Python reference in ./python (the oracle).

    novalife_hub/.venv/bin/python make_golden.py [--quick]

Cases (case.json lists them):  mark_*   : cover.bin, key, block, expected marked.bin + info
                               recover_*: image.bin (damaged marked image), expected tag_ok/block
Covers: MRI slices (needs /home/user/novalife_covers/mri256, 2x nearest -> 512x512, floored),
the native 256x256 slice N_10 (markable), and a smaller phantom crop of embed.make_cover().
"""
import glob, io, json, os, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "python"))
import embed, extract, tag_block  # noqa: E402

OUT = os.path.join(HERE, "golden"); os.makedirs(OUT, exist_ok=True)
KEY = embed.HUB_KEY
cases = []

def dump(name, arr):
    np.ascontiguousarray(arr, dtype=np.uint8).tofile(os.path.join(OUT, name))

def resize(a, f):
    h, w = a.shape; return np.asarray(Image.fromarray(a).resize((int(w*f)//2*2, int(h*f)//2*2), Image.BICUBIC), dtype=np.uint8)
def jpeg(a, q):
    b = io.BytesIO(); Image.fromarray(a).save(b, "JPEG", quality=q); return np.asarray(Image.open(io.BytesIO(b.getvalue())), dtype=np.uint8)

covers = {}
for f in sorted(glob.glob("/home/user/novalife_covers/mri256/*.jpg"))[:3]:
    a = np.asarray(Image.open(f).convert("L"), dtype=np.uint8)
    covers[os.path.basename(f)[:-4] + "_2x"] = embed.floor_background(np.repeat(np.repeat(a, 2, 0), 2, 1))
    if os.path.basename(f).startswith("N_10"):
        covers["N_10_native"] = embed.floor_background(a)
ph, _ = embed.make_cover(); covers["phantom_crop"] = ph[:512, :768].copy()

hs = [0x1234567812345678, 0x0FEDCBA987654321]
for ci, (name, cov) in enumerate(covers.items()):
    h, w = cov.shape
    for hi, handle in enumerate(hs[:1 if "phantom" in name else 2]):
        block = tag_block.build_block(KEY, 1, embed.DEMO_HUB_ID, handle)
        cid = f"mark_{name}_{hi}"
        try:
            marked, info = embed.mark(cov, embed.roi_from_image(cov), block, KEY)
        except ValueError:
            cases.append({"id": cid, "kind": "mark", "h": h, "w": w, "refused": True,
                          "block": tag_block.bits_to_bytes(block).hex()}); dump(cid + ".cover.bin", cov); continue
        dump(cid + ".cover.bin", cov); dump(cid + ".marked.bin", marked)
        cases.append({"id": cid, "kind": "mark", "h": h, "w": w, "refused": False,
                      "block": tag_block.bits_to_bytes(block).hex(), "copies": info["copies_written"],
                      "capacity": [int(x) for x in info["blocks_available_per_region"]]})
        if hi == 0:
            for cname, img in [("none", marked), ("rs0.5", resize(marked, .5)), ("rs0.75", resize(marked, .75)),
                               ("rs1.5", resize(marked, 1.5)), ("jpg90", jpeg(marked, 90)), ("jpg50", jpeg(marked, 50)),
                               ("crop25", marked[h//4:, w//4:]), ("shot", jpeg(resize(marked, .75), 80))]:
                if "--quick" in sys.argv and cname not in ("none", "rs0.75", "jpg50"): continue
                r = extract.recover(img, KEY, (h, w))
                rid = f"recover_{name}_{cname}"
                dump(rid + ".img.bin", img)
                cases.append({"id": rid, "kind": "recover", "h": int(img.shape[0]), "w": int(img.shape[1]),
                              "decl_h": h, "decl_w": w, "tag_ok": bool(r.tag_ok),
                              "block": tag_block.bits_to_bytes(r.bits).hex() if r.tag_ok else ""})
            # wrong key and unmarked must NOT verify
            for rid, img, key in [(f"recover_{name}_wrongkey", marked, bytes([0xA5]) * 16), (f"recover_{name}_unmarked", cov, KEY)]:
                dump(rid + ".img.bin", img)
                cases.append({"id": rid, "kind": "recover", "h": h, "w": w, "decl_h": h, "decl_w": w, "tag_ok": False,
                              "block": "", "key": key.hex()})
json.dump(cases, open(os.path.join(OUT, "cases.json"), "w"), indent=1)
with open(os.path.join(OUT, "cases.txt"), "w") as fh:   # line format for run_golden.c
    for c in cases:
        if c["kind"] == "mark":
            cap = c.get("capacity", [0, 0, 0, 0])
            fh.write(f"mark {c['id']} {c['h']} {c['w']} {int(c['refused'])} {c.get('copies', 0)} "
                     f"{cap[0]} {cap[1]} {cap[2]} {cap[3]} {c['block']}\n")
        else:
            fh.write(f"recover {c['id']} {c['h']} {c['w']} {c['decl_h']} {c['decl_w']} {int(c['tag_ok'])} "
                     f"{c['block'] or '-'} {c.get('key', KEY.hex())}\n")
print(len(cases), "cases:", sum(c["kind"] == "mark" for c in cases), "mark,", sum(c["kind"] == "recover" for c in cases), "recover")
