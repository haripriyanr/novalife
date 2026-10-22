# G4/G5 — first bitstream with our logic: the tag engine on the board (2026-10-20)

> **Superseded 2026-10-20:** measured with the Ascon-128 **v1.2** core. The cipher moved to NIST SP 800-232
> Ascon-AEAD128 the same day — see `results/g2_ascon_sp800_2026-10-20.md`. Kept as the record of that run.


**Level of evidence:** **post-place-and-route** reports and a **board run** on the XC7Z010
(EdgeZ7_10, Digilent cable `210319A288EEA`), driven from the Cortex-A9 over JTAG. Not FreeRTOS-driven
yet, not booted from SD/QSPI.

## What is in the bitstream

`vivado/scripts/build_enclave.tcl`: PS7 (EdgeZ7_10 board preset, as `firmware/vivado_ps`), UART1 on
EMIO to the ESP32 (R19/T19), M_AXI_GP0 → AXI SmartConnect → `enclave_axi` at **0x4000_0000 (4 KB)**.
`enclave_axi` = AXI4-Lite register block (superset of `firmware/src/mailbox.h`) around `tag_engine`
(BUILD/VERIFY_TAG, write-only key, failed-verify token bucket CAP 16 / one per second) around
`ascon128_aead`. Built with **ALLOW_AXI_KEY = 1** — a bring-up deviation from D5 (the key can be
written over AXI); a production bitstream must set it to 0.

Bitstream SHA-256 `08ebf87609c3db1fafa9352aa4834709e0a3dda0ed78f139bd84e3589aaaf864`
(`vivado/build_enclave/` is gitignored; rebuild with the command below).

## Post-place-and-route (Vivado 2026.1, xc7z010clg400-1)

| | Slice LUTs | Slice Regs | BRAM | DSP | IOB |
|---|---|---|---|---|---|
| **whole design** | **1915 (10.88 %)** | **1787 (5.08 %)** | 0 | 0 | 2 |
| `enclave_0` (enclave_axi) | 1538 | 1328 | 0 | 0 | |
| └ `tag_engine` (incl. ascon128_aead) | 1328 | 817 | 0 | 0 | |

| Timing @ FCLK0 100 MHz (10 ns) | |
|---|---|
| WNS (setup) | **+2.344 ns — met** (setup-limited Fmax ≈ 1 / (10 − 2.344) ns ≈ 130 MHz) |
| WHS (hold) | +0.035 ns — met |
| failing endpoints | 0 of 4949 |
| critical warnings in the build | 0 |

Power (`report_power`, **vectorless estimate, not measured**): 1.221 W total on-chip, 1.105 W dynamic
(dominated by the PS7), 0.116 W device static.

Reports: `results/hw_enclave_2026-10-20/post_route_{util,util_hier,timing,power}.txt`.

## Board run

`xsdb vivado/scripts/board_tag_test.tcl` — `rst -system`, program the bitstream, `ps7_init` +
`ps7_post_config` from the XSA, then the same register sequence as the simulation testbench
(`vivado/ip_repo/enclave_axi/enclave_axi_tb.v`) over every vector in
`tools/tag_reference/vectors/te_*.mem` (== `tag_block.compute_tag`). Log:
`results/hw_enclave_2026-10-20/board_tag_test.log`.

```
devcfg INT_STS before fpga 0xa802000a, after 0xf802000f (bit 2 = PCFG_DONE)
STATUS after init: 0x4e4c1001
BUILD_TAG cycles (PL counter, 100 MHz FCLK0): 129 129 ... 129   (16 vectors)
VERIFY_TAG cycles: 129 129 ... 129
BOARD_TAG_TEST PASS (16 vectors on the board)        42 checks, 0 failures
```

Measured on the board:

- PL present: STATUS magic `0x4E4C`, READY, 16 tokens; no key after reset.
- BUILD/VERIFY without a key → NO_KEY.
- **BUILD_TAG bit-exact to the Python reference on all 16 vectors** (incl. all-zero and all-ones
  key/fields); **VERIFY accepts the right tag on all 16**, rejects a flipped tag bit (3 tried).
- Wipe → key not loaded; the key window reads 0.
- **Latency: 129 PL cycles per BUILD_TAG or VERIFY_TAG** (counted by the PL itself from the CMD write
  to DONE), FCLK0 configured at 99.999893 MHz → **≈ 1.29 µs**. Excludes the AXI round trips and
  software; a JTAG-driven `mrd`/`mwr` is milliseconds, so end-to-end time from xsdb is meaningless and
  not reported.
- devcfg `INT_STS` bit 2 (PCFG_DONE) goes 0 → 1 on programming: the firmware's new PL-present probe
  (`mailbox_pl_present`, checks it before touching the AXI window) uses the right bit.

## FreeRTOS driving the enclave (same bitstream, same day)

`xsdb vivado/scripts/board_fw_load.tcl testkey` programs the bitstream, loads **test vector 0's key**
(the published demo key, through the AXI admin window — the PL-wired-console stand-in) and starts the
FreeRTOS firmware (`firmware/src`, 171,348 B text). Requests come from this PC over the LAN through the
ESP32 Wi-Fi path (192.168.31.86:8080). Log: `results/hw_enclave_2026-10-20/board_fw_http.log`.

| Request (all served by FreeRTOS → `mailbox_verify_tag` → PL) | Result |
|---|---|
| `GET /status` | `"mailbox":"axi","pl":"present","key":"loaded","tokens":16` — live, no longer hard-coded |
| VERIFY vector 0, right tag | **`ok:true`**, PL result `0x100`, 129 PL cycles |
| VERIFY, tag bit 0 flipped | `ok:false` (VERIFY_FAIL), 129 cycles |
| VERIFY, handle bit 0 flipped | `ok:false`, 129 cycles |
| 32 paced failed verifies | the 32nd answers **LIMITED** (`pl_result 0x2`, no MAC computed); `tokens 0` |
| right tag while limited | **refused** (LIMITED) |
| right tag 1.5 s later | **`ok:true`** (refilled) |
| HTTP round trip, 10 right-tag verifies | min 0.017 s, **median 0.056 s**, max 0.065 s (Wi-Fi + ESP32 AT path; the PL part is ~1.3 µs) |
| `POST /embed` | **501** `MARK_IMAGE not implemented in the PL` (it used to echo the cover back as if marked) |

Defects found and fixed on the way: the request-target buffer was 64 bytes, so a full
`/enclave/verify` query (68 bytes) was **silently truncated** and the right tag was rejected; it is now
160 bytes and an overlong target is refused instead of truncated. The reply echoes the parsed fields
so a mismatch is visible. Back-to-back requests with no pacing lost some replies on the ESP32 path
(empty responses); paced at ~0.2 s, 0 of 35 were lost — a transport limit, not measured further.

## Not done / caveats

- No UART log captured (the console path still goes to the ESP32 EMIO, see the 2026-10-20 bring-up
  note); the evidence is the HTTP replies above.
- There is deliberately **no BUILD_TAG over HTTP** (a network BUILD oracle would mint valid tags for
  any handle); BUILD is reachable only from the PS firmware API (`mailbox_build_tag`), not exercised
  from FreeRTOS yet.
- **BOOT.BIN built, not booted.** `firmware/boot/BOOT.BIN` (2,360,548 B, SHA-256
  `74cae08fcd11133dea07e81d2b5d3adcf97c5ad898ef774807b18b5dd841f0b1`) = platform FSBL + this
  bitstream + this firmware (`firmware/boot/boot.bif`; `bootgen -read` shows the three partitions,
  ELF exec 0x0010_0000). The platform FSBL is valid for this design: its `ps7_init.tcl` is identical to
  the enclave XSA's (0 diff lines). **Not tested:** it needs the SD card moved to the PC (or a QSPI
  write, not done unattended). After an SD boot no key is loaded, so the enclave answers NO_KEY (D5).
- MARK_IMAGE / EXTRACT_TAG are not in the PL (the QIM embedder needs a fixed-point reference first,
  `docs/improvement_review_2026-10-20.md` A8). The enclave flags them unsupported.
- The cipher is Ascon-128 v1.2, not SP 800-232 (review A6).

## Reproduce

```
cd vivado && mkdir -p build_enclave && cd build_enclave && vivado -mode batch -source ../scripts/build_enclave.tcl
cd build_enclave && mkdir -p xsa && cd xsa && unzip -o ../novalife_enclave.xsa
xsdb vivado/scripts/board_tag_test.tcl          # from novalife_hub/, board on JTAG
```
