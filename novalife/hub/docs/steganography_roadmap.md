# Image-tag roadmap: what we can and cannot claim

> The algorithm itself — the stages, the parameters, the rejected alternatives and the build order —
> is specified in **`algorithm.md`** and is locked in. This file is about claims: what the measured
> evidence supports today, and what it does not.

## The tag, in one line

One polar codeword carries a 128-bit block — `version | hub_id | handle | 48-bit tag` — embedded in
the low-frequency coefficients of the image, outside the diagnostic region, repeated in R regions,
with a pilot grid so the reader can find the coefficients after the image has been resized. The
record stays in the database.

## Where each piece comes from

| Piece | Published prior art |
|---|---|
| QIM | Chen & Wornell, IEEE Trans. Inf. Theory 47(4), 2001 |
| Adaptive step (16 + 0.15 x local std) | Eggers et al. scalar Costa scheme and its follow-ons |
| 5/3 lifting IWT | standard wavelet lifting |
| Polar coding N=256, K=128 | Arikan, IEEE Trans. Inf. Theory 55(7), 2009 |
| 48-bit tag | Ascon, NIST SP 800-232 (Aug 2025) — standard, truncated |
| Pilot-grid scale estimation | Kawano & Kawamura, IEICE Trans. Inf. & Syst., 2024 |
| Log-polar / template resynchronisation | Pereira; Alattar & Meyer |
| Medical ROI/RONI watermarking with an identifier | Coatrieux et al. 2008; DWT-DCT-SVD + BCH/CRC schemes since |

Full table: `tools/stego_research/PRIOR_ART.md`.

## Claims we can make now

- DICOM files carry patient metadata that is lost the moment the image is exported as a JPEG or a
  screenshot. This is obvious from the format and it is not a claim about our work.
- **Measured, in our own software:** the plain DCT-QIM baseline carried an 80-byte payload 512x512
  cover, BER 0 after JPEG Q70 and AWGN sigma 2 **on one cover, one seed**, PSNR 50.78 dB
  (`results/software_baseline_dct_qim.md`). It is a *baseline*, not the tag.
- Ascon is a NIST-standardised lightweight AEAD and hash (SP 800-232).
- Published, independent measurement of this exact problem channel: LSB is deleted by the first
  chat-app re-encode; a transform-domain mark with strong ECC survives recompression; **any
  rescale destroys transform-domain marks**. Source: HarrisonSec, 23 Sep 2026 (simulated platform
  parameters, not verified sends).
- The board can already serve HTTP over the LAN, read and write an SD card and use the full DDR
  (`results/hardware_2026-09-14_to_16.md`).

## Claims we must not make yet

- That our tag survives a real WhatsApp or Telegram send. Nothing has been through one.
- Any recovery rate after resizing, cropping, rotation, screenshotting or print-and-scan.
- Any false-accept or false-reject rate, for the tag or for the perceptual hash.
- Any hardware number: area, Fmax, power, latency, or any speedup.
- Any novelty, for the pointer design, the soft-combining, the pilot-grid synchroniser, or the
  hybrid enclave — until the prior-art survey in `PRIOR_ART.md` is complete.
- That the invisible tag is *undetectable*. Robustness and undetectability are different
  properties; a mark built to survive recompression is more conspicuous, not less. We do not claim
  secrecy of existence, and we do not need it.

## The comparison we owe the professor

| Baseline | What it is | What it will buy us |
|---|---|---|
| DICOM header only | the status quo | the number our tag must beat after the same round trips |
| **Visible QR/barcode in the margin** | build first, a few days | the honest floor: trivially robust, easily cropped out, visible to everyone |
| Our pixel tag | the work | survives crops that keep its regions, invisible, authenticated |

If the pixel tag does not beat the QR on the real channels, the paper says so.

## Plan

| Phase | Work | Output |
|---|---|---|
| A | measure what the real chat apps do; QR baseline; prior-art survey | numbers + baseline + `PRIOR_ART.md` |
| B | the Python reference of `algorithm.md`; the attack matrix; compare with the QR | measured recovery and false-accept tables |
| C | server flow (handles, revoke, rate limit, audit, perceptual hash); app scan screen | end to end in software |
| D | PL cores: pilot-grid scale estimator, tag engine, QIM embedder, soft-combine; bit-exact; then Vivado numbers | testbenches + real reports |
| E | paper and demo, from A-D only | the paper |

Pass/fail thresholds are agreed with the professor **before** the runs.
