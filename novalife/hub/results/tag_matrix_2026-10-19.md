# RPP-QIM G1 matrix (measured, software only)

Run 2026-10-19T09:35:41+00:00, 1302.5 s, Python 3.14.8 with numpy 2.5.3, Pillow 12.3.0, segno 1.6.6 in `novalife_hub/.venv`.

> **Software simulation.** No board, no FPGA, no real platform, no patient data. The
> attacks are applied by Pillow and numpy, not by WhatsApp, Telegram, Signal or a
> screenshot. Phase A measures the real platforms; nothing here substitutes for it.

> **Thresholds are not yet agreed with the professor** (NOT YET AGREED with the professor; this file reports rates and does not declare pass/fail).

## Setup

- **Covers:** 5 procedural phantoms, seeds [7010, 7011, 7012, 7013, 7014] (public/synthetic only).
- **Seeds:** 10 handle/tag seeds per cover (20261011..20261911), so 50 marked copies per condition.
- **Attacks:** 12, `none, jpeg_q90, jpeg_q70, jpeg_q50, jpeg_q40, resize_050, resize_075, resize_150, resize_200, screenshot_like, crop_corner_25, awgn_sigma2`.
- **Visible-QR baseline:** a `segno` QR (error level h, 6 px modules, 4-module quiet zone) stamped in a right margin of the marked export, decoded with `pyzbar`/libzbar after the identical attacks.

## Matrix

| Condition | tag PASS | exact 128 bits | visible QR | mean PSNR dB | mean SSIM |
|---|---|---|---|---|---|
| no attack (lossless round trip) | 50/50 (100%) | 50/50 | 50/50 (100%) | inf | 1.0 |
| JPEG quality 90 | 50/50 (100%) | 50/50 | 50/50 (100%) | 46.585 | 0.9906 |
| JPEG quality 70 | 50/50 (100%) | 50/50 | 50/50 (100%) | 40.468 | 0.9786 |
| JPEG quality 50 | 50/50 (100%) | 50/50 | 50/50 (100%) | 38.2447 | 0.9686 |
| JPEG quality 40 | 39/50 (78%) | 39/50 | 50/50 (100%) | 37.4223 | 0.9617 |
| resize to 0.50x | 50/50 (100%) | 50/50 | 50/50 (100%) | 50.4431 | 0.998 |
| resize to 0.75x | 50/50 (100%) | 50/50 | 50/50 (100%) | 51.2403 | 0.9983 |
| resize to 1.50x | 50/50 (100%) | 50/50 | 50/50 (100%) | 51.1468 | 0.9977 |
| resize to 2.00x | 50/50 (100%) | 50/50 | 50/50 (100%) | 51.1728 | 0.9979 |
| screenshot-like: resize 0.75x then JPEG Q80 | 50/50 (100%) | 50/50 | 50/50 (100%) | 41.8015 | 0.9817 |
| crop 25% off the top and left | 0/50 (0%) | 0/50 | 50/50 (100%) | 10.2168 | 0.4221 |
| AWGN sigma 2 | 50/50 (100%) | 50/50 | 50/50 (100%) | 42.017 | 0.9566 |

`tag PASS` counts a 48-bit Ascon tag that verifies after SCL decode and soft-combine;
`exact 128 bits` counts an exactly recovered block. The two are the same here (a tag
cannot verify on a wrong block at 2^-48), and are reported separately so a partial
recovery can never be read as a pass.

## ROI guarantee

- Zero change inside the drawn diagnostic ROI on **50 marks**: `HOLDS` (max |change| = 0).
- Measured in this software reference, on synthetic phantoms, with the ROI drawn by
  construction. It is not a hardware or real-image measurement.

## False accept

- Theoretical per-attempt probability: **2^-48 = 3.553e-15**; the 48-bit Ascon tag fixes the per-attempt false-accept probability; the stated server rate limit bounds online guesses.
- Wrong key, correct geometry: 0 tag PASS in 50 attempts.
- Never-marked image, correct key: 0 tag PASS in 5 attempts.

## Coverage and limits

- **The synthetic covers are embeddable by construction, and that is a real limit of this
  matrix.** `embed.make_cover` puts deliberate texture in the margin ("so the embeddable area
  is not flat") and its margin sits at pixel level 22, not 0. A real scan whose non-diagnostic
  area is a *clipped* black margin behaves completely differently: on a real cardiac MRI, 94.1%
  of the eligible blocks sat on the 0 clip and **every** re-encode failed with a hard BER of
  ~0.54 in all four regions, while the same image with the black level lifted by 16 passed
  q90/q70/q50. None of the 50/50 rates above cover that case. See
  `results/g1_real_image_2026-10-19.md`. The reference now refuses such an input loudly
  (`embed.clipped_blocks` + the `ValueError` in `embed.mark`) instead of emitting a tag that
  dies at the first re-encode; the taint is provably identical on every phantom, so no number
  in this file changes (the proof is in that document).
- Synthetic phantoms only; not a spread of real modality images.
- No rotation, no colour/JPEG subsampling changes, no multiple re-encodes, no real
  chat-app send, no screenshot from a device.
- Crop is included to be explicit that it fails: the pilot grid is periodic, so a crop
  can be detected but not located. That is a synchronisation limit, not a coding one.
- **JPEG Q40 is the weak row.** When it fails the per-region hard BER sits near 0.5
  (chance) while it sits near 0.2 when it passes -- i.e. requantisation destroyed the QIM
  parity on that copy. It is cover-content and placement dependent (some covers are
  robust at Q40 and some are not), and it is a coding/robustness limit, not geometry:
  raising the QIM step or the ECC budget is the lever, and Q40 is below any chat app's
  setting anyway. Recorded, not hidden.
- The visible QR is placed in a **right-hand margin**, so the `crop 25% top-left` attack
  removes the tag geometry but misses the QR: the QR row above is passing a crop the tag
  cannot survive, and that is a genuine advantage of a visible marker. It is not a
  like-for-like win: a QR is visible, occupies image area, is destroyed by any crop that
  hits its margin, and is trivially forgeable (it carries no authentication), which is
  exactly what the 48-bit tag exists to prevent.
- Pass/fail thresholds are the professor's to set; this file reports rates only.

