# RPP-QIM G1 matrix (measured, software only)

Run 2026-10-20T04:32:44+00:00, 665.7 s, Python 3.14.8 with numpy 2.5.3, Pillow 12.3.0, segno 1.6.6 in `novalife_hub/.venv`.

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
| JPEG quality 90 | 50/50 (100%) | 50/50 | 50/50 (100%) | 47.599 | 0.9928 |
| JPEG quality 70 | 50/50 (100%) | 50/50 | 50/50 (100%) | 41.381 | 0.9875 |
| JPEG quality 50 | 50/50 (100%) | 50/50 | 50/50 (100%) | 39.2381 | 0.9842 |
| JPEG quality 40 | 50/50 (100%) | 50/50 | 50/50 (100%) | 38.3327 | 0.9828 |
| resize to 0.50x | 50/50 (100%) | 50/50 | 50/50 (100%) | 51.3106 | 0.9981 |
| resize to 0.75x | 50/50 (100%) | 50/50 | 50/50 (100%) | 52.9543 | 0.9993 |
| resize to 1.50x | 50/50 (100%) | 50/50 | 50/50 (100%) | 52.0209 | 0.9987 |
| resize to 2.00x | 50/50 (100%) | 50/50 | 50/50 (100%) | 52.0252 | 0.9988 |
| screenshot-like: resize 0.75x then JPEG Q80 | 50/50 (100%) | 50/50 | 50/50 (100%) | 43.2654 | 0.9895 |
| crop 25% off the top and left | 50/50 (100%) | 50/50 | 50/50 (100%) | 10.0199 | 0.7015 |
| AWGN sigma 2 | 50/50 (100%) | 50/50 | 50/50 (100%) | 42.017 | 0.9408 |

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

