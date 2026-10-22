# verification/ — the harness tested against a known damage

**Nothing in this folder is a measurement of a real platform.**

These files are produced by `selftest.py`, which builds a synthetic original,
damages it in a known way (downscale to a 1600 px long edge, re-encode at JPEG
quality 72, drop the metadata), runs `report_damage.py` on the pair, and checks
that the harness reports that damage correctly. Its purpose is to prove the
measuring instrument works — not to say anything about WhatsApp, Telegram,
Signal, Instagram, email or screenshots.

| File | What it is |
|---|---|
| `selftest_original_2048_q92.jpg` | synthetic original, built by the self-test |
| `selftest_damaged_q72_1600.jpg` | the same image, downscaled to 1600 px and re-encoded at q72, EXIF dropped |
| `selftest_known_damage_report.json` | the report on that pair, as written for a platform named `selftest_known_damage` |
| `subsampling_control_*.jpg` | colour encodes at 4:2:0, 4:4:4 and 4:2:2, used to prove the SOF subsampling reader tells them apart |
| `fixture_colour_resized.jpg`, `fixture_screenshot.png` | two dry-run fixtured for exercising the report code paths (colour + resize, and a PNG with no JPEG structure) |
| `SUMMARY.md` | the most recent run in this folder |

Real platform results go in `results/`, and into `novalife_hub/results/` with the
date, the phone, the app version and the command that produced them.
