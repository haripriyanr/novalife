# Platform damage: fixture_colour_resized

Measured 2026-10-11T10:21:49+00:00 by `report_damage.py`. Every number below is measured from the two files listed; the only estimated value is the JPEG quality factor, and it is labelled as an estimate.

| Field | Value |
|---|---|
| original | tools/phase_a_platforms/test_images/synthetic_chest_1024_master.jpg |
| original sha256 | `f08aa33348ac913dc6fe208acd66e8e08c2b891c491fd709b8fe33968f77fe3b` |
| received | tools/phase_a_platforms/verification/fixture_colour_resized.jpg |
| received sha256 | `bfec8c193cf07554f834bc30ef709aebf0d06dbbd5a873c8dc5dcb11858db71a` |
| byte-identical | False |
| original size | 1024x1024 px, aspect 1.0, JPEG |
| received size | 1600x1600 px, aspect 1.0, JPEG |
| scale factor x | 1.5625 |
| scale factor y | 1.5625 |
| uniform scale | True |
| pixel ratio | 2.441406 |

## JPEG structure

- **original**: baseline_dct (not progressive), subsampling 4:4:4 (single component, grayscale), estimated quality 92.0 (estimated, method annex_k_luma_scale_match, matched luma table)
  - quant table 0:
       3    2    2    3    4    6    8   10
       2    2    2    3    4    9   10    9
       2    2    3    4    6    9   11    9
       2    3    4    5    8   14   13   10
       3    4    6    9   11   17   16   12
       4    6    9   10   13   17   18   15
       8   10   12   14   16   19   19   16
      12   15   15   16   18   16   16   16
- **received**: baseline_dct (not progressive), subsampling 4:2:0, estimated quality 71.9 (estimated, method annex_k_luma_scale_match, matched luma table)
  - quant table 0:
       9    6    6    9   13   22   29   34
       7    7    8   11   15   32   34   31
       8    7    9   13   22   32   39   31
       8   10   12   16   29   49   45   35
      10   12   21   31   38   61   58   43
      13   20   31   36   45   58   63   52
      27   36   44   49   58   68   67   57
      40   52   53   55   63   56   58   55
  - quant table 1:
      10   10   13   26   55   55   55   55
      10   12   15   37   55   55   55   55
      13   15   31   55   55   55   55   55
      26   37   55   55   55   55   55   55
      55   55   55   55   55   55   55   55
      55   55   55   55   55   55   55   55
      55   55   55   55   55   55   55   55
      55   55   55   55   55   55   55   55

## Metadata

- EXIF present in original: True; in received: False
- EXIF tag count: 8 -> 0
- tags present in the original but stripped by the platform: ['Artist', 'Copyright', 'DateTime', 'ImageDescription', 'Make', 'Model', 'Orientation', 'Software']
- tags present in the received copy but not in the original (added): none
- tags in original: ImageDescription, Make, Model, Orientation, Software, DateTime, Artist, Copyright
- orientation: 1 -> None (None)
- identifying tags: in original ['ImageDescription', 'Artist', 'Copyright', 'Software', 'Make', 'Model', 'DateTime']; surviving none; stripped ['ImageDescription', 'Artist', 'Copyright', 'Software', 'Make', 'Model', 'DateTime']
- XMP: False; ICC: False; COM segments: 0

## Pixel domain

- comparison basis: original resampled to the received geometry with PIL BICUBIC
- PSNR: 41.7681 dB
- SSIM: 0.951537 (8x8 uniform box window)
- RMSE: 2.0803 levels; max abs diff: 14 levels
- fraction of pixels changed: 0.718902
- per channel (R/G/B) PSNR dB: 41.7681 / 41.7681 / 41.7681
- PSNR over all channels: 41.7681 dB
- per-channel numbers exist because 4:2:0 subsampling destroys the chroma channels and leaves the luma looking almost intact

## Coefficient domain

- 8x8 block DCT-II, orthonormal, level shift -128 (JPEG YCbCr convention)
- band definitions: {'dc': 'zigzag 0..0', 'low': 'zigzag 1..9', 'mid': 'zigzag 10..26', 'high': 'zigzag 27..63'}

| Band | coefs/block | mean\|orig\| | mean\|change\| | change as % of original |
|---|---|---|---|---|
| dc | 1 | 716.8278 | 2.0628 | 0.29% |
| low | 9 | 4.9924 | 1.7123 | 34.3% |
| mid | 17 | 2.6387 | 2.2286 | 84.46% |
| high | 37 | 0.8244 | 0.8623 | 104.59% |

- blocks compared: 40000
- control: both measured at the original grid, so they are comparable: 'resize only' is the original downsampled to the received geometry and resampled back up with PIL BICUBIC, never re-encoded; 'platform' is the received copy upscaled back to the original geometry. The gap between them is what the re-encode added on top of the resize
  - resize only:
    - dc: mean abs change 0.4395 (0.06% of the band's original magnitude)
    - low: mean abs change 0.5219 (10.5% of the band's original magnitude)
    - mid: mean abs change 0.7521 (28.78% of the band's original magnitude)
    - high: mean abs change 0.7841 (63.65% of the band's original magnitude)
  - platform (received, upscaled back):
    - dc: mean abs change 1.2457 (0.17% of the band's original magnitude)
    - low: mean abs change 1.1787 (23.72% of the band's original magnitude)
    - mid: mean abs change 1.4045 (53.74% of the band's original magnitude)
    - high: mean abs change 1.4432 (117.15% of the band's original magnitude)

## What this says for the mark

- the platform changed the geometry from 1024x1024 -> 1600x1600 (uniform scale 1.5625)
- the mid band, where the algorithm embeds, changed by 84.46% of its original magnitude
- the high band changed by 104.59%

Limitations: the resampler used for alignment is PIL BICUBIC; the platform's own resampler is unknown, so the coefficient numbers include any resampling difference as well as re-encoding. The quality factor is an Annex K match, not a value read from the file.
