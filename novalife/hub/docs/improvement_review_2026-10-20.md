# Improvement review — 2026-10-20

A self-grill pass (AGENTS.md §0.11) over the algorithm, the measurements, the reports and the novelty
path. Nothing here is a claim; every item says what would have to be measured.

## A. Defects found in this pass

| # | Defect | Status |
|---|---|---|
| A1 | The report humanizer **changed claims**: "post-synthesis" became "post-production" / "post-combination", "keyed placement" became "keyed situation", the `version` field became "revision", "amplitude normalisation" became "size normalisation", "synthesis numbers only" became "combination numbers only". Synonym rotation also chained (a replacement could be rewritten again). | **Fixed** (hub `59ae3b0`): domain terms are masked like numbers (`report_tools/turnitout_local/rules/protected_terms.json`), rotation is one pass, 5 regression cases added (selftest 17/17). Reports regenerated; the numeric-token diff shows only intended changes. |
| A2 | The reports were stale: iwt_53_core 3137 LUT (the old flip-flop build; current is 158 LUT / 150 FF / 1 BRAM), "39 tests", "scan-and-verify not built", "board nothing programmed", "inverse IWT not built", no 10.2 s perf row, crop "fixed 2026-10-20" (it was 10-19). | **Fixed** in `gen_benchmark.py` / `gen_theory.py`. Crop rows now say they are single runs, not the 50-mark matrix. |
| A3 | **False-accept multiplicity.** `recover()` makes up to 5 coarse candidates × 25 fine offsets × 9 region subsets = **1125 tag checks per image**. By the union bound the per-image false-accept bound is **~2^-37.9**, not the 2^-48 quoted everywhere. A forger gets ~1125 guesses per submitted image. The code comment said extra attempts "cannot cause a false accept". | Comment corrected (hub `6d9a97b`). **Open:** every document that quotes 2^-48 must quote the per-image bound too; the server rate limit must count images. |
| A4 | Crop 25% PASS decodes from **one region**: `region_ber=[0.492, 0.5, 0.492, 0.004]`. The R=4 soft-combine is not what saves it — the subset search is. | Wording: describe the decoder as "soft-combine plus authenticated subset search", not "soft-combine". |
| A6 | **The cipher is Ascon-128 v1.2, not NIST SP 800-232 Ascon-AEAD128.** `ascon_primitives.py` and `ascon128_aead.v` use IV `0x80400C0600000000` and a 64-bit rate, and the KATs are `crypto_aead/ascon128v12` (tag `E355159F…`). SP 800-232 Ascon-AEAD128 has a different IV, a 128-bit rate and little-endian byte order. Cryptographically sound (same permutation, CAESAR portfolio), but D4 and every doc that says "NIST SP 800-232" are wrong as written. Also: the module loads full plaintext blocks big-endian and the final partial block little-endian, which matches no Ascon spec I know of — the keystream (placement) path should be checked against a v1.2 KAT with a partial plaintext block. | **Resolved 2026-10-20 (owner chose the standard):** MAC and keystream moved to SP 800-232; the Python model passes all 1089 official KATs, the RTL is bit-exact and on the board again; the latent decrypt and partial-block bugs went with it. Re-measured: `results/g2_ascon_sp800_2026-10-20.md`. |
| A7 | `pilot_grid_sync` RTL claimed the `measure_axis` contract but is a raw autocorrelation argmax (no baseline, mean removal, lag normalisation, lag window, DFT refinement, phase or trust flag; no tb). | Header corrected to "placeholder" (hub `82cadc1`). Recommendation: keep the geometry search on the PS; the PL verifies the restored image. |
| A8 | The QIM embedder cannot be RTL-bit-exact to the current reference: the reference is float64 (DCT, sqrt of the variance, `round`). A PL embedder needs a fixed-point reference, which changes the embedded output. | Open — **owner's call** (written reason + full re-measure). Note the embed touches one DCT coefficient, so `block' = round(block + (rep − v)·b2·b2ᵀ)` — a fixed-point version is small. |
| A5 | Supabase drift: the cloud has `008_lab_tech_writes` applied (2026-10-11) with **no file** in `supabase/migrations/`. AGENTS.md §0.4 still says 006/007 pending (they are applied). | Open: export 008 into the repo (owner to confirm what it is). |

## B. Algorithm improvements — decoder-only first (the embedded output does not change)

These do not touch `embed.py`, so the owner's "no placement redesign" decision stands; they still
need the matrix re-run on the recovery side.

1. **Reliability-weighted combining.** A region that reads garbage (BER ≈ 0.5) still emits confident
   LLRs that cancel the good regions. Weight each region's LLRs by a measured reliability (mean |LLR|
   agreement with the other regions' hard decisions, or local pilot correlation) instead of trying 9
   fixed subsets. Targets: symmetric crop ≥10% ("two regions read garbage instead of abstaining") and
   JPEG Q40 (39/50). Measure: crop row + Q40 row, before/after.
2. **MAC-aided list decoding** (the CRC-aided SCL idea with the Ascon tag as the CRC): check the tag
   on all L=8 surviving paths, not only the minimum-metric path. Published technique, typical gain
   about 0.5–1 dB at this length. Cost: 8× more tag checks → per-image bound ~2^-34.9. The trade must
   be stated next to any gain.
3. **A fixed hypothesis budget.** Make the number of tag checks per image a named constant H, report
   FA = H × 2^-48 per image, and keep H small via 1 and 2 (better ranking, fewer subsets).
4. **Embed-side (owner's call, needs a written reason + full re-measure):** a 56- or 64-bit tag
   (shrinking the handle) buys back the margin the search spends; JPEG-grid-aware placement for Q40;
   a QIM-step sweep.

## C. Measurement and novelty path (P1 — systems + measurement)

No vacant algorithmic ground exists (PRIOR_ART §4.5). What makes P1 strong:

1. **Phase A is the contribution.** A measured table of what WhatsApp (standard/HD/as document),
   Telegram (photo/file), Signal, Gmail and an Android/iOS screenshot do to a medical image in 2026:
   resolution, chroma, quantisation tables, EXIF, and tag survival. PRIOR_ART §4.1 found no such
   study for medical images in India. Needs the phone.
2. **Real covers instead of 5 phantoms.** Trap 6: phantom rows are about those covers. Run the matrix
   on a public de-identified set (chest X-ray / brain MRI; check the licence) — this is the cheapest
   credibility gain.
3. **Quality–robustness curve.** PSNR 29.9 dB / SSIM 0.80 is the weakest number for a medical paper.
   Sweep the QIM step and plot PSNR vs Q40 / crop survival.
4. **Learned-watermark baselines** (e.g. TrustMark, StegaStamp, a WAM-style model) on the identical
   attack set, as context — not as "beats". The visible-QR baseline is already done.
5. **Swap-detection false-match rate** of the stored perceptual hash on medical images (PRIOR_ART
   §4.4, still open).
6. **Enclave numbers.** Verify latency/energy on the PL vs the same verify in PS software, post-route
   — the only measurable systems number behind the "key never crosses Linux" design.
7. Patent search (Digimarc/Philips/Dolby) — still open before the paper.

Honest framing: the technical core is "exact 128-bit authenticated recovery through resize and crop,
measured on real chat-app channels, with a verified hardware enclave". If B1/B2 close symmetric crop
≥10% without changing the embedded output, that is a measured result built from published parts —
not a new algorithm.
