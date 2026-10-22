# Software baseline: DCT-QIM payload embedding (measured)

> Measured 2026-09-15, re-run and confirmed 2026-09-14/16. Code: `tools/stego_dct_qim/run_experiment.py`.
> Raw data: `tools/stego_research/results/baseline_seed7010.json`, `validation_p9_10.json`,
> `tools/stego_dct_qim/metrics.json`.

## Conditions

| | |
|---|---|
| Cover | 512x512 grayscale JPEG, `tools/stego_dct_qim/cover.jpg`, sha256 `28097f4b15d7ff8c63920ff3df4d466dcf869c041de219af3c448e632d3a28d2` |
| Seed | 7010 |
| Payload | 80 bytes, coded to 1120 bits |
| Code | systematic Hamming(7,4), rate 4/7, keyed bit interleaver |
| Embedding | 8x8 DCT, QIM with adaptive delta = 16 + 0.15 x local_std, keyed mid-band coefficient |
| Machine | Python, this host. **Software simulation, not the board.** |

## Results

| Attack | PSNR dB | SSIM | BER | Payload recovered | Hamming bits corrected |
|---|---:|---:|---:|---|---:|
| none | 50.78 | 0.999912 | 0 | yes | 0 |
| JPEG quality 70 | 44.70 | 0.999644 | 0 | yes | 0 |
| AWGN sigma 2 | 41.24 | 0.999243 | 0 | yes | 0 |
| AWGN sigma 3 | 38.17 | 0.998432 | 0 | yes | 6 |

Fixed-step control (non-adaptive, delta = 14, no attack): PSNR 51.99 dB, SSIM 0.999933 —
slightly cleaner image, but no response to local texture.

## What this shows

- An 80-byte payload survives JPEG Q70 and additive noise on **one** cover image.
- The adaptive step keeps PSNR high where the image is smooth.
- Hamming(7,4) corrected 6 bits at sigma 3 and still decoded cleanly.

## What this does **not** show (do not quote it as if it did)

- **Robustness to chat apps.** WhatsApp, Telegram, Signal, email and screenshots recompress
  and resize in ways that this test does not reproduce. This is the open question, and it is
  Phase A of the plan.
- Robustness to resizing, cropping, rotation or print-and-scan.
- Anything about a 128-bit tag: this payload is a plain 80-byte blob, no authentication, no
  handle, no revocation.
- Colour images, DICOM images with a real diagnostic ROI, other textures, other seeds.
- False-accept / false-reject behaviour (never tested: there was nothing to reject).

## Honest note

An earlier run of this same baseline reported PSNR 61.03 dB with claims of "undetectable"
steganalysis and full novelty. Those numbers do not reproduce and the novelty claim had no
prior-art survey behind it. The table above is the version that re-runs.
