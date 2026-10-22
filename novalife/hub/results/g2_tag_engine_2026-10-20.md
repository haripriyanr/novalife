# G2/G4 — PL tag engine `tag_engine` (2026-10-20)

> **Superseded 2026-10-20:** measured with the Ascon-128 **v1.2** core. The cipher moved to NIST SP 800-232
> Ascon-AEAD128 the same day — see `results/g2_ascon_sp800_2026-10-20.md`. Kept as the record of that run.


**What:** `vivado/ip_repo/tag_engine/` — BUILD_TAG / VERIFY_TAG for the enclave, on top of the
verified `ascon128_aead` core: a write-only key register (load / wipe from the admin port, no path
to any output), the 48-bit tag over `version | hub_id | handle`, and a token-bucket limit on
**failed** verifies. **Level of evidence:** simulation + **post-synthesis**. Not in a bitstream, not
connected to the mailbox, not on the board.

## Contract

`tag_block.compute_tag` (Python reference). `tools/tag_reference/vectors/gen_tag_engine_vectors.py`
asserts that streaming this 54-byte associated data through `ascon_aead_encrypt` with an empty
plaintext reproduces `compute_tag` on all 16 cases:

    MAC_DOMAIN || MAC_DOMAIN || 0x0B || version(1) || hub_id(2, BE) || handle(8, BE)

Two reference quirks this made visible (both harmless, both now the contract): `MAC_DOMAIN` is
prepended twice (`compute_tag` and `mac_truncated` each add it), and the header is 11 bytes, not the
10 the `header_bytes_of` docstring says.

## Simulation

```
vivado/scripts/run_sim.sh tag_engine          # deps.txt pulls in ascon_core
tag_engine_tb: PASS (16 vectors bit-exact; reject flips, wrong key; NO_KEY, BAD_OP, rate limit, wipe)
```

Checked: BUILD tag == `compute_tag` (16/16, incl. all-zero and all-ones keys/fields); VERIFY accepts
the right tag and rejects a flipped tag bit, a flipped handle bit and the right tag under another key;
NO_KEY before loading and after a wipe; BAD_OP for ops 0 and 3; after CAP failed verifies VERIFY
answers LIMITED even for the right tag while BUILD still works, and one refill period re-opens one
attempt.

### Mutation tests

| Mutation | FAIL lines |
|---|---|
| wrong tag slice (`tag_out[79:32]`) | 35 |
| header length byte 0x0B → 0x0A | 35 |
| hub_id / pad nibble order swapped | 33 |
| VERIFY always ok | 38 |
| rate limit removed | 2 |
| wipe ignored | 5 |

## Post-synthesis (xc7z010clg400-1, 10 ns clock, `synth_1` only)

| Slice LUTs | Slice Registers | BRAM | DSP | WNS @100 MHz |
|---|---|---|---|---|
| **1325 (7.53 %)** | **817 (2.32 %)** | **0** | **0** | **+3.821 ns — met** |

Includes `ascon128_aead` (1422 LUT standalone; the unused plaintext/ciphertext path is trimmed).
Script: `results/hw_core_synth_2026-10-20_tag_engine/core_synth.tcl`.

## Caveats

- The token bucket counts **checks**. The software decoder makes up to 1125 tag checks per image
  (`docs/improvement_review_2026-10-20.md` A3); if the PS geometry search calls VERIFY per
  hypothesis, CAP/REFILL must be sized per image, or the bucket must be fed per image by the PS.
- The MAC is Ascon-128 **v1.2**, not NIST SP 800-232 Ascon-AEAD128 (review A6).
- Not connected to the AXI mailbox; no bitstream.
