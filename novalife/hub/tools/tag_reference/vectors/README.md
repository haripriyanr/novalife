# Conformance vectors (G2)

Generated files that freeze the Python reference for the RTL. **Do not edit by hand** — regenerate.

| Generator | Produces | Freezes |
|---|---|---|
| `gen_polar_vectors.py` | `polar_enc_info.mem`, `polar_enc_code.mem`, `polar_params.vh`, `polar_encode_vectors.json` | the polar **encoder** vs `polar_codec.polar_encode` |
| `gen_polar_decode_vectors.py` | `polar_dec_llr.mem`, `polar_dec_info.mem`, `polar_dec_params.vh`, `polar_decode_vectors.json` | the polar **SC decoder** integer contract (cross-checked vs `polar_scl_decode(..., l_size=1)`) |
| `gen_ascon_vectors.py` | `ascon_meta.mem`, `ascon_ad.mem`, `ascon_pt.mem`, `ascon_ct.mem`, `ascon_params.vh`, `ascon_vectors.json` | `ascon128_aead` vs `ascon_primitives.ascon_aead_encrypt` (17 official LWC KATs + the hub MAC and keystream paths) |
| `gen_mask_vectors.py` | `mask_in.mem`, `mask_roi.mem`, `mask_exp_var.mem`, `mask_exp_mask.mem`, `mask_params.vh`, `mask_vectors.json` | `perceptual_mask_core` vs `perceptual_mask.mask_block_decision` (31 blocks of 16 signed samples; every branch incl. the ROI majority boundary and floor division) |
| `gen_iwt_vectors.py` | `iwt_line_len.mem`, `iwt_line_in.mem`, `iwt_line_s.mem`, `iwt_line_d.mem`, `iwt_frame_spec.mem`, `iwt_frame_in.mem`, `iwt_frame_sub.mem`, `iwt_params.vh`, `iwt_vectors.json` | `iwt_53_core` vs `iwt_lifting.iwt1d_53` (12 lines) and `iwt_lifting.iwt2d_53` (2 frames, one **non-square**) |

## Bit-order and word-size contract

Bit `j` of a vector is `x[j]`; the integer value is `sum(x[j] << j)` (bit 0 is the LSB);
`.mem` lines are that integer in hex, `$readmemh`-compatible.

Three shapes exist, and they are not interchangeable:
- **Ascon** `.mem` files: **one hex byte per line**.
- **mask** `mask_in.mem` / `mask_roi.mem`: one word per **sample** (16-bit two's complement / 1 bit).
- **IWT** `.mem` files: every line is the **low 32 bits of a signed integer** (`%08x`), so negative
  coefficients survive. The testbench sign-extends the core's narrow outputs before comparing.

## Regenerate

```
novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_polar_vectors.py
novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_polar_decode_vectors.py
novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_ascon_vectors.py
novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_mask_vectors.py
novalife_hub/.venv/bin/python tools/tag_reference/vectors/gen_iwt_vectors.py
```

## Run the matching testbenches

```
vivado/scripts/run_sim.sh polar_encoder
vivado/scripts/run_sim.sh polar_sc_decoder
vivado/scripts/run_sim.sh ascon_core ascon128_aead_tb.v
vivado/scripts/run_sim.sh perceptual_mask_core
vivado/scripts/run_sim.sh iwt_53_core
```

All self-check (they fail on any mismatch) and are mutation-tested — see
`../../results/g2_polar_vectors_2026-10-19.md`, `../../results/g2_ascon_2026-10-19.md`,
`../../results/g2_mask_2026-10-19.md` and `../../results/g2_iwt_2026-10-19.md`.

## Still to add (G2)

`polar_sc_decoder` is **SC (list size 1)**; the pipeline decodes **SCL L=8**, which is not built.
No vectors yet for the pilot grid or QIM (those cores do not exist). The 5/3 IWT has vectors for
both directions of the analysis transform; there is **no inverse (synthesis) core** yet, so
perfect-reconstruction through hardware is not yet demonstrated (the Python reference's
`iiwt2d_53` round trip does hold).
