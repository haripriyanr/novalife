# Tag reference (`tools/tag_reference/`)

Python reference for the locked algorithm (`docs/algorithm.md`, RPP-QIM).
Software simulation only: no board, no FPGA, no real platform, no patient data.

## Files

| File | Stage | What it does |
|---|---|---|
| `ascon_primitives.py` | primitive | Ascon-AEAD128 (NIST SP 800-232), checked against all 1089 official KATs (`vectors/kat/`); was Ascon-128 v1.2 until 2026-10-20, plus the truncated-MAC and keystream derivations. Replaces the AES-GCM proxy formerly at `sims/ascon128.py` (now quarantined in `legacy/`); the PL core `ascon_core` targets this. |
| `tag_block.py` | P2 | 128-bit block: 4b version \| 12b hub_id \| 64b handle \| 48b truncated Ascon MAC. Build, split, verify. |
| `pilot_grid.py` | P1 | Secret-interval QIM grid in the LL band outside the ROI; scale estimate via autocorrelation of projection sums + windowed DFT (Kawano & Kawamura 2024). Carries no payload. |
| `embed.py` | P3+P4 | Full mark path: IWT → mask → pilot → polar encode → Ascon-CTR keyed placement → QIM on 8×8 DCT of the LL band, same 256-bit codeword in R=4 quadrant regions. |
| `extract.py` | recovery | Scale-estimate, undo, soft-combine LLRs across regions, polar SCL decode, verify tag. Deps: numpy + Pillow only. |
| `run_demo.py` | measurement | Attack matrix on one synthetic cover; writes the two results files below. |
| `run_matrix.py` | measurement (G1) | The G1 matrix: ≥5 covers × ≥10 seeds, the resize conditions, ROI-zero, false accept, and the visible-QR baseline. Writes `results/tag_matrix_<date>.{md,json}`. Deps: + `segno` and `pyzbar` (both in the venv). |
| `run_real_image.py` | measurement (G1) | The same channel set against a **real** scan (passed by path, pinned by SHA-256, never committed), plus a capacity study, a clipping diagnostic and the intake-normalisation variants. `embed.mark` refuses an input it cannot mark survivably, and that refusal is reported as a result. Writes `results/real_image_benchmark_<date>[_s<N>][_<label>].{md,json}`. |

Parameters live as constants at the top of each file, taken from
`docs/algorithm.md` section 3 (starting values, not results).

## Run

From the repository root, with the project venv (numpy + Pillow for `run_demo.py`;
numpy + Pillow + `segno` + `pyzbar` for the QR baseline in `run_matrix.py`):

```bash
novalife_hub/.venv/bin/python novalife_hub/tools/tag_reference/run_demo.py
novalife_hub/.venv/bin/python novalife_hub/tools/tag_reference/run_matrix.py   # the G1 matrix
# real-image benchmark; --image is a path outside the repo (see tools/stego_research/covers/README.md)
novalife_hub/.venv/bin/python novalife_hub/tools/tag_reference/run_real_image.py \
    --image /path/to/scan.jpg --seeds 3 --label postfix
```

Self-tests per module (fast except `embed.py`, which marks a full 1600×1200 cover):

```bash
novalife_hub/.venv/bin/python novalife_hub/tools/tag_reference/ascon_primitives.py
novalife_hub/.venv/bin/python novalife_hub/tools/tag_reference/tag_block.py
novalife_hub/.venv/bin/python novalife_hub/tools/tag_reference/pilot_grid.py
novalife_hub/.venv/bin/python novalife_hub/tools/tag_reference/embed.py
novalife_hub/.venv/bin/python novalife_hub/tools/tag_reference/extract.py
```

Outputs:

* `novalife_hub/results/tag_python_reference_2026-10-11_matrix.json` — machine-readable
* `novalife_hub/results/tag_python_reference_2026-10-11.md` — readable report
* `novalife_hub/results/tag_matrix_<date>.json` / `.md` — the G1 matrix from `run_matrix.py`
* `demo_out/` — cover, ROI, marked export, received copies (regenerable scratch, not evidence)

## Reuse, not copies

The reference imports the shared sims rather than reimplementing them:
`iwt_lifting` (5/3 lifting), `perceptual_mask` (DSP48-style variance core),
`polar_codec` (N=256 K=128 + SCL L=8), `dicom_loader` (ROI threshold rule).
`ascon_primitives.py` intentionally does *not* reuse the old `sims/ascon128.py` (now in
`legacy/`: it was an AES-128-GCM proxy despite its name, while the PL core is real Ascon — Ascon-AEAD128, NIST SP 800-232, since 2026-10-20).

## What does not work yet / known limits (measured, not guessed)

> Updated 2026-10-19. `run_matrix.py` (5 covers × 10 seeds) and
> `results/tag_matrix_<date>.md` hold the numbers.

* **Resize now works** (fixed 2026-10-19): exact 128-bit recovery at 0.5x/0.75x/1.5x/2.0x and for
  resize+JPEG. The earlier failure was a *geometry-search* bug, not the ECC budget — with the correct
  scale and offset the payload decodes at BER 0. For a pure resize the scale is taken exactly from the
  received/declared size ratio (the pilot period is biased ~0.2% by the pilot grid + 5/3 IWT), and the
  sub-pixel offset is found by a small exact search in which the 48-bit tag is the only verdict. See
  `extract.py: candidate_maps` (the `rescale recv/decl` priority candidate) and `FINE_PRIOR`.
* **The size-ratio candidate no longer depends on the pilot** (fixed 2026-10-19, real scan): the pilot
  mis-locked by a harmonic (period 24.9 instead of 12.5 in LL, 2x) and, because the crop test used that
  period, the exact size-ratio candidate was never built — so the 2048→1600 downscale failed at q75/q90
  while the harsher 1280→q85 survived. Admitted now on either signal (pilot residual **or** both axis
  ratios agreeing), and priority candidates take their exact slots first. The self-test asserts it with
  a deliberately mis-locked pilot. `results/g1_1600_geometry_2026-10-19.md`.
* **Crop: partly fixed 2026-10-19, and the reason it failed was not the one written here before.** The
  old note ("the grid is periodic, so a crop can be detected but not located") was measured to be false:
  for a pure crop the scale is unchanged and the size is not, so the residual
  `received_ll − declared_ll × scale` **is** the content shift — at ×1.0 for a corner crop and ×0.5 for a
  symmetric one, and both are priority candidates now. Three defects were behind it: one starved region
  aborted the whole read instead of contributing erasures (now LLR 0, and the other regions decide); the
  correct geometry was ranked below grid-equally-good decoys; and `placement_map` was shown taint only the
  decoder had, so a cropped-away area moved which block carried which bit and desynchronised whole regions
  on images whose pixels were restored exactly. Placement taint (ROI ∪ clipping) is now separate from
  erasure taint (undercovered blocks), and the ROI statistics come from covered pixels only. Measured:
  **corner crops 5/10/25/40%, corner 25% + JPEG q75 and symmetric 5% all recover exact 128 bits**;
  **symmetric ≥10% still fails** (every region loses the same border, so no quadrant survives and two
  regions read garbage instead of abstaining — closing it needs placement to be a pure function of
  geometry and key, which changes the embedded output). A crop recovery also costs 95–200 s here.
  `results/g1_crop_2026-10-19.md`.
* The measured harmonic mis-lock above still stands: the pilot is not a working crop locator, and the
  crop locator now uses the residual rather than the period, so crop no longer depends on it.
* Rotation and unequal aspect ratios are not handled (algorithm.md section 4): there is no rotation
  estimator; a rotated copy fails.
* The visible-QR baseline in `run_matrix.py` survives every attack here, including the corner crop the
  tag cannot. That is a real advantage of a visible marker and must be reported as one; the QR is
  nonetheless visible, occupies image area, is destroyed by any crop that hits its margin, and carries
  no authentication (it is forgeable), which is what the 48-bit tag exists to prevent.
* False accept is reported in `run_matrix.py` (wrong key, and never-marked image). The theoretical
  per-attempt rate is 2^-48; the server rate limit bounds online guesses.
* **No real chat-app send has been measured (Phase A).** Lab JPEG/resize/crop/noise only.
* No hardware numbers. Pass/fail thresholds are the professor's to set and are **not yet agreed**.
* Deviations from the locked spec, recorded in the code and needing a written
  owner decision before RTL: R=4 quadrant regions instead of "corners + centre
  band" (`embed.py`); per-axis offsets and independent axis scales returned by
  the pilot in addition to the scale (`pilot_grid.py`, `extract.py`).
