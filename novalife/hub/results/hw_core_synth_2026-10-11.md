# Per-core Vivado synthesis measurement — NovaLife PL cores

> **All numbers in this file are POST-SYNTHESIS** (Vivado `synth_design` / `report_utilization` /
> `report_timing_summary`, *Design State: Synthesized*). They are **not post-implementation**
> (no `place_design` / `route_design` / `write_bitstream` was run). WNS here uses *estimated*
> routing delays; the real F<sub>max</sub> after place-and-route will be **lower**. Treat every
> timing figure as an upper-bound estimate, and every LUT count as an upper bound that
> `opt_design`/physical optimisation can only reduce (`report_utilization` says so itself).

Date of run: **2026-10-11**. This is the **first** measured area/timing data for the tag cores;
until now the only Vivado numbers we had were the 2026-09-15 AES-CTR vault path (79% LUT / 88%
slice, WNS −38.641 ns) in `results/hardware_2026-09-14_to_16.md`.

## What was measured and how

- **Tool:** `vivado v2026.1` (SW Build 6511674), BASIC licence active to 2027-06-27.
- **Part:** `xc7z010clg400-1`. Device budgets used by the reports: **17,600** slice LUTs,
  **35,200** slice registers, **60** block-RAM tiles (RAMB36), **80** DSP48E1, 6,000 LUTRAM.
- **Clock:** one `create_clock -period 10.000` (100 MHz) on the core's clock port, in an XDC
  added to `constrs_1`. No PS FCLK assumed.
- **Method:** one throwaway project per core (`create_project -force`), only that core's source
  file(s) added, the core module forced as top (so nothing is optimised away across modules),
  `launch_runs synth_1` + `wait_on_run`, `open_run synth_1`, then `report_utilization` and
  `report_timing_summary -max_paths 25` to per-core files. **Implementation, bitstream and the
  hardware manager were never invoked.**
- `dwt_2d_transform_2level` was measured as a **bonus** core (it instantiates two
  `dwt_2d_transform`); it is **not** one of the six requested cores and is listed separately.

Each core is wrapped in `catch{}`, so an elaborate/synth failure is recorded as a valid result and
the loop continues. **All seven elaborated and synthesised cleanly: no errors, no CRITICAL
WARNINGs, no latch inference.** `status.txt` per core = `STATUS: OK`.

### Exact command (run with cwd = this results directory)

```bash
source /home/user/develop/Xilinx/2026.1/Vivado/settings64.sh && \
  vivado -mode batch -source core_synth.tcl \
         -log run_vivado.log -journal run_vivado.jou \
         > run_transcript.log 2>&1
```

### Script used (`core_synth.tcl`, kept in this directory)

```tcl
# ============================================================================
# NovaLife HUB - per-core POST-SYNTHESIS area + timing measurement
#   One throwaway project per core, only that core's source(s), core forced as
#   top, 10 ns create_clock, ONLY synth_1. No implementation / bitstream / board.
#   Each core wrapped in catch{} so a failure is recorded and the loop continues.
# ============================================================================
set base   /run/media/user/DATA/repos/embedded_proj/novalife_hub/results/hw_core_synth_2026-10-11
set iprepo /run/media/user/DATA/repos/embedded_proj/novalife_hub/vivado/ip_repo
set part   xc7z010clg400-1

# {rundir_name  top_module  {src files (rel. to ip_repo)}  clock_port}
set cores {
    {ascon_core    ascon128_aead           {ascon_core/ascon128_aead.v}                          clk}
    {perceptual_mask_core perceptual_mask_core {perceptual_mask_core/perceptual_mask_core.v}    clk}
    {iwt_53_core   iwt_53_core             {iwt_53_core/iwt_53_core.v}                            clk}
    {dwt_2d_core   dwt_2d_transform        {dwt_2d_core/dwt_2d_transform.v}                       clk}
    {polar_encoder polar_encoder           {polar_encoder/polar_encoder.v}                        clk}
    {axi_lite_ctrl axi_lite_ctrl           {axi_lite_ctrl/axi_lite_ctrl.v}                        s_axi_aclk}
    {dwt_2d_2level dwt_2d_transform_2level {dwt_2d_core/dwt_2d_transform.v dwt_2d_core/dwt_2d_transform_2level.v} clk}
}

proc synth_one {name top rellist clport} {
    global base iprepo part
    set rundir [file join $base $name]
    file mkdir $rundir
    set status [file join $rundir "status.txt"]
    set xdc    [file join $rundir "timing.xdc"]
    # 10 ns (100 MHz) single-clock constraint, independent of the PS FCLK.
    set fh [open $xdc w]
    puts $fh "# 100 MHz clock constraint (post-synthesis timing check)"
    puts $fh "create_clock -name ${name}_clk -period 10.000 \[get_ports $clport\]"
    close $fh
    set srclist [list]
    foreach r $rellist { lappend srclist [file join $iprepo $r] }
    if {[catch {
        create_project -force ${name}_synth [file join $rundir proj] -part $part
        add_files -fileset sources_1  $srclist
        add_files -fileset constrs_1  $xdc
        set_property top $top [current_fileset]
        launch_runs synth_1
        wait_on_run  synth_1
        open_run     synth_1
        report_utilization    -file          [file join $rundir util.rpt]
        report_timing_summary -max_paths 25  -file [file join $rundir timing.rpt]
        close_project
    } err]} {
        set fh2 [open $status w]
        puts $fh2 "STATUS: FAIL"; puts $fh2 "ERROR:"; puts $fh2 $err
        puts $fh2 ""; puts $fh2 "ERRORINFO:"; puts $fh2 $::errorInfo
        close $fh2
        catch { close_project }
        puts "CORE $name: FAIL (see $status)"
        return
    }
    set fh2 [open $status w]; puts $fh2 "STATUS: OK"; close $fh2
    puts "CORE $name: OK"
}
foreach c $cores { synth_one {*}$c }
puts "ALL_DONE"
```

## Summary — six requested cores (post-synthesis)

| Core (top module) | Slice LUTs | LUT% | FF (Slice Reg) | FF% | BRAM36 | DSP48 | WNS (ns) | Timing @100 MHz |
|---|--:|--:|--:|--:|--:|--:|--:|---|
| `ascon128_aead` (ascon_core) | 367 | 2.09% | 393 | 1.12% | 0 | 0 | +6.728 | **MET** (0 fail) |
| `perceptual_mask_core` | 175 | 0.99% | 39 | 0.11% | 0 | 0 | +1.519 | **MET** (0 fail) |
| `iwt_53_core` | 21 | 0.12% | 41 | 0.12% | 0 | 0 | +5.312 | **MET** (0 fail) |
| `dwt_2d_transform` (dwt_2d_core) | 54 | 0.31% | 35 | 0.10% | 0 | 0 | +5.671 | **MET** (0 fail) |
| `polar_encoder` | 65 | 0.37% | 257 | 0.73% | 0 | 0 | +7.738 | **MET** (0 fail) |
| `axi_lite_ctrl` | 120 | 0.68% | 368 | 1.05% | 0 | 0 | +7.171 | **MET** (0 fail) |
| **Bonus** `dwt_2d_transform_2level` | 65 | 0.37% | 54 | 0.15% | 0 | 0 | +5.579 | **MET** (0 fail) |

Across the **six requested cores in total**: **802 slice LUTs (4.56%)**, **1,133 FFs (3.22%)**,
**0 BRAM, 0 DSP48**. (Sum of isolated core numbers; the integrated system is not just the sum.)

## Budget verdict (targets `<75%` LUT, `<40%` DSP, `<40%` BRAM)

- **Every core, individually, fits all three budgets with large margin** — the largest is
  `ascon128_aead` at 2.09% LUT, and **all** use 0% DSP and 0% BRAM.
- This **confirms the design principle** that the tag cores must stay small: unlike the 2026-09-15
  AES-CTR/DMA/DCT path (79% LUT, did not time-close), the six tag cores together are ~4.6% LUT.
- **Caveat — this is not the system.** These are isolated cores. The PL enclave still needs the
  wrapper, the AXI interconnect, the DMA/reserved-window path, and (later) a soft CPU — none of
  which is measured here. Budget headroom is real but must be re-checked on the integrated design.
- **Timing:** all six meet 100 MHz setup at post-synthesis (WNS > 0). This is an estimate; real
  routing will eat the margin. `perceptual_mask_core` is the tightest (**WNS +1.519 ns**, its
  variance-compare path); everything else has ≥5 ns of estimated slack.

## Per-core detail

Utilisation columns below are the Vivado `report_utilization` rows; timing is the `report_timing_summary`
setup (max-delay) analysis. "Total endpoints" = TNS Total Endpoints; failing = TNS Failing Endpoints.

### 1. `ascon128_aead` — ascon_core/ascon128_aead.v

| Resource | Used | Available | Util% |
|---|--:|--:|--:|
| Slice LUTs (as logic) | 367 | 17,600 | 2.09% |
| LUT as Memory (LUTRAM) | 0 | 6,000 | 0.00% |
| Slice Registers (FF) | 393 | 35,200 | 1.12% |
| Block RAM Tile (RAMB36) | 0 | 60 | 0.00% |
| DSP48 | 0 | 80 | 0.00% |

- **WNS +6.728 ns / TNS 0.000 ns / 0 failing of 786 endpoints — timing MET.**
- Critical path: `round_cnt_reg[3]` → `S_reg[3][0]/CE`, data-path 2.890 ns (logic 0.875, route 2.015).
- Small and fast at 100 MHz. This module is the AeAD datapath only; the MAC/KDF tag mode is not in
  it yet, so its final size will grow.

### 2. `perceptual_mask_core` — perceptual_mask_core/perceptual_mask_core.v

| Resource | Used | Available | Util% |
|---|--:|--:|--:|
| Slice LUTs (as logic) | 175 | 17,600 | 0.99% |
| LUT as Memory (LUTRAM) | 0 | 6,000 | 0.00% |
| Slice Registers (FF) | 39 | 35,200 | 0.11% |
| Block RAM Tile (RAMB36) | 0 | 60 | 0.00% |
| DSP48 | 0 | 80 | 0.00% |

- **WNS +1.519 ns / TNS 0.000 ns / 0 failing of 40 endpoints — timing MET (tightest of all).**
- Critical path: `sum_x_reg[5]` → `mask_out_reg/D`, data-path **8.330 ns** (logic 3.547,
  route 4.783) — the single-cycle variance decision (multiply + add + compare).
- **Observation:** the header calls this "DSP48-based", but synthesis mapped **both** squares
  (8×8 and ~12×12) to **LUTs — DSP48 = 0**. To actually spend DSP48 (and save LUTs/power) the
  multipliers would need explicit DSP inference/synthesis controls; left to defaults Vivado chose
  LUTs. Flagging so the "DSP48 variance" description and reality match.

### 3. `iwt_53_core` — iwt_53_core/iwt_53_core.v

| Resource | Used | Available | Util% |
|---|--:|--:|--:|
| Slice LUTs (as logic) | 21 | 17,600 | 0.12% |
| LUT as Memory (LUTRAM) | 0 | 6,000 | 0.00% |
| Slice Registers (FF) | 41 | 35,200 | 0.12% |
| Block RAM Tile (RAMB36) | 0 | 60 | 0.00% |
| DSP48 | 0 | 80 | 0.00% |

- **WNS +5.312 ns / TNS 0.000 ns / 0 failing of 71 endpoints — timing MET.**
- Critical path: `d_calc_reg[3]` → `s_calc_reg[13]/D`, data-path 4.584 ns.
- Very small. (Several declared regs are unused in the RTL and were optimised away.)

### 4. `dwt_2d_transform` — dwt_2d_core/dwt_2d_transform.v

| Resource | Used | Available | Util% |
|---|--:|--:|--:|
| Slice LUTs (as logic) | 54 | 17,600 | 0.31% |
| LUT as Memory (LUTRAM) | 0 | 6,000 | 0.00% |
| Slice Registers (FF) | 35 | 35,200 | 0.10% |
| Block RAM Tile (RAMB36) | 0 | 60 | 0.00% |
| DSP48 | 0 | 80 | 0.00% |

- **WNS +5.671 ns / TNS 0.000 ns / 0 failing of 58 endpoints — timing MET.**
- Critical path: `prev_pixel_reg[2]` → `hh_out_reg[5]/D`, data-path 4.225 ns.

### 5. `polar_encoder` — polar_encoder/polar_encoder.v

| Resource | Used | Available | Util% |
|---|--:|--:|--:|
| Slice LUTs (as logic) | 65 | 17,600 | 0.37% |
| LUT as Memory (LUTRAM) | 0 | 6,000 | 0.00% |
| Slice Registers (FF) | 257 | 35,200 | 0.73% |
| Block RAM Tile (RAMB36) | 0 | 60 | 0.00% |
| DSP48 | 0 | 80 | 0.00% |

- **WNS +7.738 ns / TNS 0.000 ns / 0 failing of 128 endpoints — timing MET (best WNS).**
- Critical path: `u_vec_reg[7]` → `encoded_bits_out_reg[0]/D`, data-path 2.111 ns.
- Note for follow-up: the RTL maps only the lower 128 bits of `u_vec` (the code reports 257 FF =
  the 256-bit `encoded_bits_out` + `valid_out`), and mixes non-blocking loads with blocking reads
  of `u_vec`, so **the encoding this RTL produces is not trustworthy as-is** — it still needs to be
  checked bit-exact against the Python reference. Synthesis succeeded regardless; this file reports
  area/timing only, not functional correctness.

### 6. `axi_lite_ctrl` — axi_lite_ctrl/axi_lite_ctrl.v

| Resource | Used | Available | Util% |
|---|--:|--:|--:|
| Slice LUTs (as logic) | 120 | 17,600 | 0.68% |
| LUT as Memory (LUTRAM) | 0 | 6,000 | 0.00% |
| Slice Registers (FF) | 368 | 35,200 | 1.05% |
| Block RAM Tile (RAMB36) | 0 | 60 | 0.00% |
| DSP48 | 0 | 80 | 0.00% |

- **WNS +7.171 ns / TNS 0.000 ns / 0 failing of 688 endpoints — timing MET.**
- Critical path: `ar_addr_r_reg[2]` → `s_axi_rdata_reg[10]/D`, data-path 2.678 ns.
- This is the *old* AES-CTR/LSB register file, not the enclave mailbox; it is small and clean, but
  it does not match the mailbox command set in `docs/system_architecture.md`.

### 7. (Bonus) `dwt_2d_transform_2level` — dwt_2d_core/dwt_2d_transform_2level.v

| Resource | Used | Available | Util% |
|---|--:|--:|--:|
| Slice LUTs (as logic) | 65 | 17,600 | 0.37% |
| LUT as Memory (LUTRAM) | 0 | 6,000 | 0.00% |
| Slice Registers (FF) | 54 | 35,200 | 0.15% |
| Block RAM Tile (RAMB36) | 0 | 60 | 0.00% |
| DSP48 | 0 | 80 | 0.00% |

- **WNS +5.579 ns / TNS 0.000 ns / 0 failing of 91 endpoints — timing MET.**
- Critical path: `stage1/ll_out_reg[0]` → `stage2/hh_out_reg[5]/D`, data-path 4.317 ns.
- Included because the file was named and it exercises the `dwt_2d_transform` dependency
  (measures `dwt_2d_transform.v + dwt_2d_transform_2level.v` together). Not one of the six.

## Caveats (read before quoting any number)

1. **Post-synthesis only.** No place/route/bitstream. WNS uses estimated net delays; implement the
   design (`place_design`/`route_design`) before stating an F<sub>max</sub>. `report_utilization`
   itself warns the final LUT count can be lower after physical optimisation.
2. **Isolated cores.** No AXI interconnect, no DMA, no wrapper, no soft CPU, no cross-clock paths.
   The integrated enclave's utilisation and (especially) its timing will differ.
3. **DSP = 0 everywhere.** Notably `perceptual_mask_core` mapped its multipliers to LUTs despite
   the "DSP48-based" intent. Whether we *want* DSP48 (LUT/power trade) is a decision, not a bug.
4. **Area/timing ≠ function.** These runs prove the RTL elaborates and meets the 100 MHz estimate,
   not that it computes the right answer. Bit-exact checks against `tools/stego_research/sims/`
   are still required for every core before any functional claim.
5. **`polar_encoder` RTL is suspect** (see its note); do not trust its output until it is verified.

## Where the files are

Everything from this run lives under `novalife_hub/results/hw_core_synth_2026-10-11/`:

```
core_synth.tcl                 # the script above
run_vivado.log / run_vivado.jou
run_vivado_79512.backup.log / .jou   # from the first, aborted attempt (bad command)
run_transcript.log             # stdout tee (has all CORE ... : OK lines)
.Xil/                          # Vivado cache (run with cwd here, so nothing hit the repo root)
<core>/proj/                    # per-core throwaway Vivado project + synthesized .dcp
<core>/util.rpt <core>/timing.rpt
<core>/timing.xdc <core>/status.txt
```

Total on-disk footprint ≈ 3.5 MB. Nothing was written to the repo root or to `/tmp`.
**No git commit was made.**
