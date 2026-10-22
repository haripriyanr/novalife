# NovaLife C handoff

**Goal:** a C99 implementation of the NovaLife algorithm (marking + reading a 128-bit tag in a
medical image) that runs on a Zynq Cortex-A9 under FreeRTOS.  The Python in `python/` is the oracle.

* `nl_api.h`   -- the interface to implement: `nl_mark()` and `nl_recover()`.
* `python/`    -- reference (embed.py = marking, extract.py = reading, tag_block, ascon, polar, iwt,
                  pilot_grid.resample_affine).  Read embed.py and extract.py first.
* `make_golden.py` -- regenerates `golden/` from the Python (`../../.venv/bin/python make_golden.py`).
* `run_golden.c`, `Makefile` -- the test: `make test IMPL="your1.c your2.c" INC=-Iyour/include`.
  Exit 0 only if every golden case matches; `dummy_impl.c` is a wrong implementation that must FAIL.

**What "correct" means**
* `nl_mark`: output image **byte-identical** to Python `embed.mark` (it is all integer maths:
  integer ROI cut, 5/3 integer wavelet, Ascon-AEAD128 as PRF for a Feistel placement permutation,
  polar encode N=256 K=128, sign-of-Hadamard embedding), same `copies_written` and capacities, and the
  same refusals.
* `nl_recover`: same `tag_ok` and the same 128 bits as Python `extract.recover` after resize, JPEG,
  crop; and **never** `tag_ok` for a wrong key or an unmarked image.
* Float is only in the reader (bilinear resample, soft LLRs); use double.

No stdio/platform code in the library; malloc is fine but handle failure.  Size target: 512x512
mark < 3 s, recover < 5 s (worst case crop < 40 s) on a desktop.
