# Platform damage: fixture_screenshot

Measured 2026-10-11T10:22:44+00:00 by `report_damage.py`. Every number below is measured from the two files listed; the only estimated value is the JPEG quality factor, and it is labelled as an estimate.

| Field | Value |
|---|---|
| original | tools/phase_a_platforms/verification/fixture_screenshot.png |
| original sha256 | `4369742acfebc883b5a0bd87e46783ed176bfb04efe671296b2373cebdad5a36` |
| received | tools/phase_a_platforms/verification/fixture_screenshot.png |
| received sha256 | `4369742acfebc883b5a0bd87e46783ed176bfb04efe671296b2373cebdad5a36` |
| byte-identical | True |
| original size | 1024x1024 px, aspect 1.0, PNG |
| received size | 1024x1024 px, aspect 1.0, PNG |
| scale factor x | 1.0 |
| scale factor y | 1.0 |
| uniform scale | True |
| pixel ratio | 1.0 |

## JPEG structure

- **original**: not a JPEG (PNG)
- **received**: not a JPEG (PNG)

## Metadata

- EXIF present in original: False; in received: False
- EXIF tag count: 0 -> 0
- tags present in the original but stripped by the platform: none
- tags present in the received copy but not in the original (added): none
- orientation: None -> None (None)
- identifying tags: in original none; surviving none; stripped none
- XMP: None; ICC: None; COM segments: 0

## Pixel domain

- comparison basis: same geometry; direct comparison, no resampling
- PSNR: None dB
- SSIM: 1.0 (8x8 uniform box window)
- RMSE: 0.0 levels; max abs diff: 0 levels
- fraction of pixels changed: 0.0

## Coefficient domain

- 8x8 block DCT-II, orthonormal, level shift -128 (JPEG YCbCr convention)
- band definitions: {'dc': 'zigzag 0..0', 'low': 'zigzag 1..9', 'mid': 'zigzag 10..26', 'high': 'zigzag 27..63'}

| Band | coefs/block | mean\|orig\| | mean\|change\| | change as % of original |
|---|---|---|---|---|
| dc | 1 | 716.6777 | 0.0 | 0.0% |
| low | 9 | 4.9686 | 0.0 | 0.0% |
| mid | 17 | 2.6135 | 0.0 | 0.0% |
| high | 37 | 1.2319 | 0.0 | 0.0% |

- blocks compared: 16384
- control: geometry is unchanged, so there is nothing to separate: the received copy was compared directly on the original grid

## What this says for the mark

- the platform changed the geometry from none (uniform scale 1.0)
- the mid band, where the algorithm embeds, changed by 0.0% of its original magnitude
- the high band changed by 0.0%

Limitations: the resampler used for alignment is none; the platform's own resampler is unknown, so the coefficient numbers include any resampling difference as well as re-encoding. The quality factor is an Annex K match, not a value read from the file.
