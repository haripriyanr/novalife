# G1 — a real scan through modelled chat-app channels (measured, software only)

> **Software reference only.** No board, no FPGA, no real platform send. The chat-app channels are
> **MODELLED** from documented behaviour (long-edge downscale + JPEG re-encode + EXIF strip), not
> measured on a phone. Only `tools/phase_a_platforms/` can measure a real platform, and it needs the
> owner's phone.
>
> One command: `novalife_hub/.venv/bin/python tools/tag_reference/run_real_image.py --image <path>
> [--seeds N] [--label <suffix>]`. Artifacts:
> `real_image_benchmark_2026-10-19_s3_prefix.{md,json}` (before the fix) and
> `real_image_benchmark_2026-10-19_s3_postfix.{md,json}` (after).

## Question

The G1 matrix (`tag_matrix_2026-10-19.md`) reports 50/50 on every resize and re-encode condition —
on **synthetic phantoms**. This run asks the next question: what happens on a real, de-identified
scan, and is the matrix's pass a property of the algorithm or of the covers?

## Image and setup

| | |
|---|---|
| image | a publicly available illustrative cardiac MRI, 500×282 grayscale, supplied by the owner from a web image search (2026-10-19) |
| sha256 | `de20237803f2fe74523f37d31f67f244cca992d5b4b1bd9e3f358490c7df3efd` |
| committed? | no — see `tools/stego_research/covers/README.md`; passed by path and pinned by SHA-256 |
| patient data | none; de-identified, not a hospital record |
| seeds | 3 handles (20261019, 20261119, 20261219); 9 channels each |
| variants | `raw`; `black_lifted_16` (one variable changed: the black level); `normalised_safe_range_16_235` (the recommended intake transform) |

### Capacity: the native scan cannot carry the tag at all

| long edge | shape | LL | universe | ROI blocks | capacity/region | min | fits |
|---|---|---|---|---|---|---|---|
| 282 | 282×158 | 79×141 | 32 | 0.614 | [2, 3, 4, 3] | 2 | no |
| 565 | 564×318 | 159×282 | 153 | 0.484 | [22, 20, 16, 19] | 16 | no |
| 848 | 848×478 | 239×424 | 364 | 0.416 | [52, 55, 48, 56] | 48 | no |
| 1130 | 1130×636 | 318×565 | 665 | 0.368 | [115, 115, 91, 106] | 91 | no |
| 1600 | 1600×902 | 451×800 | 1 400 | 0.313 | [239, 246, 219, 258] | 219 | no |
| 1800 | 1800×1014 | 507×900 | 1 736 | 0.302 | [312, 319, 270, 312] | 270 | **yes** |
| 2048 | 2048×1154 | 577×1024 | 2 304 | 0.284 | [414, 418, 385, 438] | 385 | **yes** |

(`ROI blocks` is the fraction of the universe the ROI taints.) Minimum viable long edge on this scan:
**1800 px**. The benchmark marks at 2048×1154. The payload is 4 regions × 256 eligible LL blocks (one
per codeword bit) and the pilot grid removes roughly half the universe.

## Finding 1 — on the raw scan, every re-encode fails

`raw`: the scan as delivered. ROI 16.8% of pixels; 414/418/385/438 eligible blocks per region;
lossless round trip passes. Marking cost PSNR **30.19 dB**, SSIM **0.63**.

| condition | what it is | tag PASS | exact 128-bit | mean region BER | QR |
|---|---|---|---|---|---|
| `none` | lossless, control | **3/3** | 3/3 | 0.051 | 3/3 |
| `chat_standard_1600_q75` | downscale to 1600 + JPEG q75 | **0/3** | 0/3 | **0.519** | 3/3 |
| `chat_hd_1600_q90` | downscale to 1600 + JPEG q90 | **0/3** | 0/3 | **0.523** | 3/3 |
| `chat_small_1280_q85` | downscale to 1280 + JPEG q85 | **0/3** | 0/3 | **0.531** | 3/3 |
| `jpeg_q50` | JPEG q50 | **0/3** | 0/3 | **0.530** | 3/3 |
| `jpeg_q40` | JPEG q40 | **0/3** | 0/3 | **0.532** | 3/3 |
| `screenshot_like` | resize 0.75 + JPEG q80 | **0/3** | 0/3 | **0.533** | 3/3 |
| `awgn_sigma2` | additive Gaussian noise σ = 2 | **0/3** | 0/3 | **0.532** | 3/3 |
| `crop_corner_25` | 25% corner crop | **0/3** | 0/3 | **0.531** | 3/3 |

The control passes; **every** attack fails at a hard BER near 0.53 — worse than a coin flip, and the
same in all four regions. The visible QR decodes 3/3 on every row, including the crop.

## Finding 2 — the cause, isolated with one variable

**`clipping` diagnostic: 964 / 1024 placement blocks (94.1%) touch a pixel clipped at 0 or 255.**
Median support pixel minimum 0, median support mean 1. The ROI mask pushes the mark into the MRI's
black margin, where the blocks are flat and sit on the 0 clip: the uint8 reconstruction clips the
write and the first codec makes the block a constant, so all four regions read the same bit.

Domain clipping is not fatal on its own — a block sitting at 16 behaves fine. The killer is
*clipping at the boundary*.

**`black_lifted_16`: the same image with the black level moved 0 → 16, nothing else.**

| condition | tag PASS | exact 128-bit | mean region BER | QR |
|---|---|---|---|---|
| `none` | **3/3** | 3/3 | 0.048 | 3/3 |
| `jpeg_q50` | **3/3** | 3/3 | 0.076 | 3/3 |
| `chat_small_1280_q85` | **3/3** | 3/3 | 0.177 | 3/3 |
| `screenshot_like` | **3/3** | 3/3 | 0.055 | 3/3 |
| `awgn_sigma2` | **3/3** | 3/3 | 0.076 | 3/3 |
| `jpeg_q40` | **2/3** | 2/3 | 0.237 | 3/3 |
| `chat_standard_1600_q75` | 0/3 | 0/3 | 0.515 | 3/3 |
| `chat_hd_1600_q90` | 0/3 | 0/3 | 0.517 | 3/3 |
| `crop_corner_25` | 0/3 | 0/3 | 0.531 | 3/3 |

Clipping diagnostic: **0 / 1024** blocks (0.0%). Marking cost PSNR 30.20 dB, SSIM 0.81.

That is the causal experiment: one variable changed, **four** channels flip from 0/3 to 3/3 (JPEG
q50, the 1280 downscale, screenshot-like, AWGN) and a fifth (q40) reaches 2/3, while BER falls from
~0.52 to the lossless level (0.05–0.19). The phantom never exposed it because
`embed.make_cover` textures its margin deliberately ("so the embeddable area is not flat") and puts
it at 22, not 0. **The 50/50 rows of the G1 matrix are a property of the covers as much as of the
algorithm.**

## Finding 3 — the product answer is intake normalisation, not a transform change

`normalised_safe_range_16_235`: the scan mapped onto [16, 235], i.e. head-room at *both* clipping
boundaries. ROI 17.0% of pixels; capacity [411, 418, 383, 437]; clipping diagnostic **0/1024**;
marking cost PSNR **30.20 dB**, SSIM **0.81**; ROI change **0**; false accept 0/3.

| condition | tag PASS | exact 128-bit | mean region BER | QR |
|---|---|---|---|---|
| `none` | **3/3** | 3/3 | 0.055 | 3/3 |
| `chat_small_1280_q85` | **3/3** | 3/3 | 0.190 | 3/3 |
| `jpeg_q50` | **3/3** | 3/3 | 0.092 | 3/3 |
| `screenshot_like` | **3/3** | 3/3 | 0.071 | 3/3 |
| `awgn_sigma2` | **3/3** | 3/3 | 0.106 | 3/3 |
| `jpeg_q40` | **2/3** | 2/3 | 0.243 | 3/3 |
| `chat_standard_1600_q75` | 0/3 | 0/3 | — | 3/3 |
| `chat_hd_1600_q90` | 0/3 | 0/3 | 0.517 | 3/3 |
| `crop_corner_25` | 0/3 | 0/3 | — | 3/3 |

So mapping the amplitude into a safe range — something a DICOM→display pipeline does anyway — turns
the clipped scan into a markable one with the **same** channel profile as the black-lifted diagnostic
variant. That is the transform the gateway should apply to the non-diagnostic area at intake. It is
**not** implemented in the gateway yet.

## Finding 4 — the fixes, and the proof that the matrix is untouched

### 4.1 The silent failure (fixed)

`embed.mark` used to accept a clipped input and emit a tag that cannot survive one re-encode. It now:

- taints **clipped blocks alongside the ROI** (`embed.clipped_blocks` + `embed.blocked_blocks`,
  `CLIP_MARGIN = 1`), in *both* the encoder and the decoder, so a frame with clean area is marked in
  the clean area instead of a clipped margin; and
- **refuses loudly** when a region cannot be filled, naming which taint is responsible (verbatim from
  the `postfix` run):

```
cannot place 256 blocks in every region: available [36, 40, 23, 5]; ignoring the ROI taint
[137, 130, 174, 99], ignoring the clipping taint [414, 418, 385, 438].  If the clipping counts
are the low ones, the image's non-diagnostic area sits on a uint8 clipping level (a clipped
black margin is the common case) and the fix is to normalise the amplitude at intake, not to
change the transform.  Otherwise grow the cover, shrink the ROI clearance, or widen the pilot
interval.  CLIP_RULE records the measurement.
```

The taint is deliberately computed from the **pixels**, not the LL band: clipping is stable under a
re-encode or a downscale (a black region stays black), whereas an LL-domain test drifts with the
codec. Verified: on the decoder side, over a downscale + JPEG copy of a normalised scan, the taint
flags **0** blocks (i.e. it does not disagree with the encoder).

A permanent regression check now lives in `embed.py`'s self-test (`clipping_test`): it asserts that
the clipping taint adds nothing on the phantom (so no phantom measurement can change), that a
deliberately clipped cover is flagged (6345 blocks on the phantom-with-a-black-margin), and that
`mark` refuses it and names clipping. `python tools/tag_reference/embed.py` fails loudly if the
silent-failure behaviour ever returns.

### 4.2 The G1 matrix does not change — proven, not assumed

`blocked_blocks` is identical to `roi_masks` on every phantom cover (the 14 phantom blocks that
touch a clip are all already ROI-tainted), so the placement, the marked image and the extraction are
bit-identical. Measured against the previous revision (`73ad203`), 5 covers × 3 handles:

- masks identical: **5/5 covers**
- capacity identical: `[371, 374, 368, 370]` on all 5
- marked-image SHA-256 identical: **15/15**
- lossless region BER identical: **15/15**
- tag verdict identical: **15/15 (all PASS)**

So `tag_matrix_2026-10-19.{md,json}` stands as recorded; a re-run would only reproduce it.

### 4.3 `local_std` divide-by-zero (fixed, no behaviour change)

`embed.local_std` returned `0.0` while emitting a numpy `divide by zero encountered in scalar
floor_divide` for any block coordinate outside `ll` — which happens on **every downscale channel**,
because placements come from the declared geometry while the received LL is smaller. The silent
fallback drops that block's step to its floor `QIM_BASE_DELTA`. Both the caller and the frozen
`perceptual_mask.compute_dsp48_variance` contract now handle an empty window explicitly and return
0.0 without a warning; no vector changes (all 31 mask vectors are non-empty and still bit-exact).

## State after the fix (the `postfix` run)

Same command, same image, same seeds, `--label postfix`, on the fixed reference:

| variant | before (`prefix`) | after (`postfix`) |
|---|---|---|
| `raw` | marked silently; **0/3 on all 8 attacks**, BER ≈ 0.53 | **refused**, with the reason and the responsible taint named |
| `black_lifted_16` | 5/9 channels | **5/9 channels, identical** (BER 0.048 control, q50 0.076, q40 2/3) |
| `normalised_safe_range_16_235` | (not run) | **marked: 5/9 channels**, 0/1024 clipped |

The `raw` refusal now also reports the cover-level clipping count (1764/2304 blocks = 76.6% of the
whole universe). No number for the markable variants changed, which is the expected consequence of
the taint being a no-op unless the image is actually clipped.

Note that **both** markable variants still fail the 1600-long-edge downscale pair while the *more
aggressive* 1280 downscale passes. That is the geometry defect below, not a damage limit, and it is
independent of the clipping finding.

## Open defects (recorded, not hidden)

1. **Clipped input needs a product-level fix.** The reference now refuses it; nothing in the gateway
   performs the intake normalisation yet. Until it does, the hub cannot mark a scan whose margin is
   clipped — which is the common case for an exported/cropped scan.
2. **The 1600-downscale pair fails even after the black lift, while the more aggressive 1280
   downscale passes.** That is a geometry-search defect, not a damage limit, and it is
   **pre-existing** (identical with the ROI-only taint of the previous revision, verified by
   monkeypatch). Evidence from `recover(..., verbose=True)` on the normalised scan:
   - the coarse candidate score is degenerate — `declared geometry (no offset)` scores
     **agreement 0.000** while every wrong candidate at scale 1.558 scores **1.000**;
   - the pilot locks onto a period of **25.0** LL coefficients instead of 16 (25/16 = 1.558), so all
     pilot-derived candidates are nonsense;
   - the correct candidate then dies inside `read_regions` at
     `region 0: ran out of blocks while placing bit 206` — the decoder's own ROI taint is degenerate
     on that copy, i.e. it taints almost every block of region 0.
   Not diagnosed further. It is the next task.
3. **Crop** — unchanged: the pilot grid is periodic, so a crop can be detected but not located. See
   the matrix document.

## Provenance

- software reference, Python; no board, no FPGA, no real platform send
- before: reference revision `73ad203`; after: see each artifact's `reference_revision` field
- environment recorded in the artifact (`python`, `numpy`, `pillow`, `segno`, `pyzbar`)
- threshold policy: the pass/fail thresholds for the official G1 run are still to be agreed with the
  professor **before** that run; this document reports rates only, and no threshold here was chosen
  after seeing the result
