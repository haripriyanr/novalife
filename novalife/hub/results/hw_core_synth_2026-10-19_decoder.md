# Per-core Vivado synthesis — REDESIGNED polar SC decoder (G2) — 2026-10-19

> **POST-SYNTHESIS only.** `synth_design` / `report_utilization` / `report_timing_summary`,
> *Design State: Synthesized*. **No** `place_design`, `route_design`, `write_bitstream`, hardware
> manager or board. WNS uses *estimated* routing delays — real post-route Fmax will be lower.
> Simulation is not hardware.

This run replaces the first 2026-10-19 attempt, in which `polar_sc_decoder` **did not synthesise**
(Vivado OOM: the all-register tree needed 39,168 flip-flops > the part's 35,200 slice registers).
`vivado/ip_repo/polar_sc_decoder/polar_sc_decoder.v` is now **memory-backed**: the SC tree lives in
two inferred simple-dual-port RAMs and a microsequencer walks it one element at a time.

- **Tool:** `vivado v2026.1`, BASIC licence. **Part:** `xc7z010clg400-1`
  (budgets: 17,600 slice LUTs, 35,200 slice registers, 60 RAMB36, 80 DSP48E1).
- **Command:** `vivado -mode batch -source core_synth.tcl` with cwd = this directory.
- **Evidence:** `polar_sc_decoder/util.rpt`, `polar_sc_decoder/timing.rpt`,
  `polar_sc_decoder/status.txt` (`STATUS: OK`), `run_transcript.log`.

## Result

| Core | Status | Slice LUTs | Slice Regs | RAMB36 | RAMB18 | DSP | WNS @100 MHz |
|---|---|---|---|---|---|---|---|
| `polar_sc_decoder` (memory-backed) | **OK** | **471 (2.68 %)** | **258 (0.73 %)** | **2** | **1** | **0** | **+3.483 ns — timing met** |

- **Block RAM tiles: 2.5 (4.17 %)** — the two tree memories inferred as BRAM, not flip-flops:
  `llr_mem` 2304 × 16 b = 36,864 b = exactly one **RAMB36** → 2 RAMB36 used for the 16-bit LLR tree
  (Vivado packed it as 2 × RAMB36 + 1 × RAMB18 total); `bits_mem` 2304 × 1 b → the **RAMB18**.
  `LUT as Memory = 0` confirms nothing spilled into distributed RAM.
- **Timing met:** `All user specified timing constraints are met`, WNS **+3.483 ns** on a 10 ns
  (100 MHz) constraint, TNS 0, WHS +0.148 ns. Worst path: `stage_r` → `bits_mem` read address.

## How it was made to fit (and to meet timing)

Three changes from the failed version, each verified in simulation (`g2_polar_vectors_2026-10-19.md`):

1. **Memory-backed tree.** `llr[9][256]×16b + bits[9][256]` (39,168 FF) → two inferred simple-dual
   RAMs (2304×16 + 2304×1). A small FSM (`ST_UPD_A…E`, `ST_DEC_A/B`, `ST_PROP_A…D`) reproduces the
   exact Python leaf-by-leaf order.
2. **No multipliers in F.** `sign(a)·sign(b)·min(|a|,|b|)` was two 16-bit multipliers on the critical
   path (−5.657 ns). Replaced with a sign-bit XOR plus a conditional negate (no multiplier).
3. **Pipelined write data.** `|a|`, `|b|` and the sign are registered, then `min`/negate produces the
   write word on the next cycle. Element cost 3 → 5 cycles, but the F/G path between RAM ports is
   broken into reg-to-reg hops.

| Redesign step | WNS @100 MHz | Notes |
|---|---|---|
| all-register (first attempt) | — | **OOM** — 39,168 FF > 35,200 |
| memory-backed, combinational F/G | −5.657 ns | fits (589 LUT) but slow |
| + no-multiplier F | −2.449 ns | |
| + pipelined write data (final) | **+3.483 ns** | **timing met** |

## Cost of the fix

- **Throughput drops.** Serial per-element walk ⇒ **~0.46 M cycles per codeword** (structural: the
  same number for every vector) = **~4.6 ms @100 MHz**, ~9.2 ms @50 MHz. Fine for a prototype tag
  path (a verification is not latency-critical); a fully parallel SC/SCL design would be far faster
  and far larger.
- The testbench budget was raised from 200,000 to 800,000 cycles to match (see
  `polar_sc_decoder_tb.v`).

## Verification (simulation, Icarus)

- `./vivado/scripts/run_sim.sh polar_sc_decoder` → **PASS (24 vectors, bit-exact vs integer SC
  contract)**.
- **Mutation-tested** on the final RTL: forcing the leaf decision to 0 → 24/24 errors; dropping the F
  sign (`mag` instead of `±mag`) → 24/24 errors. The testbench is still sensitive to real defects.

## Caveats

- **IOB artifact:** synthesising a core as top exposes its wide ports (256-bit LLR load, 128-bit
  info) as device IOs (`Bonded IOB = 158 > 100`). Artifact of standalone synthesis; inside a block
  design the core is wired internally.
- Post-synthesis only; no place-and-route, no bitstream, no board. `−5.657`/`−2.449`/`+3.483` are
  estimates under a 10 ns constraint.
- Still **SC (list size 1)**. The pipeline decodes **SCL L=8**, which is not built. The SCL decoder
  will need L parallel copies of this tree (memory or registers) — a separate design task.

## Provenance

- source: `vivado/ip_repo/polar_sc_decoder/polar_sc_decoder.v` (+ `polar_sc_decoder_tb.v`)
- includes: `tools/tag_reference/vectors/polar_params.vh`, `polar_dec_params.vh`
- script: `core_synth.tcl` (this directory); logs: `run_transcript.log`, `polar_sc_decoder/status.txt`
- prior (failed) run: `../hw_core_synth_2026-10-19.md`
- date: 2026-10-19
