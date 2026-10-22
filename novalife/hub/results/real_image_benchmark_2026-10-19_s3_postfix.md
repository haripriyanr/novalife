# Real-image benchmark — a real cardiac MRI through chat-app-shaped channels

*Generated 2026-10-19T13:42:33+00:00 in 299.8 s. Schema `novalife/real_image_benchmark/v2`; reference `73ad203` (working tree dirty).*

> **Software reference only.** No board, no FPGA, no real platform send. The chat-app
> channels are **MODELLED** from documented behaviour, not measured on a phone.

## Headline

- The native scan (500x282) **cannot
  carry the tag at all**: a few eligible LL blocks per region against 256 required. It is marked here at 
  **2048x1154** (minimum viable long edge on this scan: **1800 px**).
- **`raw`: the reference REFUSES to mark it.**
  **clipping diagnostic**: 1764/2304 blocks (76.6%) touch a pixel clipped at 0 or 255 (cover-level count over the whole universe; no placements exist because marking was refused)
  Reason recorded by `embed.mark`: *cannot place 256 blocks in every region: available [36, 40, 23, 5]; ignoring the ROI taint [137, 130, 174, 99], ignoring the clipping taint [414, 418, 385, 438].  If the clipping counts are the low ones, the image's non-diagnostic area sits on a uint8 clipping level (a clipped black margin is the common case) and the fix is to normalise the amplitude at intake, not to change the transform.  Otherwise grow the cover, shrink the ROI clearance, or widen the pilot interval.  CLIP_RULE records the measurement.*
- **`black_lifted_16`: marked, and the tag survives 5/9
  channels** (lossless control passes at region BER [0.046875, 0.0390625, 0.09375, 0.01171875]). Fails: `chat_standard_1600_q75`, `chat_hd_1600_q90`, `jpeg_q40`, `crop_corner_25`.
- **`normalised_safe_range_16_235`: marked, and the tag survives 5/9
  channels** (lossless control passes at region BER [0.0625, 0.05078125, 0.09375, 0.01171875]). Fails: `chat_standard_1600_q75`, `chat_hd_1600_q90`, `jpeg_q40`, `crop_corner_25`.

The phantom covers never caught the clipping failure because `embed.make_cover` puts
deliberate texture in its margin ("so the embeddable area is not flat") and its margin
sits at 22, not 0. That is a property of the test image, not of the algorithm.

## The image

- path `/tmp/opencode/brave_scan.jpg` (not committed; see `tools/stego_research/covers/README.md`)
- sha256 `de20237803f2fe74523f37d31f67f244cca992d5b4b1bd9e3f358490c7df3efd`
- a publicly available illustrative cardiac MRI, supplied by the owner from a web image search (2026-10-19). De-identified, not a hospital record, no patient data. NOT committed to the repo -- see tools/stego_research/covers/README.md; passed by path and pinned by SHA-256 so the run is comparable.

## Capacity study — why the size had to change

Payload: 4 regions x **256** eligible LL
blocks (one per codeword bit); the pilot grid every 16 LL
coefficients removes roughly half the universe.

| long edge | shape | LL | universe | ROI blocks | capacity/region | min | fits |
|---|---|---|---|---|---|---|---|
| 282 | 282x158 | 79x141 | 32 | 0.614 | [2, 3, 4, 3] | 2 | no |
| 565 | 564x318 | 159x282 | 153 | 0.484 | [22, 20, 16, 19] | 16 | no |
| 848 | 848x478 | 239x424 | 364 | 0.416 | [52, 55, 48, 56] | 48 | no |
| 1130 | 1130x636 | 318x565 | 665 | 0.368 | [115, 115, 91, 106] | 91 | no |
| 1600 | 1600x902 | 451x800 | 1400 | 0.313 | [239, 246, 219, 258] | 219 | no |
| 1800 | 1800x1014 | 507x900 | 1736 | 0.302 | [312, 319, 270, 312] | 270 | **yes** |
| 2048 | 2048x1154 | 577x1024 | 2304 | 0.284 | [414, 418, 385, 438] | 385 | **yes** |

## The variants

### `raw` — the scan as delivered; large areas of the margin are clipped at 0

**`embed.mark` refused this input.** It will not emit a tag it cannot prove
survives a single re-encode:

```
cannot place 256 blocks in every region: available [36, 40, 23, 5]; ignoring the ROI taint [137, 130, 174, 99], ignoring the clipping taint [414, 418, 385, 438].  If the clipping counts are the low ones, the image's non-diagnostic area sits on a uint8 clipping level (a clipped black margin is the common case) and the fix is to normalise the amplitude at intake, not to change the transform.  Otherwise grow the cover, shrink the ROI clearance, or widen the pilot interval.  CLIP_RULE records the measurement.
```

- marked at 2048x1154; the algorithm ROI is 16.8% of pixels
- **clipping diagnostic**: 1764/2304 blocks (76.6%) touch a pixel clipped at 0 or 255 (cover-level count over the whole universe; no placements exist because marking was refused)
- no channels were run: there is no marked image to attack

### `black_lifted_16` — identical image with the black level lifted by 16 (no clipping at 0)

- marked at 2048x1154; the algorithm ROI is 17.0% of pixels; eligible blocks per region [411, 418, 383, 437] against 256 needed
- lossless round trip: tag OK [True, True, True], region BER [0.046875, 0.0390625, 0.09375, 0.01171875]
- **clipping diagnostic**: 0/1024 blocks (0.0%) touch a pixel clipped at 0 or 255; 0 (0.0%) are essentially flat; median support pixel min 16, median support mean 17 (a flat block at the clipping level (pixel min 0 or max 255, range <= 1) cannot hold the mark through a re-encode: the codec makes it a constant)
- marking cost: PSNR **30.198 dB**, SSIM **0.806**
- ROI: max change inside the algorithm ROI over 3 marks = **0** (zero everywhere); pixel-support violations 0
- false accept with the wrong key: 0 PASS in 3 attempts

| condition | what it is | tag PASS | exact 128-bit | mean PSNR | mean SSIM | mean region BER | QR |
|---|---|---|---|---|---|---|---|
| `none` | the control | **3/3** | 3/3 | None | 1.0 | 0.0475 | 3/3 |
| `chat_standard_1600_q75` | the common case | **0/3** | 0/3 | 45.866 | 0.9888 | 0.515 | 3/3 |
| `chat_hd_1600_q90` | same size cap, higher quality | **0/3** | 0/3 | 49.8397 | 0.9953 | 0.5166 | 3/3 |
| `chat_small_1280_q85` | a smaller delivery profile | **3/3** | 3/3 | 39.3257 | 0.9681 | 0.1774 | 3/3 |
| `jpeg_q50` | requantisation, same geometry | **3/3** | 3/3 | 43.3813 | 0.9774 | 0.0755 | 3/3 |
| `jpeg_q40` | aggressive requantisation | **2/3** | 2/3 | 42.334 | 0.9704 | 0.2367 | 3/3 |
| `screenshot_like` | resample and re-encode together | **3/3** | 3/3 | 45.9113 | 0.9872 | 0.0547 | 3/3 |
| `awgn_sigma2` | pixel-domain noise | **3/3** | 3/3 | 42.021 | 0.9603 | 0.0755 | 3/3 |
| `crop_corner_25` | the open case: a periodic grid cannot locate a crop | **0/3** | 0/3 | 11.597 | 0.4076 | 0.5313 | 3/3 |

### `normalised_safe_range_16_235` — the scan mapped onto [16,235] -- the intake normalisation this benchmark recommends, with head-room at both clipping boundaries

- marked at 2048x1154; the algorithm ROI is 17.0% of pixels; eligible blocks per region [411, 418, 383, 437] against 256 needed
- lossless round trip: tag OK [True, True, True], region BER [0.0625, 0.05078125, 0.09375, 0.01171875]
- **clipping diagnostic**: 0/1024 blocks (0.0%) touch a pixel clipped at 0 or 255; 0 (0.0%) are essentially flat; median support pixel min 16, median support mean 17 (a flat block at the clipping level (pixel min 0 or max 255, range <= 1) cannot hold the mark through a re-encode: the codec makes it a constant)
- marking cost: PSNR **30.198 dB**, SSIM **0.8051**
- ROI: max change inside the algorithm ROI over 3 marks = **0** (zero everywhere); pixel-support violations 0
- false accept with the wrong key: 0 PASS in 3 attempts

| condition | what it is | tag PASS | exact 128-bit | mean PSNR | mean SSIM | mean region BER | QR |
|---|---|---|---|---|---|---|---|
| `none` | the control | **3/3** | 3/3 | None | 1.0 | 0.0553 | 3/3 |
| `chat_standard_1600_q75` | the common case | **0/3** | 0/3 | 45.926 | 0.9886 | None | 3/3 |
| `chat_hd_1600_q90` | same size cap, higher quality | **0/3** | 0/3 | 49.859 | 0.9952 | 0.5173 | 3/3 |
| `chat_small_1280_q85` | a smaller delivery profile | **3/3** | 3/3 | 39.7933 | 0.968 | 0.1895 | 3/3 |
| `jpeg_q50` | requantisation, same geometry | **3/3** | 3/3 | 43.428 | 0.9772 | 0.0921 | 3/3 |
| `jpeg_q40` | aggressive requantisation | **2/3** | 2/3 | 42.3927 | 0.9701 | 0.2425 | 3/3 |
| `screenshot_like` | resample and re-encode together | **3/3** | 3/3 | 45.9687 | 0.987 | 0.0713 | 3/3 |
| `awgn_sigma2` | pixel-domain noise | **3/3** | 3/3 | 42.016 | 0.9595 | 0.1058 | 3/3 |
| `crop_corner_25` | the open case: a periodic grid cannot locate a crop | **0/3** | 0/3 | 12.9293 | 0.425 | None | 3/3 |

## False accept

- never-marked image: 0 PASS in 2
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

- reference revision `73ad203` (working tree dirty)
- python: `3.14.8`
- numpy: `2.5.3`
- pillow: `12.3.0`
- segno: `1.6.6`
- qr_decoder: `pyzbar + libzbar`
- generation: `novalife_hub/.venv/bin/python tools/tag_reference/run_real_image.py --image <path> [--label <suffix>]`
