# Covers — public sources only (no patient data, ever)

This folder intentionally contains **no cover images** other than the one DICOM test file already
here. Download at run time so the repo stays small and license-clean.

Rules: **public or synthetic images only. Never a real patient image, never a real study.**

## Standard test image (Lenna, 512x512)

```bash
curl -L 'https://upload.wikimedia.org/wikipedia/en/7/7d/Lenna_%28test_image%29.png' -o cover.png
```

## Baseline cover used for the seed-7010 runs

The re-runnable baseline uses the cover already checked in:

```
novalife_hub/tools/stego_dct_qim/cover.jpg   # 512x512 JPEG, sha256 recorded in results/
```

Its hash is written down in `novalife_hub/results/software_baseline_dct_qim.md`, so a re-run is
comparable. The DICOM test file `covers/test_dicom.dcm` is for the loader and the ROI mask.

Do not commit downloaded copies under `covers/`; fetch to a work directory outside the repo if you
need another cover.

## License and provenance note

Lenna has a complicated publication history. Use it only as a reproducible research placeholder.
Any published release must re-run the same scripts on a freely licensed cover (for example
USC-SIPI `4.2.04`) and record the cover SHA-256 in `results/`.
