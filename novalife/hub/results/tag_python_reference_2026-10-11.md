# RPP-QIM Python reference: attack matrix (measured, software only)

Run 2026-10-19T09:06:48+00:00, 9.8 s, Python 3.14.8 with numpy 2.5.3 and Pillow 12.3.0 in `novalife_hub/.venv`.

> **Software simulation.** No board, no FPGA, no real platform, no patient data.
> The cover is a synthetic chest-radiograph-shaped phantom drawn from a fixed seed
> (`tools/tag_reference/embed.py: make_cover`); the ROI is drawn with it, so the
> diagnostic region is exact by construction rather than thresholded. Every attack
> below is applied by this reference, not by WhatsApp, Telegram, Signal or a
> screenshot. Phase A measures the real platforms; nothing here substitutes for it.

## Setup

| | |
|---|---|
| Cover | 1600x1200 synthetic phantom, seed 7010, sha256 `ec015447374acf31...` |
| ROI | 207665 px (10.8% of the frame), drawn phantom ROI (ground truth, exact by construction) for the no-touch check; algorithm ROI = img > mean + 0.2 x std (sims/dicom_loader.py rule) |
| Tag block | version=1 hub_id=0x9a3 handle=0xa998ebac3f8bd66c tag=0x0ec36359c94e |
| Transform | 5/3 lifting, 1 level, tools/stego_research/sims/iwt_lifting.py |
| Pilot grid | G=16 LL coefficients (= 32 px), B=3, amplitude 16 |
| QIM | delta = 16.0 + 0.15 x local_std, 8x8 DCT of the LL band, zigzag 12 |
| Regions | R=4 quadrants x 256 eligible 8x8 blocks (256 codeword bits each) |
| Code | N=256 K=128, SCL L=8, tools/stego_research/sims/polar_codec.py |
| MAC | Ascon-AEAD128 (NIST SP 800-232), truncated 48-bit tag, tools/tag_reference/ascon_primitives.py |
| Marked export | PSNR 29.918 dB, SSIM 0.804207 against the cover; max |change| inside drawn ROI = **0**, inside algorithm ROI = **0** |
| Clean self-check | round-trip tag PASS (exact 128-bit recovery, see `none` row) |

## The matrix

| Condition | scale est. (rows/cols) | true scale | exact 128 bits | tag | PSNR dB | SSIM |
|---|---|---|---|---|---|---|
| no attack (lossless round trip) | 0.9980 / 1.0004 | 1.00 / 1.00 | yes | PASS | None | 1.0 |
| JPEG quality 90 | 0.9980 / 1.0004 | 1.00 / 1.00 | yes | PASS | 46.583 | 0.990645 |
| JPEG quality 70 | 0.9980 / 1.0004 | 1.00 / 1.00 | yes | PASS | 40.466 | 0.978611 |
| JPEG quality 50 | 0.9980 / 1.0004 | 1.00 / 1.00 | yes | PASS | 38.246 | 0.968567 |
| JPEG quality 40 | 0.9980 / 1.0004 | 1.00 / 1.00 | yes | PASS | 37.422 | 0.961641 |
| resize to 0.50x | 0.4990 / 0.5002 | 0.50 / 0.50 | yes | PASS | 50.439 | 0.998037 |
| resize to 1.50x | 1.4970 / 1.5007 | 1.50 / 1.50 | yes | PASS | 51.136 | 0.997644 |
| crop 25% off the top and left | 0.9996 / 1.0042 | 1.00 / 1.00 | no | FAIL | 10.216 | 0.422494 |
| screenshot-like: resize 0.75x then JPEG Q80 | 0.7485 / 0.7503 | 0.75 / 0.75 | yes | PASS | 41.8 | 0.981674 |
| AWGN sigma 2 | 0.9980 / 1.0004 | 1.00 / 1.00 | yes | PASS | 42.017 | 0.956613 |

`scale est.` is what the pilot grid measured on the received image; `true scale` is
what the attack applied. The pilot period is biased low by about 0.2% (the pilot grid
plus the 5/3 IWT); measured on its own that bias is far outside the payload block
tolerance at 0.5x. For a pure resize the scale is therefore taken exactly from the
received/declared size ratio, and the remaining sub-pixel offset is found by a small
exact search in which the 48-bit tag is the only verdict -- the earlier `ECC budget
too small` reading of the resize failure was wrong: with the correct geometry the
payload decodes at BER 0. The pilot is still what handles a crop, where the received
size no longer fixes the scale; crop remains the open case, and that *is* a
synchronisation limit rather than a coding one.

## Per condition

### no attack (lossless round trip) (`none`)

- received 1600x1200 (declared 1600x1200); the control: if this is not exact the reference is broken, not the algorithm
- pilot period rows 15.968, cols 16.007 LL samples (nominal 16); scale 0.9980/1.0004 vs true 1.00/1.00; trusted=True
- grid residual after the scale is undone: [0.0, 0.0] LL rows/cols
- accepted candidate: `identity + fine +0.00/+0.00` (17 coarse candidates ranked)
- region hard BER before decoding: 0.000, 0.000, 0.000, 0.000
- **exact 128-bit recovery: yes**; **tag verdict: PASS**
- PSNR None dB, SSIM 1.0; direct comparison, both images at the declared export geometry

### JPEG quality 90 (`jpeg_q90`)

- received 1600x1200 (declared 1600x1200); grayscale, 4:4:4
- pilot period rows 15.968, cols 16.007 LL samples (nominal 16); scale 0.9980/1.0004 vs true 1.00/1.00; trusted=True
- grid residual after the scale is undone: [0.0, 0.0] LL rows/cols
- accepted candidate: `identity + fine +0.00/+0.00` (17 coarse candidates ranked)
- region hard BER before decoding: 0.000, 0.000, 0.000, 0.000
- **exact 128-bit recovery: yes**; **tag verdict: PASS**
- PSNR 46.583 dB, SSIM 0.990645; direct comparison, both images at the declared export geometry

### JPEG quality 70 (`jpeg_q70`)

- received 1600x1200 (declared 1600x1200); the quality the existing DCT-QIM baseline measured at
- pilot period rows 15.968, cols 16.007 LL samples (nominal 16); scale 0.9980/1.0004 vs true 1.00/1.00; trusted=True
- grid residual after the scale is undone: [0.0, 0.0] LL rows/cols
- accepted candidate: `identity + fine +0.00/+0.00` (17 coarse candidates ranked)
- region hard BER before decoding: 0.004, 0.000, 0.012, 0.012
- **exact 128-bit recovery: yes**; **tag verdict: PASS**
- PSNR 40.466 dB, SSIM 0.978611; direct comparison, both images at the declared export geometry

### JPEG quality 50 (`jpeg_q50`)

- received 1600x1200 (declared 1600x1200); below any platform's setting
- pilot period rows 15.968, cols 16.007 LL samples (nominal 16); scale 0.9980/1.0004 vs true 1.00/1.00; trusted=True
- grid residual after the scale is undone: [0.0, 0.0] LL rows/cols
- accepted candidate: `identity + fine +0.00/+0.00` (17 coarse candidates ranked)
- region hard BER before decoding: 0.144, 0.121, 0.113, 0.332
- **exact 128-bit recovery: yes**; **tag verdict: PASS**
- PSNR 38.246 dB, SSIM 0.968567; direct comparison, both images at the declared export geometry

### JPEG quality 40 (`jpeg_q40`)

- received 1600x1200 (declared 1600x1200); aggressive requantisation
- pilot period rows 15.968, cols 16.007 LL samples (nominal 16); scale 0.9980/1.0004 vs true 1.00/1.00; trusted=True
- grid residual after the scale is undone: [0.0, 0.0] LL rows/cols
- accepted candidate: `identity + fine +0.00/+0.00` (17 coarse candidates ranked)
- region hard BER before decoding: 0.133, 0.160, 0.160, 0.352
- **exact 128-bit recovery: yes**; **tag verdict: PASS**
- PSNR 37.422 dB, SSIM 0.961641; direct comparison, both images at the declared export geometry

### resize to 0.50x (`resize_050`)

- received 800x600 (declared 1600x1200); a real resample, Pillow BICUBIC, both axes
- pilot period rows 7.984, cols 8.004 LL samples (nominal 16); scale 0.4990/0.5002 vs true 0.50/0.50; trusted=True
- grid residual after the scale is undone: [0.6, -0.18] LL rows/cols
- accepted candidate: `rescale recv/decl 0.5000/0.5000 + fine -0.25/-0.25` (18 coarse candidates ranked)
- region hard BER before decoding: 0.016, 0.008, 0.004, 0.004
- **exact 128-bit recovery: yes**; **tag verdict: PASS**
- PSNR 50.439 dB, SSIM 0.998037; marked export resampled to the received geometry with Pillow LANCZOS (1200, 1600)->(600, 800); the resampler's own error is included

### resize to 1.50x (`resize_150`)

- received 2400x1800 (declared 1600x1200); a real resample, Pillow BICUBIC, both axes
- pilot period rows 23.952, cols 24.011 LL samples (nominal 16); scale 1.4970/1.5007 vs true 1.50/1.50; trusted=True
- grid residual after the scale is undone: [1.8, -0.53] LL rows/cols
- accepted candidate: `rescale recv/decl 1.5000/1.5000 + fine -0.25/-0.25` (18 coarse candidates ranked)
- region hard BER before decoding: 0.004, 0.004, 0.000, 0.000
- **exact 128-bit recovery: yes**; **tag verdict: PASS**
- PSNR 51.136 dB, SSIM 0.997644; marked export resampled to the received geometry with Pillow LANCZOS (1200, 1600)->(1800, 2400); the resampler's own error is included

### crop 25% off the top and left (`crop_corner_25`)

- received 1200x900 (declared 1600x1200); keeps the bottom-right 56% of the frame; 25% of each axis removed from one corner
- pilot period rows 15.993, cols 16.067 LL samples (nominal 16); scale 0.9996/1.0042 vs true 1.00/1.00; trusted=True
- grid residual after the scale is undone: [-150.0, -200.0] LL rows/cols
- accepted candidate: `identity` (17 coarse candidates ranked)
- region hard BER before decoding: 
- **exact 128-bit recovery: no**; **tag verdict: FAIL**
- PSNR 10.216 dB, SSIM 0.422494; marked export resampled to the received geometry with Pillow LANCZOS (1200, 1600)->(900, 1200); the resampler's own error is included
- recovery notes: no placement at declared geometry: region 0: ran out of blocks while placing bit 53

### screenshot-like: resize 0.75x then JPEG Q80 (`screenshot_like`)

- received 1200x900 (declared 1600x1200); resample and re-encode together, the worst of the two
- pilot period rows 11.976, cols 12.005 LL samples (nominal 16); scale 0.7485/0.7503 vs true 0.75/0.75; trusted=True
- grid residual after the scale is undone: [0.9, -0.27] LL rows/cols
- accepted candidate: `rescale recv/decl 0.7500/0.7500 + fine -0.25/-0.25` (18 coarse candidates ranked)
- region hard BER before decoding: 0.035, 0.023, 0.023, 0.031
- **exact 128-bit recovery: yes**; **tag verdict: PASS**
- PSNR 41.8 dB, SSIM 0.981674; marked export resampled to the received geometry with Pillow LANCZOS (1200, 1600)->(900, 1200); the resampler's own error is included

### AWGN sigma 2 (`awgn_sigma2`)

- received 1600x1200 (declared 1600x1200); additive white Gaussian noise in the pixel domain
- pilot period rows 15.968, cols 16.007 LL samples (nominal 16); scale 0.9980/1.0004 vs true 1.00/1.00; trusted=True
- grid residual after the scale is undone: [0.0, 0.0] LL rows/cols
- accepted candidate: `identity + fine +0.00/+0.00` (17 coarse candidates ranked)
- region hard BER before decoding: 0.031, 0.012, 0.016, 0.027
- **exact 128-bit recovery: yes**; **tag verdict: PASS**
- PSNR 42.017 dB, SSIM 0.956613; direct comparison, both images at the declared export geometry

## Summary

- exact 128-bit recovery in **9 of 10** conditions; tag verifies in 9.
- what this run does **not** show: real chat-app sends, rotation, colour, other
  covers, other seeds, false-accept behaviour against a *guessed* handle, and
  anything on hardware. All of that is future work and is listed in
  `tools/tag_reference/README.md`.

