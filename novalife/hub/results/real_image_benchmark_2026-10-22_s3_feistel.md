# Real-image benchmark — a real cardiac MRI through chat-app-shaped channels

*Generated 2026-10-22T05:15:52+00:00 in 279.2 s. Schema `novalife/real_image_benchmark/v2`; reference `815d9a1` (working tree dirty).*

> **Software reference only.** No board, no FPGA, no real platform send. The chat-app
> channels are **MODELLED** from documented behaviour, not measured on a phone.

## Headline

- The native scan (500x282) **cannot
  carry the tag at all**: a few eligible LL blocks per region against 256 required. It is marked here at 
  **2048x1154** (minimum viable long edge on this scan: **565 px**).
- **`raw`: marked, and the tag survives 5/9
  channels** (lossless control passes at region BER [0.078125, 0.12109375, 0.19140625, 0.46875]). Fails: `jpeg_q50`, `jpeg_q40`, `awgn_sigma2`, `crop_corner_25`.
- **`black_lifted_16`: marked, and the tag survives 9/9
  channels** (lossless control passes at region BER [0.0, 0.0, 0.0, 0.0]). Every channel passes.
- **`normalised_safe_range_16_235`: marked, and the tag survives 9/9
  channels** (lossless control passes at region BER [0.00390625, 0.0, 0.00390625, 0.00390625]). Every channel passes.

The phantom covers never caught the clipping failure because `embed.make_cover` puts
deliberate texture in its margin ("so the embeddable area is not flat") and its margin
sits at 22, not 0. That is a property of the test image, not of the algorithm.

## The image

- path `/home/user/novalife_covers/brave_scan.jpg` (not committed; see `tools/stego_research/covers/README.md`)
- sha256 `de20237803f2fe74523f37d31f67f244cca992d5b4b1bd9e3f358490c7df3efd`
- a publicly available illustrative cardiac MRI, supplied by the owner from a web image search (2026-10-19). De-identified, not a hospital record, no patient data. NOT committed to the repo -- see tools/stego_research/covers/README.md; passed by path and pinned by SHA-256 so the run is comparable.

## Capacity study — why the size had to change

Payload: 4 regions x **256** eligible LL
blocks (one per codeword bit); the pilot grid every 16 LL
coefficients removes roughly half the universe.

| long edge | shape | LL | universe | ROI blocks | capacity/region | min | fits |
|---|---|---|---|---|---|---|---|
| 282 | 282x158 | 79x141 | 665 | 0.532 | [311, 55, 0, 0] | 0 | no |
| 565 | 564x318 | 159x282 | 2730 | 0.416 | [1595, 1339, 1083, 827] | 827 | **yes** |
| 848 | 848x478 | 239x424 | 6254 | 0.349 | [4070, 3814, 3558, 3302] | 3302 | **yes** |
| 1130 | 1130x636 | 318x565 | 11139 | 0.310 | [7681, 7425, 7169, 6913] | 6913 | **yes** |
| 1600 | 1600x902 | 451x800 | 22400 | 0.275 | [16234, 15978, 15722, 15466] | 15466 | **yes** |
| 1800 | 1800x1014 | 507x900 | 28350 | 0.265 | [20829, 20573, 20317, 20061] | 20061 | **yes** |
| 2048 | 2048x1154 | 577x1024 | 36864 | 0.253 | [27556, 27300, 27044, 26788] | 26788 | **yes** |

## The variants

### `raw` — the scan as delivered; large areas of the margin are clipped at 0

- marked at 2048x1154; the algorithm ROI is 17.0% of pixels; eligible blocks per region [1307, 1051, 795, 539] against 256 needed
- lossless round trip: tag OK [True, True, True], region BER [0.078125, 0.12109375, 0.19140625, 0.46875]
- **clipping diagnostic**: 80/1024 blocks (7.8%) touch a pixel clipped at 0 or 255; 0 (0.0%) are essentially flat; median support pixel min 5, median support mean 12 (a flat block at the clipping level (pixel min 0 or max 255, range <= 1) cannot hold the mark through a re-encode: the codec makes it a constant)
- marking cost: PSNR **58.793 dB**, SSIM **0.9987**
- ROI: max change inside the algorithm ROI over 3 marks = **0** (zero everywhere); pixel-support violations 0
- false accept with the wrong key: 0 PASS in 3 attempts

| condition | what it is | tag PASS | exact 128-bit | mean PSNR | mean SSIM | mean region BER | QR |
|---|---|---|---|---|---|---|---|
| `none` | the control | **3/3** | 3/3 | None | 1.0 | 0.2139 | 3/3 |
| `chat_standard_1600_q75` | the common case | **3/3** | 3/3 | 51.3713 | 0.9957 | 0.2747 | 3/3 |
| `chat_hd_1600_q90` | same size cap, higher quality | **3/3** | 3/3 | 55.0923 | 0.9983 | 0.2415 | 3/3 |
| `chat_small_1280_q85` | a smaller delivery profile | **3/3** | 3/3 | 42.892 | 0.9936 | 0.2731 | 3/3 |
| `jpeg_q50` | requantisation, same geometry | **1/3** | 1/3 | 48.9983 | 0.9889 | 0.3789 | 3/3 |
| `jpeg_q40` | aggressive requantisation | **1/3** | 1/3 | 46.0117 | 0.9155 | 0.39 | 3/3 |
| `screenshot_like` | resample and re-encode together | **3/3** | 3/3 | 51.9653 | 0.9959 | 0.2604 | 3/3 |
| `awgn_sigma2` | pixel-domain noise | **0/3** | 0/3 | 43.759 | 0.9198 | 0.4544 | 3/3 |
| `crop_corner_25` | the open case: a periodic grid cannot locate a crop | **0/3** | 0/3 | 11.331 | 0.4742 | 0.5374 | 3/3 |

### `black_lifted_16` — identical image with the black level lifted by 16 (no clipping at 0)

- marked at 2048x1154; the algorithm ROI is 19.1% of pixels; eligible blocks per region [26447, 26191, 25935, 25679] against 256 needed
- lossless round trip: tag OK [True, True, True], region BER [0.0, 0.0, 0.0, 0.0]
- **clipping diagnostic**: 0/1024 blocks (0.0%) touch a pixel clipped at 0 or 255; 0 (0.0%) are essentially flat; median support pixel min 14, median support mean 16 (a flat block at the clipping level (pixel min 0 or max 255, range <= 1) cannot hold the mark through a re-encode: the codec makes it a constant)
- marking cost: PSNR **59.2913 dB**, SSIM **0.9988**
- ROI: max change inside the algorithm ROI over 3 marks = **0** (zero everywhere); pixel-support violations 0
- false accept with the wrong key: 0 PASS in 3 attempts

| condition | what it is | tag PASS | exact 128-bit | mean PSNR | mean SSIM | mean region BER | QR |
|---|---|---|---|---|---|---|---|
| `none` | the control | **3/3** | 3/3 | None | 1.0 | 0.0 | 3/3 |
| `chat_standard_1600_q75` | the common case | **3/3** | 3/3 | 51.0107 | 0.996 | 0.0752 | 3/3 |
| `chat_hd_1600_q90` | same size cap, higher quality | **3/3** | 3/3 | 54.656 | 0.9981 | 0.0039 | 3/3 |
| `chat_small_1280_q85` | a smaller delivery profile | **3/3** | 3/3 | 42.862 | 0.9943 | 0.0961 | 3/3 |
| `jpeg_q50` | requantisation, same geometry | **3/3** | 3/3 | 48.8783 | 0.9943 | 0.0039 | 3/3 |
| `jpeg_q40` | aggressive requantisation | **3/3** | 3/3 | 47.563 | 0.9928 | 0.0094 | 3/3 |
| `screenshot_like` | resample and re-encode together | **3/3** | 3/3 | 51.603 | 0.9965 | 0.0462 | 3/3 |
| `awgn_sigma2` | pixel-domain noise | **3/3** | 3/3 | 42.021 | 0.9457 | 0.0039 | 3/3 |
| `crop_corner_25` | the open case: a periodic grid cannot locate a crop | **3/3** | 3/3 | 11.348 | 0.6083 | 0.3115 | 3/3 |

### `normalised_safe_range_16_235` — the scan mapped onto [16,235] -- the intake normalisation this benchmark recommends, with head-room at both clipping boundaries

- marked at 2048x1154; the algorithm ROI is 19.4% of pixels; eligible blocks per region [26298, 26042, 25786, 25530] against 256 needed
- lossless round trip: tag OK [True, True, True], region BER [0.00390625, 0.0, 0.00390625, 0.00390625]
- **clipping diagnostic**: 0/1024 blocks (0.0%) touch a pixel clipped at 0 or 255; 0 (0.0%) are essentially flat; median support pixel min 14, median support mean 16 (a flat block at the clipping level (pixel min 0 or max 255, range <= 1) cannot hold the mark through a re-encode: the codec makes it a constant)
- marking cost: PSNR **59.3043 dB**, SSIM **0.9988**
- ROI: max change inside the algorithm ROI over 3 marks = **0** (zero everywhere); pixel-support violations 0
- false accept with the wrong key: 0 PASS in 3 attempts

| condition | what it is | tag PASS | exact 128-bit | mean PSNR | mean SSIM | mean region BER | QR |
|---|---|---|---|---|---|---|---|
| `none` | the control | **3/3** | 3/3 | None | 1.0 | 0.0023 | 3/3 |
| `chat_standard_1600_q75` | the common case | **3/3** | 3/3 | 51.257 | 0.9959 | 0.0772 | 3/3 |
| `chat_hd_1600_q90` | same size cap, higher quality | **3/3** | 3/3 | 54.7597 | 0.998 | 0.0026 | 3/3 |
| `chat_small_1280_q85` | a smaller delivery profile | **3/3** | 3/3 | 44.0203 | 0.9946 | 0.0928 | 3/3 |
| `jpeg_q50` | requantisation, same geometry | **3/3** | 3/3 | 49.092 | 0.9942 | 0.0114 | 3/3 |
| `jpeg_q40` | aggressive requantisation | **3/3** | 3/3 | 47.8153 | 0.9927 | 0.0117 | 3/3 |
| `screenshot_like` | resample and re-encode together | **3/3** | 3/3 | 51.868 | 0.9964 | 0.0485 | 3/3 |
| `awgn_sigma2` | pixel-domain noise | **3/3** | 3/3 | 42.016 | 0.9447 | 0.0072 | 3/3 |
| `crop_corner_25` | the open case: a periodic grid cannot locate a crop | **3/3** | 3/3 | 12.654 | 0.631 | 0.3106 | 3/3 |

## False accept

- never-marked image: 0 PASS in 3
- theoretical per attempt: 2^-48; the stated server rate limit bounds online guessing

## Thresholds

NOT YET AGREED with the professor; this file reports rates and does not declare pass/fail

## What this run does and does not show

- **Does**: measure a real de-identified scan end to end, locate a failure mode the
  synthetic covers hid because they were built to be embeddable, and isolate the cause
  with a one-variable experiment (black level 0 -> 16).
- **Does not**: prove anything about a real WhatsApp/Telegram send. That is Phase A
  (`tools/phase_a_platforms/`), which needs the owner's phone and reports on real files.
- The reference now **refuses** an input it cannot mark survivably (`embed.clipped_blocks`
  plus the loud `ValueError` in `embed.mark`) instead of silently emitting a dead tag. It
  goes further than refusing: clipped blocks are tainted alongside the ROI in *both* the
  encoder and the decoder (`embed.blocked_blocks`), so a frame with enough clean area is
  marked in the clean area rather than in a clipped margin.
- The clipping taint is **bit-identical on every phantom cover** (proven, not assumed:
  same masks, same capacity, same marked-image SHA-256, same BER and the same tag verdict
  against the previous revision), so `results/tag_matrix_2026-10-19.*` still stands.
- The product-side fix for a clipped input is **amplitude normalisation at intake** of the
  non-diagnostic area; the transform itself is unchanged. Not a product change yet.
- The marked render is large; a real chat app's downscale is modelled with Pillow
  LANCZOS, and a phone's encoder is not Pillow.

## Provenance

- reference revision `815d9a1` (working tree dirty)
- python: `3.14.8`
- numpy: `2.5.3`
- pillow: `12.3.0`
- segno: `1.6.6`
- qr_decoder: `pyzbar + libzbar`
- generation: `novalife_hub/.venv/bin/python tools/tag_reference/run_real_image.py --image <path> [--label <suffix>]`
