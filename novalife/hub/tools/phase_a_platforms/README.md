# Phase A: measure what the real platforms do to an image

> **Status: harness ready, no platform measured yet.** Everything in
> `verification/` was produced by the self-test against a damage this repository
> created. **No WhatsApp, Telegram, Signal, Instagram or email send has been
> measured.** Fill `results/` from a real phone before any of these numbers is
> quoted anywhere.
>
> **Why this exists:** `docs/algorithm.md` section 7 puts Phase A first — every
> robustness number the project has is from lab conditions (JPEG Q70, AWGN on
> one cover). The pilot grid's budget, the share resolution, and whether exact
> recovery of 128 bits is even possible after a real send all depend on what a
> real platform does to the file. This tool measures that, one platform at a
> time, and nothing more.

## Files

| File | What it is |
|---|---|
| `report_damage.py` | the measurement: original vs received, printed table + JSON + `SUMMARY.md` |
| `make_test_image.py` | builds the synthetic test images (never real patient data) |
| `jpeg_probe.py` | JPEG/EXIF structure parser used by the report (stdlib `struct` only) |
| `selftest.py` | checks the harness against a damage it creates itself |
| `results/` | where real platform reports go; `results_template.json` is the blank schema |
| `verification/` | the self-test's fixtures and its report (NOT platform measurements) |

Dependencies: Python 3.14 with the project venv (`novalife_hub/.venv`): numpy and
Pillow. Nothing else is needed and nothing needs installing.

## Step 1 — build the test images

```bash
cd novalife_hub
.venv/bin/python tools/phase_a_platforms/make_test_image.py
```

Writes, for each size (512 and 1024):

```
tools/phase_a_platforms/test_images/synthetic_chest_512.png            untouched reference
tools/phase_a_platforms/test_images/synthetic_chest_512_master.jpg     the file you send
tools/phase_a_platforms/test_images/synthetic_chest_1024.png
tools/phase_a_platforms/test_images/synthetic_chest_1024_master.jpg
```

The images are a synthetic chest-radiograph shape (dark field, bright lung
ellipses, ribs, fine texture, a black film margin), drawn procedurally from a
fixed seed. There is no patient data in them and no patient data is ever used in
this phase.

The `_master.jpg` carries fabricated metadata — `SYNTHETIC TEST IMAGE - NOT A
PATIENT`, `Make: SYNTHETIC`, `Model: TEST-FIXTURE`, and friends — because "did
the platform strip the metadata" is only measurable if the file that leaves the
hospital carries metadata. **Do not put any real EXIF on it.**

## Step 2 — keep the original untouched

This is the whole protocol's integrity guarantee, so it is worth being strict:

1. **Send a copy, keep the repo file.** Copy
   `synthetic_chest_512_master.jpg` to the phone over USB (or a cable-linked
   file manager) and send *that copy*. The file under `test_images/` is never
   touched and is what you pass to `--original`. Do not send the file itself
   from this machine through any service, or the "original" and the "received"
   copy stop being independent.
2. **Never re-save, re-compress, crop, rotate or "fix" the master.** Do not open
   it in an editor. Do not let a gallery app rewrite it. The file you send and
   the file you pass to `--original` must be byte-identical.
3. **Record the hash.** `make_test_image.py` prints a `sha256` for every file it
   writes; the report also prints the original's sha256. If the two ever
   disagree, the original was touched and the run is invalid.
4. **Name the copies after the platform the moment they come back.** WhatsApp
   images are timestamped and nearly indistinguishable; a wrong label makes the
   result useless, not just untidy.

## Step 3 — the sends

Do them in this order, on one phone, one day, ideally on Wi-Fi with default app
settings (no "HD"/"original quality" option unless the protocol says to). Take a
screenshot of each send's settings if the app offers them.

| # | Route | How |
|---|---|---|
| 1 | **WhatsApp, as image** | send in a chat (not a status), let it send, save the received image back to the gallery from the receiving phone, transfer that file out |
| 2 | **WhatsApp, as document** | attach as a document instead of a photo, then download it on the other side |
| 3 | **Telegram** | send as a photo (not a file), save the received copy |
| 4 | **Signal** | send as a normal image with default quality, save the received copy |
| 5 | **Instagram** | send in a DM (or post to a private account and save the delivered copy), and record which |
| 6 | **Email** | attach to an email sent to yourself, download the attachment from the mail client |
| 7 | **Screenshot** | open the master in the phone's gallery, screenshot the screen, and take the screenshot as the "received" copy |

Notes that matter more than they look:

- Use **two devices** where possible (send from one, save on the other). A
  self-send through the same account is fine but writes the route down.
- For each route, transfer the received file to this machine **as a file**
  (USB, or upload it to yourself in a way that does not recompress it again).
  Do not photograph the screen; do not take a screenshot to capture a
  screenshot unless that is the route being measured.
- Record the **phone model, OS version and app version** per run. A platform
  changes behaviour with versions and the number is only comparable with the
  version attached.
- Every run must use the **same original file**. If the master is re-created,
  its sha256 changes and the earlier results are not comparable with the later
  ones.

## Step 4 — measure

One command per platform, from `novalife_hub/`:

```bash
.venv/bin/python tools/phase_a_platforms/report_damage.py \
    --original tools/phase_a_platforms/test_images/synthetic_chest_512_master.jpg \
    --received  tools/phase_a_platforms/results/whatsapp_image_received.jpg \
    --platform  whatsapp_image \
    --out       tools/phase_a_platforms/results
```

(`--original` is the untouched file in `test_images/`; `--received` is the copy
that came back from the phone, stored wherever you keep the received copies.)

Use a descriptive `--platform` label: `whatsapp_image`, `whatsapp_document`,
`telegram`, `signal`, `instagram`, `email_attachment`, `screenshot`.

Outputs, into `--out`:

- `<platform>_report.json` — every number, machine-readable
- `<platform>_SUMMARY.md` — the same run in readable form
- `SUMMARY.md` — the most recent run, for whoever opens the folder first

The tool prints the same table to the terminal.

## What each field means, and what to trust

| Reported | Read it as |
|---|---|
| dimensions, scale factor x/y | measured exactly, from the file headers |
| aspect ratio | measured; "uniform scale" says whether the platform distorted it |
| JPEG coding, progressive | read from the SOF marker; not a guess |
| chroma subsampling | read from the SOF component sampling factors. A grayscale JPEG has no chroma plane, so it says "single component, grayscale" — that is the correct answer, not a failure |
| **estimated quality factor** | the one estimated number: an Annex K table match. It is labelled an estimate in the JSON and in `SUMMARY.md` |
| quantisation tables | the actual tables in the file, natural order, printed in full |
| EXIF tag count, tags present/absent | measured, tag by tag, against the original's tag list |
| orientation | the EXIF orientation value if it survived |
| PSNR / SSIM / RMSE / max diff | measured in the pixel domain, on the received geometry (the original is resampled to match, and the report says so and names the resampler) |
| DCT band change (DC, low, mid, high) | mean absolute change per band, from the 8x8 block DCT of both images. `mid` (zigzag 10-26) is the band `docs/algorithm.md` embeds in, so this row is the one that decides whether the mark has a channel at all |

Two honesty notes that the harness enforces on itself:

- If the geometry changed, a control compares **resize only** (the original
  downsampled and resampled back, never re-encoded) against **the platform**
  (the received copy upscaled back). The gap between them is what the re-encode
  added on top of the resize. Neither row is a claim about the platform's
  internal resampler, which is unknown.
- The resampler used for alignment is named in the JSON (`resampler`). It is the
  harness's choice, not the platform's.

## Results table to fill in

One row per route. Fill it in from the JSON, not from memory. Nothing goes in
this table that has not been measured on a real phone.

| Platform / route | phone, OS, app version | received size | scale x/y | coding | subsampling | est. quality | EXIF tags left | orientation | PSNR dB | mid-band change % | high-band change % |
|---|---|---|---|---|---|---|---|---|---|---|---|
| whatsapp_image | | | | | | | | | | | |
| whatsapp_document | | | | | | | | | | | |
| telegram | | | | | | | | | | | |
| signal | | | | | | | | | | | |
| instagram | | | | | | | | | | | |
| email_attachment | | | | | | | | | | | |
| screenshot | | | | | | | | | | | |

Suggested extra rows, once the table above exists: the same platform on a
different phone (is the behaviour the sender's or the receiver's?), a second send
through the same app (is it deterministic?), and the master sent to a group chat
rather than one person.

## Verify the harness itself first

```bash
.venv/bin/python tools/phase_a_platforms/selftest.py
```

This builds a synthetic original, damages it the way Phase A cares about
(downscale to a 1600 px long edge, re-encode at JPEG quality 72, drop the
metadata), runs the report on the pair and **checks that the harness reports
that damage correctly**: scale factor, quality estimate, subsampling, EXIF
stripping, and the band-level damage. It exits non-zero if any check fails. Its
output lives in `verification/` and is a test of the instrument, not evidence
about any platform.

## When the results are in

1. Copy each `<platform>_report.json` and `<platform>_SUMMARY.md` into
   `results/` (they are written there by default).
2. Add one row per platform to `novalife_hub/results/` — that folder is the
   project's record of measured data, and Phase A's numbers belong there with
   the date, the phone, the app version and the command.
3. Update `PROGRESS.md`: Phase A moves from "next" only when these files exist
   and the table above is filled.
4. Then, and only then, recompute the pilot-grid budget and the share
   resolution in `docs/algorithm.md` section 3 from the measured numbers.

## Known limits of this harness (stated before anyone measures with it)

- The quality factor is an **estimate** from Annex K tables. Encoders that do
  not scale Annex K (and there are several) will be reported as "not a
  plausible Annex K scaling", which is itself the finding.
- SSIM uses an 8x8 uniform window instead of the 11x11 Gaussian of the SSIM
  paper, and the mean is taken over the whole image rather than over strided
  windows. It is comparable between runs of this harness; it is not the
  reference SSIM number from the literature.
- The pixel-domain comparison resamples the original to the received geometry.
  The original's own resampling error is included in PSNR/SSIM and in the
  coefficient comparison; the control row exists to separate the two.
- A screenshot is not a compressive platform, and the report says so by
  reporting a PNG with no JPEG structure at all. That is the expected result for
  that row.
- Rotation, crop and unequal aspect ratios are reported, not interpreted. If a
  platform returns a rotated image, the orientation tag and the aspect ratio
  are how you will see it.
