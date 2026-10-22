# NovaLife — PROGRESS TRACKER

> Last updated: 2026-10-19
> **Status:** software reference working and measured (single cover 9/10; **G1 matrix 5×10: resize and
> screenshot-like 50/50, JPEG Q40 39/50, crop 0/50**; **crop partly fixed 2026-10-19: corner 5–40% + JPEG and symmetric 5% recover
> exact 128 bits, symmetric ≥10% still open**); **crop recovery 23–48 s after perf pass 2 (was 127–160 s)**; app builds and runs; board alive but empty;
> a PS FreeRTOS firmware builds but its mailbox is a stub and no PL logic is in any bitstream.
>
> **Plan of record: `AGENTS.md` §0.** Prior-art verdict (2026-10-19, `novalife_hub/tools/stego_research/PRIOR_ART.md` §4):
> no algorithmic-novelty claim; the paper is systems + measurement; all hardware work is gated behind
> a software matrix that must pass (Gate **G1**), including exact recovery through a real resample.

**Full context and decisions:** `AGENTS.md`. **Measured data:** `novalife_hub/results/`.

## Where the evidence lives

| Folder | What it is |
|---|---|
| `novalife_hub/docs/algorithm.md` | the locked algorithm (RPP-QIM): stages, parameters, rejected alternatives |
| `novalife_hub/results/` | every measured number, with date and provenance |
| `novalife_hub/tools/tag_reference/` | the Python reference: build, pilot grid, embed, extract, demo |
| `novalife_hub/tools/phase_a_platforms/` | the harness that measures what a real chat app does to an image |
| `novalife_app/`, `supabase/` | the Flutter client and the database migrations |

## What is real, right now

**Measured, in software** (`results/tag_matrix_2026-10-19.md`, 5 covers × 10 seeds; and
`results/tag_python_reference_2026-10-11.md`, one cover):

- **G1 matrix (50 marks per condition):** resize 0.5x/0.75x/1.5x/2.0x and screenshot-like
  (resize 0.75x + JPEG Q80) **50/50**; JPEG Q90/Q70/Q50 and AWGN sigma 2 50/50; **JPEG Q40 39/50**
  (content/placement dependent — when it fails the per-region hard BER is ~0.5, i.e. a coding/robustness
  limit, not geometry); **crop 0/50**;
- **ROI guarantee:** zero change inside the drawn diagnostic region on all 50 marks;
- **false accept:** 0 tag PASS in 50 wrong-key attempts and 0 in 5 never-marked images (theoretical
  2^-48 per attempt, bounded online by the server rate limit);
- **visible-QR baseline:** a segno QR in a right margin decodes 50/50 on every attack, including the
  corner crop the tag cannot survive — a real advantage of a visible marker (but it is visible,
  occupies area, croppable, and carries no authentication);
- the single-cover run gives 9/10 (only crop fails);
- the pilot grid measures scale to within ~0.2%, which is *not* accurate enough to align the payload
  blocks after a resample; for a pure resize the scale is taken exactly from the received/declared
  size ratio instead, and the sub-pixel offset is found by an exact search with the 48-bit tag as the
  verdict (see `tools/tag_reference/extract.py`);
- **crop**: the earlier reading ("the grid is periodic, so a crop can be detected but not located") was
  **wrong**, and it cost time. Measured 2026-10-19 (`results/g1_crop_2026-10-19.md`): for a pure crop
  the scale is unchanged and the size is not, so the residual *is* the content shift; the failures were
  (1) one starved region aborting the whole read instead of contributing erasures, (2) the correct
  geometry being ranked below grid-equally-good decoys, and (3) `placement_map` seeing taint only the
  decoder had (which block carries which bit is decided by skipping tainted blocks, so new taint
  desynchronises the region). Fixed: erasures (LLR 0) for a bit with no block or no carrier; the crop
  residual as a priority candidate in both forms (`×1.0` corner, `×0.5` symmetric); placement taint
  (ROI ∪ clipping — the encoder's view) separated from erasure taint (adds cropped-away blocks); ROI
  statistics from covered pixels only. Measured: **corner crops 5/10/25/40%, corner 25% + JPEG q75 and
  symmetric 5% all PASS with exact 128 bits**; a 10% symmetric crop still fails (every region loses
  the same border, so no quadrant survives and two regions read garbage instead of abstaining).
- **Real-image check (2026-10-19, `results/g1_real_image_2026-10-19.md`):** the 50/50 rows above are
  partly a property of the phantom covers. On a real de-identified cardiac MRI (pinned by SHA-256,
  not committed) rendered at 2048×1154 — the native 500×282 scan cannot carry the tag at all, minimum
  viable long edge **1800 px** — **94.1%** of the placement blocks sat on a pixel clipped at 0 (the
  ROI mask pushes the mark into the black margin) and **every** re-encode failed at hard BER ≈ 0.53
  while the lossless control passed. Lifting the black level by 16 (one variable) left **0/1024**
  clipped blocks and flipped six channels from 0/3 to 3/3. The reference now taints clipped blocks
  alongside the ROI (`embed.clipped_blocks` / `embed.blocked_blocks`) and **refuses loudly** instead
  of emitting a dead tag; the taint is bit-identical on every phantom (proven: 5 covers × 3 handles
  — same masks, capacity, marked-image SHA-256, BER, verdict), so the matrix above is unchanged. The
  product answer is amplitude normalisation of the non-diagnostic area at intake ([16,235] measured
  to work); **not implemented in the gateway yet**.
- **The 1600-downscale geometry defect is fixed (2026-10-19, `results/g1_1600_geometry_2026-10-19.md`).**
  It was not damage: the pilot **mis-locked by a harmonic** (period 24.9 instead of 12.5 in LL, exactly
  2×, and it flagged itself `trusted=False`), and because the crop test was computed from that period,
  the one candidate that needs no pilot — the exact received/declared size ratio — was never built. The
  candidate is now admitted on either signal (pilot residual **or** both axis ratios agreeing within
  1%), and priority candidates take their exact slots first. Measured on the real scan: the
  **1600-long-edge q75/q90 channels go from fail to exact 128-bit PASS**, while the 1280 channel and
  45 phantom marks across the touched conditions are unchanged (0 verdict changes). Still open: the
  harmonic itself is unguarded (harmless for a pure resize, but crop has no pilot-free fallback, so it
  blocks any crop claim) and a mis-aimed candidate still reports a misleading `read_regions` taint.
- the marked export is visibly changed: PSNR 29.9 dB, SSIM 0.80 (needs retuning before hospital use);
- zero change inside the diagnostic ROI, measured in the software reference.

**Measured, in hardware** (`results/hw_core_synth_2026-10-11.md`, `results/hardware_2026-09-14_to_16.md`):

- the six existing PL cores synthesise to **802 LUTs (4.56%), 0 BRAM, 0 DSP**, all meeting a
  100 MHz clock — **post-synthesis only**, no place-and-route; the rewritten `polar_encoder` is
  **383 LUT / 257 FF**, WNS +4.500 ns, and the decoder — after the first all-register version failed
  to fit (OOM: >35,200 registers) — is now **memory-backed and synthesises at 471 LUT / 258 FF /
  2.5 BRAM tiles / 0 DSP, WNS +3.483 ns** (post-synthesis, 100 MHz) — `results/hw_core_synth_2026-10-19_decoder.md`;
- the board served HTTP at 192.168.31.86 with 0% ping loss, read/wrote an SD vault, passed a DDR
  march test (2026-09-16);
- JTAG sees the part; nothing is programmed (DONE = 0).

**Verified, in simulation — not hardware** (`results/g2_polar_vectors_2026-10-19.md`):

- `polar_encoder` **bit-exact** on 64 generated vectors, `polar_sc_decoder` (SC, list size 1)
  **bit-exact** on 24 vectors; both **mutation-tested** (a broken DUT fails);
- the integer SC contract equals the float `polar_scl_decode(l_size=1)`, and clean cases decode
  exactly to their 128 info bits; max internal magnitude 7031 (fits signed 16-bit);
- **this is simulation**: no synthesis of the decoder, no bitstream, no board.

**Measured, on the app:**

- 47 tests pass, `flutter analyze` clean, installs and launches on a real phone as
  `tech.syndrix.novalife`.

**Not built, not measured, not claimed:** the enclave firmware and the mailbox path, Linux, the
bitstream with our logic, the on-box database, any Fmax/area/power after place-and-route, and anything
that has been through a real chat app. (A PS-side FreeRTOS + lwIP firmware does build — see
`novalife_hub/firmware/` — but it runs no enclave and no PL marking.)

## Phase table

| Phase | Work | Status |
|---|---|---|
| A | Measure what the real chat apps do (phone), visible-QR baseline, finish prior-art survey | 🟡 harness built and self-verified (18/18); **needs the owner's phone** |
| B | Python reference of the tag and the attack matrix | ✅ built and measured — single cover 9/10; **G1 matrix 5×10**: resize 50/50, JPEG Q40 39/50, crop 0/50; **crop partly fixed 2026-10-19** (corner 5–40% + JPEG, symmetric 5% recover exact 128 bits; symmetric ≥10% open, matrix row not yet re-run); **perf pass 2 2026-10-20**: crop recovery 127→23 s (5.5×), official crop row now ~20 min |
| C | Server flow (handles, revoke, rate limit, hash-chained audit, perceptual hash) + app scan screen | ⬜ not started |
| D | PL cores: pilot-grid sync, tag engine, QIM embedder, soft-combine, polar SCL decoder; bit-exact; then Vivado numbers | 🟡 6 old cores synthesised; **polar stage bit-exact in sim 2026-10-19** (encoder + SC decoder; vectors + mutation-tested); SCL L=8 and the other new cores do not exist |
| E | Paper and demo, from measured data only | ⬜ |
| H | FreeRTOS firmware + boot from SD/QSPI + mailbox to the PL + reserved DDR window | 🟡 PS FreeRTOS build exists (HTTP vault, ESP32 Wi-Fi); mailbox is a **stub**, no PL logic, no Linux, no boot chain |
| DB | Cloud Supabase: create, apply migrations, add v2 tables, RLS | 🟡 **in progress** |
| App | SDK rework for the new instance, release build, roles, consent, audit, scan-and-verify | 🟡 analyze/test/install done; release build blocked on R8 keep rules |

## PL cores (`vivado/ip_repo/`)

| Core | Status |
|---|---|
| `ascon_core` | **real Ascon-AEAD128, verified 2026-10-19**: was a **stub** (no S-box, no linear layer — not a cipher); now **bit-exact over 19 vectors** (17 official LWC KATs + the hub MAC and keystream paths), mutation-tested; **synthesised 1422 LUT / 722 FF / 0 BRAM / 0 DSP, WNS +3.210 ns** (post-synthesis; the old 367-LUT figure was the stub) |
| `perceptual_mask_core` | **verified 2026-10-19**: was an 8-bit / Q16.8-`>=` / any-ROI stub that could not be checked against the reference; now implements `perceptual_mask.mask_block_decision` (floor-divided means, ROI **majority**, variance output), **bit-exact over 31 vectors**, mutation-tested; **synthesised 116 LUT / 152 FF / 0 BRAM / 2 DSP, WNS +2.054 ns** after splitting the compute into two cycles (single-cycle WNS −1.921 ns) |
| `iwt_53_core` | **verified 2026-10-19**: was a per-pixel stub (`d = x - ((x+0)>>>1)`, no even/odd split, no second dimension, `tuser` hard-wired to LL); now the real 5/3 lifting kernel, **bit-exact over 12 lines vs `iwt_lifting.iwt1d_53`** and, composed as two instantiations in the tb, **bit-exact on all four sub-bands for a 16x16 and a non-square 8x16 frame vs `iwt2d_53`**; mutation-tested; **synthesised 158 LUT / 150 FF / 1 BRAM tile / 0 DSP, WNS +3.618 ns** once the line buffers moved into a reset-free block (as flip-flops it was 3137 LUT / 8682 FF). **No inverse core yet** |
| ~~`dwt_2d_core`~~ | **deprecated 2026-10-19** → `legacy/dwt_2d_haar/`: Haar with 8-bit clipped (lossy) outputs — **not** the locked 5/3 IWT — and a testbench that compared nothing. Replaced by `iwt_53_core` |
| `polar_encoder` | **bit-exact, verified 2026-10-19** in simulation: 64 vectors vs the Python reference, mutation-tested; **synthesised 383 LUT / 257 FF / 0 BRAM / 0 DSP, WNS +4.500 ns** (post-synthesis) |
| `axi_lite_ctrl` | **moved to `legacy/`** — old AES-CTR + LSB register interface (banned scheme); the mailbox replaces it |
| `polar_scl_decoder` | **partial**: `polar_sc_decoder` (SC, list size 1) bit-exact + mutation-tested 2026-10-19; **redesigned memory-backed, synthesises 471 LUT / 258 FF / 2.5 BRAM / 0 DSP, WNS +3.483 ns** (post-synthesis); **SCL L=8 still missing** |
| `pilot_grid_sync` | **missing** (the new stage in `algorithm.md`) |
| `qim_adaptive_embedder` | **missing** |
| `tag_engine` (build + verify, key store, rate limit) | **missing** |
| multi-region soft-combine | **missing** |

## Compliance checklist (DPDP 2023 / NABH / ABDM, not legal advice)

| Requirement | Phase | Done |
|---|---|---|
| Explicit patient consent (DPDP §6) | C | ⬜ |
| Role-based access control (DPDP §8) | C | ⬜ |
| Immutable hash-chained audit trail (DPDP §10) | C | ⬜ |
| Breach notification, DPO reporting, erasure (§13) | C | ⬜ |
| Multi-factor authentication (NABH) | C | ⬜ |
| ABHA ID as the patient identifier (ABDM) | C | ⬜ |

## Rules this file must obey

1. A phase is done only when its artifacts exist and its checks pass.
2. No hardware number is written here unless it came from a real report or a board run.
3. Nothing is claimed before it is measured; no novelty claim before the prior-art survey.
4. Placeholders are labelled as placeholders.
5. Simulation is never written as hardware.
