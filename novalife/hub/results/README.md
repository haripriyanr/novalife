# results/ — measured data only

Everything in this folder is **measured**, with the date, the command and the input recorded.
Nothing here is a target, a plan or an estimate. Estimates and plans live in `docs/`.

| File | What it holds |
|---|---|
| `software_baseline_dct_qim.md` | the only measured end-to-end watermarking numbers we have (one cover, one seed) |
| `hardware_2026-09-14_to_16.md` | what actually ran on the Zynq board: bring-up, the PS bare-metal vault, and the Vivado synthesis numbers |

Raw machine-readable data sits next to its source:
`tools/stego_research/results/*.json`, and the images under
`tools/stego_research/results/` and `tools/stego_dct_qim/`.

Rules for this folder:
1. Every number says where it came from and whether it is simulation or hardware.
2. A result is one row per condition, with the seed and the input file, so it can be re-run.
3. Nothing is published, quoted in the paper or claimed until it is here.
