# G2 — polar conformance vectors and bit-exact RTL (2026-10-19)

Gate **G2** is "reference frozen + conformance vectors; each core's testbench passing"
(`../AGENTS.md` §0.2). This file records the first G2 slice: the **polar stage**, done
properly, plus the harness every later core will use.

Everything here is **simulation** (Icarus Verilog). No synthesis, no board, no hardware
number. Simulated ≠ hardware.

## What was wrong before

| Item | State before | Evidence |
|---|---|---|
| `polar_encoder.v` | Implemented only **3 of the 8** transform stages, mapped the 128 info bits to channels 0..127 instead of the reliable set, and mixed blocking/non-blocking assignments in one clocked block | read of the old RTL; documented as untrusted in `../AGENTS.md` §0.4 |
| `polar_scl_decoder` | **did not exist** — no tag could be read in the PL | `../AGENTS.md` §0.4 |
| Testbenches | The existing testbenches **do not check anything**; they print and `$finish`. Ascon prints `SUCCESSFUL` unconditionally and prints a tag equal to its key-shaped input; the 2-level DWT tb prints `LL2 = 0, LH2 = 0` and still says success | run of each tb |
| Vectors | none — nothing was frozen, so "matches the reference" was unverifiable | — |

## What was built

| File | Role |
|---|---|
| `tools/tag_reference/vectors/gen_polar_vectors.py` | writes the encode vectors + `polar_params.vh`; self-checks the fast transform against the textbook Kronecker definition `F^⊗8` |
| `tools/tag_reference/vectors/gen_polar_decode_vectors.py` | integer SC contract, cross-checked against `polar_scl_decode(..., l_size=1)`; writes decode vectors + `polar_dec_params.vh` |
| `vivado/ip_repo/polar_encoder/polar_encoder.v` | rewritten: full 8-stage transform, generated index map, clean clocking |
| `vivado/ip_repo/polar_sc_decoder/polar_sc_decoder.v` | **new**: SC (list size 1) decoder, integer min-sum, bit-exact to the contract |
| `vivado/ip_repo/*/*_tb.v` (polar) | **self-checking** testbenches that read the vectors and fail on any mismatch |
| `vivado/scripts/run_sim.sh` | one command to run any core's tb with Icarus Verilog |

Bit-order contract (fixed, generated): bit `j` of a vector is `x[j]`; integer value is
`sum(x[j] << j)`; `.mem` lines are that integer in hex.

## Results (reproduce with `vivado/scripts/run_sim.sh <core>`)

```
$ vivado/scripts/run_sim.sh polar_encoder
polar_encoder_tb: PASS (64 vectors, bit-exact vs polar_codec.py)

$ vivado/scripts/run_sim.sh polar_sc_decoder
polar_sc_decoder_tb: PASS (24 vectors, bit-exact vs integer SC contract)
```

Independent checks, all passed:

- the reference fast `polar_transform` equals the **Kronecker** construction `u · F^⊗8`
  over GF(2) on 16 random `u` (so a wrong reference cannot silently become the standard);
- the **integer** SC decoder equals the float `polar_scl_decode(llr, l_size=1)` on all 24
  cases (so the RTL contract is the real decoder, not a lookalike);
- clean input cases (LLR = ±A) decode **exactly** to their own 128 info bits;
- datapath range: **max internal magnitude 7031**, inside signed 16-bit (±32767) — so
  16-bit arithmetic is provably sufficient on this vector set.

**Mutation tests** (prove the testbenches can fail, so PASS means something):

| Mutation | Result |
|---|---|
| encoder with `LOG2N = 7` (one stage removed) | `FAIL (64/64 vectors wrong)` |
| decoder with the leaf decision forced to `0` | `FAIL (24 errors)` |

## Not done (honest scope of this slice)

This is **not** all of G2, and it is not "hardware ready".

- **`polar_scl_decoder` is a `polar_sc_decoder`**: the RTL implements **list size 1**. The
  reference pipeline (`embed.py` / `extract.py`) decodes with **SCL L=8**
  (`polar_codec.polar_scl_decode` default). SCL L=8 in RTL (path copies, path-metric sort)
  is the next stage and is **not built**.
- **No synthesis yet** for the new decoder. It holds `llr[9][256]` signed 16-bit +
  `bits[9][256]` ≈ 38k flip-flops, which may be large for the XC7Z010; it must be
  synthesised and, if needed, reduced (e.g. smaller datapath, shared stage buffers).
- **Other cores still lack vectors and checking testbenches**: `ascon_core`,
  `iwt_53_core`, `dwt_2d_core`, `perceptual_mask_core` all still only print. The G2 vector
  set so far covers the polar stage only; IWT, mask, pilot, QIM and Ascon vectors are
  outstanding.
- **Nothing is wired into a block design or a bitstream**, and no `tag_engine` exists.

## Provenance

- reference: `tools/stego_research/sims/polar_codec.py` (N=256, K=128)
- simulator: Icarus Verilog (`iverilog`/`vvp`); commands in `vivado/scripts/run_sim.sh`
- vectors: seeds fixed (`20261019`), regenerate with the two `gen_*` scripts above
- date: 2026-10-19
