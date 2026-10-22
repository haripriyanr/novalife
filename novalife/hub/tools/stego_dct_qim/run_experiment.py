#!/usr/bin/env python3
"""Small, deterministic transform-domain steganography experiment.

The implementation deliberately uses only operations that map to a Zynq PL
reference design: 8x8 separable DCT, integer-ish QIM, HMAC-derived ordering,
and systematic Hamming(7,4) correction with a keyed interleaver.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image


N = 512
BLOCK = 8
RAW_BYTES = 80
KEY = b"novalife-zynq7010-experiment-v1"
COEFFS = [(1, 2), (2, 1), (2, 2), (1, 3), (3, 1), (2, 3), (3, 2), (3, 3)]


def bits_from_bytes(data: bytes) -> np.ndarray:
    return np.unpackbits(np.frombuffer(data, dtype=np.uint8))


def bytes_from_bits(bits: np.ndarray) -> bytes:
    return np.packbits(bits.astype(np.uint8)).tobytes()


def hamming_encode(bits: np.ndarray) -> np.ndarray:
    if len(bits) % 4:
        bits = np.pad(bits, (0, 4 - len(bits) % 4))
    out = []
    for nib in bits.reshape(-1, 4):
        d1, d2, d3, d4 = map(int, nib)
        # Positions 1..7: p1 p2 d1 p4 d2 d3 d4, even parity.
        out.extend([d1 ^ d2 ^ d4, d1 ^ d3 ^ d4, d1, d2 ^ d3 ^ d4, d2, d3, d4])
    return np.array(out, dtype=np.uint8)


def hamming_decode(bits: np.ndarray, expected_bits: int) -> tuple[np.ndarray, int, int]:
    corrected = 0
    nonzero_syndromes = 0
    decoded = []
    for word in bits[: len(bits) // 7 * 7].reshape(-1, 7):
        w = word.copy()
        s1 = int(w[0] ^ w[2] ^ w[4] ^ w[6])
        s2 = int(w[1] ^ w[2] ^ w[5] ^ w[6])
        s4 = int(w[3] ^ w[4] ^ w[5] ^ w[6])
        syndrome = s1 | (s2 << 1) | (s4 << 2)
        if syndrome:
            nonzero_syndromes += 1
            if syndrome <= 7:
                w[syndrome - 1] ^= 1
                corrected += 1
        decoded.extend([w[2], w[4], w[5], w[6]])
    return np.array(decoded[:expected_bits], dtype=np.uint8), corrected, nonzero_syndromes


def keyed_permutation(length: int, label: bytes) -> np.ndarray:
    vals = []
    for i in range(length):
        digest = hmac.new(KEY, label + i.to_bytes(4, "big"), hashlib.sha256).digest()
        vals.append((digest, i))
    return np.array([i for _, i in sorted(vals)], dtype=np.int32)


def keyed_block_order(block_ids: list[int]) -> list[int]:
    return [i for _, i in sorted((hmac.new(KEY, b"block" + i.to_bytes(4, "big"), hashlib.sha256).digest(), i) for i in block_ids)]


def dct_matrix() -> np.ndarray:
    c = np.zeros((8, 8), dtype=np.float64)
    for k in range(8):
        for n in range(8):
            c[k, n] = math.sqrt(1 / 8) if k == 0 else 0.5
            c[k, n] *= math.cos(math.pi * (2 * n + 1) * k / 16)
    return c


C = dct_matrix()


def blocks(image: np.ndarray):
    for by in range(0, image.shape[0], 8):
        for bx in range(0, image.shape[1], 8):
            yield by, bx, image[by : by + 8, bx : bx + 8]


def texture_candidates(image: np.ndarray) -> list[int]:
    scores = []
    for idx, (_, _, block) in enumerate(blocks(image)):
        # Local activity selects textured blocks, where changes are less visible.
        scores.append(float(np.std(block)))
    threshold = float(np.percentile(scores, 35))
    return [i for i, score in enumerate(scores) if score >= threshold]


def slot_plan(image: np.ndarray, count: int, adaptive: bool = True):
    ids = list(range((image.shape[0] // 8) * (image.shape[1] // 8)))
    # The schedule must not depend on the cover: the receiver has only the
    # stego image. Adaptivity is therefore applied to Delta, not membership.
    ids = keyed_block_order(ids)
    if len(ids) < count:
        raise ValueError(f"not enough coefficient slots: {len(ids)} < {count}")
    plan = []
    for block_id in ids[:count]:
        # Key chooses a mid-band coefficient, preventing a fixed pattern.
        digest = hmac.new(KEY, b"coeff" + block_id.to_bytes(4, "big"), hashlib.sha256).digest()
        plan.append((block_id, COEFFS[digest[0] % len(COEFFS)]))
    return plan


def qim_embed(value: float, bit: int, delta: float) -> float:
    # Two cosets separated by delta, with spacing 2*delta.
    return 2 * delta * round((value - bit * delta) / (2 * delta)) + bit * delta


def qim_extract(value: float, delta: float) -> int:
    return int(round(value / delta)) & 1


def transform(image: np.ndarray, payload: bytes | None, adaptive: bool, decode: bool = False):
    expected_bits = RAW_BYTES * 8
    coded_len = (expected_bits // 4) * 7
    interleave = keyed_permutation(coded_len, b"interleave")
    plan = slot_plan(image, coded_len, adaptive)
    out = image.copy().astype(np.float64)
    extracted = []
    for (block_id, (u, v)), coded_index in zip(plan, range(coded_len)):
        by, bx = (block_id // (image.shape[1] // 8)) * 8, (block_id % (image.shape[1] // 8)) * 8
        block = out[by : by + 8, bx : bx + 8]
        coeff = C @ (block - 128.0) @ C.T
        sigma = float(np.std(block))
        delta = (16.0 + 0.15 * sigma) if adaptive else 14.0
        if payload is not None:
            raw_bits = bits_from_bytes(payload)
            coded = hamming_encode(raw_bits)
            bit = int(coded[interleave[coded_index]])
            coeff[u, v] = qim_embed(coeff[u, v], bit, delta)
            out[by : by + 8, bx : bx + 8] = C.T @ coeff @ C + 128.0
        else:
            extracted.append(qim_extract(coeff[u, v], delta))
    if payload is not None:
        return np.clip(np.rint(out), 0, 255).astype(np.uint8), None
    coded_received = np.array(extracted, dtype=np.uint8)
    deinterleaved = np.empty_like(coded_received)
    deinterleaved[interleave] = coded_received
    raw_bits, corrected, syndromes = hamming_decode(deinterleaved, expected_bits)
    return None, (bytes_from_bits(raw_bits), corrected, syndromes)


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    mse = float(np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2))
    return float("inf") if mse == 0 else 10 * math.log10(255 * 255 / mse)


def ssim_global(a: np.ndarray, b: np.ndarray) -> float:
    x, y = a.astype(np.float64), b.astype(np.float64)
    mux, muy = x.mean(), y.mean()
    vx, vy = x.var(), y.var()
    cov = ((x - mux) * (y - muy)).mean()
    c1, c2 = 6.5025, 58.5225
    return float((2 * mux * muy + c1) * (2 * cov + c2) / ((mux * mux + muy * muy + c1) * (vx + vy + c2)))


def evaluate(name: str, cover: np.ndarray, stego: np.ndarray, payload: bytes):
    decoded_image, info = transform(stego, None, adaptive=True)
    recovered, corrected, syndromes = info
    reference_bits, recovered_bits = bits_from_bytes(payload), bits_from_bytes(recovered[:RAW_BYTES])
    ber = float(np.mean(reference_bits != recovered_bits))
    return {"attack": name, "psnr_db": psnr(cover, stego), "ssim_global": ssim_global(cover, stego),
            "ber": ber, "payload_ok": recovered[:RAW_BYTES] == payload,
            "hamming_corrected": corrected, "hamming_nonzero_syndromes": syndromes}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cover", default="cover.jpg")
    ap.add_argument("--out", default=".")
    args = ap.parse_args()
    out = Path(args.out)
    rgb = Image.open(args.cover).convert("L").resize((N, N), Image.Resampling.LANCZOS)
    cover = np.asarray(rgb, dtype=np.uint8)
    payload = bytes((hashlib.sha256(b"reproducible-zynq-payload").digest() * 4)[:RAW_BYTES])

    stego, _ = transform(cover, payload, adaptive=True)
    Image.fromarray(stego).save(out / "stego.png")
    results = [evaluate("none", cover, stego, payload)]

    jpeg_path = out / "attacked_quality70.jpg"
    Image.fromarray(stego).save(jpeg_path, quality=70, subsampling=0)
    jpeg = np.asarray(Image.open(jpeg_path).convert("L"), dtype=np.uint8)
    results.append(evaluate("JPEG quality=70", cover, jpeg, payload))

    rng = np.random.default_rng(7010)
    noisy = np.clip(stego.astype(np.int16) + rng.normal(0, 2.0, stego.shape), 0, 255).astype(np.uint8)
    Image.fromarray(noisy).save(out / "attacked_awgn_sigma2.png")
    results.append(evaluate("AWGN sigma=2", cover, noisy, payload))

    # A control quantifies the quality cost of a non-adaptive, fixed-step DCT plan.
    fixed, _ = transform(cover, payload, adaptive=False)
    Image.fromarray(fixed).save(out / "control_fixed_qim.png")
    control = {"psnr_db": psnr(cover, fixed), "ssim_global": ssim_global(cover, fixed)}

    report = {"image": str(args.cover), "image_size": list(cover.shape), "seed": 7010,
              "key_sha256": hashlib.sha256(KEY).hexdigest(), "raw_payload_bytes": RAW_BYTES,
              "coded_bits": RAW_BYTES * 8 // 4 * 7, "raw_payload_bpp": RAW_BYTES * 8 / cover.size,
              "code": "systematic Hamming(7,4), rate 4/7, keyed bit interleaver",
              "embedding": "8x8 DCT QIM; adaptive delta=16+0.15*local_std; keyed mid-band coefficient",
              "results": results, "fixed_qim_control": control}
    (out / "metrics.json").write_text(json.dumps(report, indent=2) + "\n")
    lines = ["# Transform-Domain Steganography Experiment", "", "See `metrics.json` for exact output.", ""]
    for row in results:
        lines.append(f"- {row['attack']}: PSNR {row['psnr_db']:.2f} dB, global SSIM {row['ssim_global']:.6f}, BER {row['ber']:.6f}, payload_ok={row['payload_ok']}")
    lines += ["", f"Fixed-step control: PSNR {control['psnr_db']:.2f} dB, global SSIM {control['ssim_global']:.6f}.", "", "The keyed schedule is a security aid, not encryption; encrypt/authenticate the payload before ECC in deployment."]
    (out / "RESULTS.md").write_text("\n".join(lines) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
