# Per-core Vivado synthesis — polar cores (G2) — 2026-10-19

> **POST-SYNTHESIS only.** `synth_design` / `report_utilization` / `report_timing_summary`,
> *Design State: Synthesized*. **No** `place_design`, `route_design`, `write_bitstream`, hardware
> manager or board. WNS uses *estimated* routing delays — real post-route Fmax will be lower.
> Treat LUT counts as upper bounds. Simulation is not hardware.

Method is identical to `hw_core_synth_2026-10-11.md` (one throwaway project per core, only that
core's source, core forced as top, one `create_clock -period 10.000` (100 MHz), `launch_runs
synth_1` + `wait_on_run`, then the two reports). One addition: both polar cores `` `include ``
generated headers from `tools/tag_reference/vectors/`, so that directory is added to the fileset's
`include_dirs`.

- **Tool:** `vivado v2026.1`, BASIC licence. **Part:** `xc7z010clg400-1`
  (budgets: 17,600 slice LUTs, 35,200 slice registers, 60 RAMB36, 80 DSP48E1).
- **Command:** `vivado -mode batch -source core_synth.tcl` with cwd = this directory.
- **Why measured:** the encoder was rewritten and the decoder is new (see
  `g2_polar_vectors_2026-10-19.md`); both need real area/timing before anything is built on them.

## Result

| Core | Status | Slice LUTs | Slice Registers | BRAM | DSP | WNS @100 MHz |
|---|---|---|---|---|---|---|
| `polar_encoder` | **OK** | 383 (2.18 %) | 257 (0.73 %) | 0 | 0 | **+4.500 ns** (timing met) |
| `polar_sc_decoder` | **FAIL** | — | — | — | — | — |

### `polar_encoder` — synthesises, fits, meets timing

383 LUT / 257 FF / 0 BRAM / 0 DSP, `WNS = +4.500 ns` on a 10 ns constraint (`All user specified
timing constraints are met`). The earlier 65-LUT figure came from a core that computed only **3 of
the 8** transform stages, so the correct core is naturally larger; 383 LUT is still 2.18 % of the
part.

### `polar_sc_decoder` — does **not** synthesise (resource explosion)

> **Follow-up (same day):** the decoder was **redesigned to be memory-backed** and now synthesises
> and meets timing (**471 LUT / 258 FF / 2.5 BRAM / 0 DSP, WNS +3.483 ns**). See
> `hw_core_synth_2026-10-19_decoder.md`. The failure below is kept as the record of why.

The synthesis process is **killed (OOM)** during *Cross Boundary and Area Optimization*
(`rdiArgs.sh: line 60: ... Killed`), so there are no utilization numbers. This is **structural**,
not a coding slip:

- the design keeps the whole SC tree in registers — `llr[9][256]` signed 16-bit
  (= 36,864 FFs) plus `bits[9][256]` (= 2,304 FFs) = **39,168 flip-flops**, which **exceeds the
  part's 35,200 slice registers** before any logic;
- those arrays are read and written at computed indices from many sites, so they cannot be inferred
  as block RAM and instead become enormous variable-index multiplexers.

A first attempt also used variable `/` and `%` in the index arithmetic (inferring dividers); those
were replaced with shifts/masks, which did not change the outcome — the arrays are the problem.

**Redesign path (next):** store the per-stage LLR/bits buffers in **memory** (the tree is only
9 × 256 × 16 b ≈ 4.6 KB → a few RAMB18) and/or use a **resource-shared butterfly** that reuses one
datapath across stages. That is the standard SC/SCL decoder shape and is the real G2 datapath work.

## Caveats

- **IOB artifact:** synthesising a core as top exposes its wide ports (256-bit codeword, 128-bit
  info) as device IOs (`Bonded IOB = 389 > 100`). That is an artifact of standalone synthesis, not a
  design constraint — inside a block design the core is wired internally.
- No register/area number here implies anything about place-and-route or on-board timing.
- The decoder failing synthesis is a **useful** result: it is exactly the check that keeps a
  non-implementable design off the board.

## Provenance

- sources: `vivado/ip_repo/polar_encoder/polar_encoder.v`,
  `vivado/ip_repo/polar_sc_decoder/polar_sc_decoder.v` (commit `4380937`)
- includes: `tools/tag_reference/vectors/polar_params.vh`, `polar_dec_params.vh`
- script: `core_synth.tcl` (this directory); logs: `run_transcript.log`, per-core `status.txt`
- date: 2026-10-19
