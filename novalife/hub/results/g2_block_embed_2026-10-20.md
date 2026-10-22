# `block_embed_core` — G2 verification + synthesis (2026-10-20)

> **POST-SYNTHESIS only.** `synth_design` / `report_utilization` / `report_timing_summary`,
> *Design State: Synthesized*. **No** `place_design`, `route_design`, `write_bitstream`, hardware
> manager or board. WNS uses *estimated* routing delays. Simulation is not hardware.

## Contract (algorithm.md 3.2)

- 4x4 LL block sign-of-Hadamard embedding ($H = [1,1,-1,-1] \otimes [1,1,-1,-1]$):
  1. $std = \text{isqrt}(var)$ (16-step iterative square root).
  2. $\delta = 64 + ((5 \times std) \gg 3)$, forced even; $T = \delta / 2$; $\text{cap} = 4 \times T$.
  3. $v = \sum H \cdot x$ (accumulated during stream input).
  4. Error $e = (+T - v)$ if bit 0 and $v < T$; $(-T - v)$ if bit 1 and $v > -T$; else 0. Clamped to $[-\text{cap}, \text{cap}]$.
  5. Distribution: $q = e \ggg 4$, $rem = e \ \& \ 15$; $d_k = q + (k < rem ? 1 : 0)$; $y_k = x_k + H_k \times d_k$.
  6. $rbit = (v < 0)$.

## Verification & Mutation Testing

- **Simulation**: 123/123 conformance vectors in `tools/tag_reference/vectors/be_vectors.json` PASS bit-exactly.
- **Mutation testing** (7 mutations caught):
  - Cap removed: 272 errors
  - Wrong Hadamard sign 0: 78 errors
  - No odd delta fix: 114 errors
  - Wrong sign threshold ($T = \delta/4$): 1229 errors
  - Truncate division on $e$ ($/$ instead of $\ggg$): 480 errors
  - Invert $rbit$: 119 errors
  - isqrt trial bit off: 2091 errors

## Post-Synthesis Implementation Numbers

| Slice LUTs | Slice Regs | BRAM | DSP | WNS @ 100 MHz |
|---|---|---|---|---|
| **450 (2.56%)** | **490 (1.39%)** | **0 (0%)** | **0 (0%)** | **+1.411 ns (timing met)** |

- Tool: `vivado v2026.1`; part `xc7z010clg400-1`; 10 ns clock constraint (`synth_1`).
- Throughput: 16 input samples in, 16 cycles isqrt, 2 compute cycles (`ST_CALC1`, `ST_CALC2`), 16 output samples out (34 cycles per 4x4 block, ~340 ns @ 100 MHz).
