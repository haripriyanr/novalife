# hubcore -- the NovaLife algorithm in portable C (runs on the Zynq PS under FreeRTOS)

Purpose: interim home for everything that is not yet in the PL (2026-10-22, owner's decision:
"move all jobs not on the PL to the PS, port to the PL later").  It is a **C99 port of the Python
reference** in `tools/tag_reference/` (+ `tools/stego_research/sims/`).  The Python is the oracle:

* every integer function must be **bit-identical** to the Python (same pixels out, same bits, same
  placement, same tag);
* float code (LLRs, soft scoring) must give the **same decisions** on the golden cases;
* every test compares against golden data produced by the Python reference and **fails on any
  mismatch**; a test that prints PASS without comparing is a defect (the project has been bitten
  by stubs before).  Mutation-check your tests (break the code on purpose, see it fail).
* no platform code: only `<stdint.h> <stddef.h> <stdlib.h> <string.h> <math.h>`; no stdio in `src/`
  (tests may use stdio).  The same sources are built for the host (gcc, tests) and for the
  Cortex-A9 firmware.  malloc is allowed but every failure must be handled and returned as an error.

Layout: `include/hubcore/*.h`, `src/*.c`, `tests/*.c`, `tests/gen_*.py` (writes `tests/golden/*`),
`Makefile` (`make test` builds and runs all tests with the host gcc; `-Wall -Wextra -Werror`).
Run Python with `novalife_hub/.venv/bin/python`.

Module ownership (do not edit files you do not own; read others' headers):
* A (primitives): `ascon`, `tag_block`, `polar` (encode + SCL L=8 decode), `iwt` (5/3 forward and
  inverse 2D).
* B (embedder): `embed` (roi_cut/roi mask, floor_background, taint masks, Feistel placement,
  integer sign-of-Hadamard block embed, `hc_mark()`), uses A's headers.
* C (reader): `extract` (resample_affine, coverage, read_regions, candidates, decode attempts,
  `hc_recover()`), uses A's and B's headers.
If a header you need is not there yet, write against the Python signature, keep going, and run the
tests once the file appears (`ls include/hubcore`); never re-implement another module's function.
