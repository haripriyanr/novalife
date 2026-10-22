# Stego research harness

Reproducible **software-only** reference models for the NovaLife tag. Nothing here touches the
board. Numbers produced here belong in `novalife_hub/results/` with a date and a command.

## Layout

```
tools/stego_research/
├── README.md            # this file
├── requirements.txt     # numpy, Pillow
├── PRIOR_ART.md         # what is published, what we may claim
├── covers/README.md     # public test image, no patient data, ever
├── sims/                # the reference models
└── results/             # measured JSON + PNG/JPG outputs
```

Sims that exist:

| File | What it is | State |
|---|---|---|
| `polar_codec.py` | systematic polar encoder N=256 K=128 + SCL decoder L=8 | the encoder is the one the PL core must match |
| ~~`ascon128.py`~~ | was named for Ascon but implemented AES-128-GCM | **removed** → `../../legacy/`; the real Ascon is `../tag_reference/ascon_primitives.py` |
| `iwt_lifting.py` | 5/3 lifting integer wavelet | bit-exact target for `iwt_53_core` |
| `perceptual_mask.py` | local-variance ROI mask | bit-exact target for `perceptual_mask_core` |
| `adaptive_qim.py` | adaptive DWT-QIM embed/extract | software only |
| `dicom_loader.py` | DICOM pixels + ROI extraction | test data |
| `steganalysis.py` | chi-square, SPA, RS, KL | **diagnostics only**; a low KL divergence is not a security claim |

The DCT-QIM baseline experiment lives in `../stego_dct_qim/`.

## Run

```bash
cd novalife_hub
. .venv/bin/activate
python tools/stego_dct_qim/run_experiment.py --cover tools/stego_dct_qim/cover.jpg --out tools/stego_dct_qim
```

The baseline's frozen parameters, cover and seed are recorded in
`novalife_hub/results/software_baseline_dct_qim.md`, so a re-run is comparable.

## What this harness is for

- the Python reference the PL cores must be bit-exact against (rule 5 in `../AGENTS.md`);
- Phase B: the whole tag path — build the 128-bit block, embed outside the ROI, repeat in R
  regions, soft-combine on recovery, polar decode, verify;
- the attack matrix: JPEG qualities, real chat-app round trips, screenshot, resize, crop,
  print-and-scan, noise.

## Honesty bans

Do **not** claim, until measured in a frozen tested decoder:

- a BER tolerance figure for hardware;
- any speedup, acceleration or energy figure;
- novelty of the QIM rule, the adaptive step, or the transform;
- a complete DWT engine or a working RS decoder that does not exist.

Keyed placement is obfuscation, not encryption — the authentication tag stays mandatory.
