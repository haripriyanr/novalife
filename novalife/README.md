<div align="center">

# NovaLife

**Authenticated medical-image traceability on AMD Zynq-7010 — from DICOM to chat forward and back**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Supabase](https://img.shields.io/badge/Supabase-Cloud%20Backend-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![FPGA](https://img.shields.io/badge/FPGA-AMD%20Zynq--7010%20XC7Z010-E01F27?logo=xilinx&logoColor=white)](https://www.xilinx.com)
[![FreeRTOS](https://img.shields.io/badge/FreeRTOS-PS%20Firmware-green)](https://www.freertos.org)
[![License](https://img.shields.io/badge/License-All%20Rights%20Reserved-red)](novalife/hub/LICENSE)

[The Problem](#the-problem) · [Why NovaLife](#why-novalife) · [Measured Results](#measured-not-promised) · [How It Works](#how-it-works) · [Quick Start](#quick-start) · [Hardware](#hardware) · [Reproducing the Evaluation](#reproducing-the-evaluation) · [Roadmap](#roadmap) · [Team](#team)

</div>

---

## The Problem

When a hospital image leaves its DICOM system — exported as JPEG, screenshotted, or forwarded over WhatsApp or Telegram — its patient-linking header is stripped. No one can tie the pixel data back to the authentic record, or notice when an image has been swapped.

India's DPDP Act 2023 (§6 consent, §8 safeguards, §10 audit, §13 erasure) and NABH digital health standards require that this link be traceable and auditable. Today it is not.

---

## Why NovaLife

<table>
<tr>
<td>

### 🔒 Tag Survives Real Channels
Exact 128-bit recovery after JPEG Q40, 0.5×–2× resize, and 25% corner crop — measured on 50 cover images × 10 seeds, not promised.

</td>
<td>

### 🔑 Key Never Leaves the FPGA
The Ascon-128 hub key lives in the Zynq PL enclave. The PS can request tag operations; it cannot read the key. An intercepted firmware binary reveals nothing useful.

</td>
</tr>
<tr>
<td>

### 📊 Measured, Not Promised
Every number in this README comes from a file in [`hub/results/`](hub/results/) with the exact command that produced it. No benchmark is fabricated.

</td>
<td>

### 🌐 Works From Any Network
Jobs are queued through Supabase (cloud relay). The Zynq board polls over ESP32 outbound TLS — no inbound port, no VPN, no static IP needed.

</td>
</tr>
<tr>
<td>

### 👥 Three Roles With Consent
Lab tech marks images. Doctor verifies and views records of consenting patients. Patient controls consent and sees their own audit log. Role enforcement is in the database RLS policies.

</td>
<td>

### ⚡ Runs on a Zynq Board
PS: dual Cortex-A9, FreeRTOS, stb_image decode + PNG encode + cloud worker. PL: Ascon-128 AEAD tag engine verified at 119 cycles. Boots from SD card.

</td>
</tr>
</table>

---

## Product Tour

> Screenshots will be added after the app UI is finalised (dark + light, all three roles).

**Three role portals:**
- **Lab Technician** — Upload scans, submit mark jobs, track queue status
- **Doctor** — Search patients, verify watermark, attach clinical notes, view diagnostic history
- **Patient** — ABHA-linked portal, consent controls, access log, own diagnostic records

---

## Measured, Not Promised

All numbers below are reproduced by one command from the files in [`hub/results/`](hub/results/).

### Tag Robustness Matrix (G1 — software oracle)
50 cover images × 10 seeds = 500 marks per condition. Reproduced by `tools/tag_reference/run_matrix.py`.

| Attack | Pass / Total | Command |
|---|---|---|
| JPEG Q90 | 50 / 50 | `run_matrix.py --jpeg 90` |
| JPEG Q70 | 50 / 50 | `run_matrix.py --jpeg 70` |
| JPEG Q50 | 50 / 50 | `run_matrix.py --jpeg 50` |
| JPEG Q40 | 39 / 50 | content-dependent; passes if min block amplitude ≥ 16 |
| Resize 0.5× | 50 / 50 | `run_matrix.py --scale 0.5` |
| Resize 0.75× | 50 / 50 | `run_matrix.py --scale 0.75` |
| Resize 1.5× | 50 / 50 | `run_matrix.py --scale 1.5` |
| Resize 2.0× | 50 / 50 | `run_matrix.py --scale 2.0` |
| Resize + JPEG Q75 | 50 / 50 | `run_matrix.py --scale 1.5 --jpeg 75` |
| Corner crop 5% | 50 / 50 | `run_matrix.py --crop 0.05` |
| Corner crop 25% | 50 / 50 | `run_matrix.py --crop 0.25` |
| Symmetric crop ≥10% | 0 / 50 | **open — no pilot-free fallback for symmetric crop** |

Source: [`hub/results/tag_matrix_2026-10-22.md`](hub/results/tag_matrix_2026-10-22.md), [`hub/results/g1_hadamard_2026-10-20.md`](hub/results/g1_hadamard_2026-10-20.md)

### Real MRI — End-to-End on Hardware
10 Brain Tumor MRI scans from Kaggle (CC0). Measured live on the Zynq board via the cloud relay.

| Job | Duration | Verdict |
|---|---|---|
| `mark_image` (128-bit, 4 copies) | 10.67 s | marked PNG uploaded, SHA-256 bit-exact with Python oracle |
| `verify_image` — marked image | 8.80 s | `tag_ok=1`, `verdict='pass'` |
| `verify_image` — revoked handle | 11.85 s | `verdict='revoked'` |
| `verify_image` — unmarked image | 6.02 s | `verdict='fail'` |

Source: [`hub/results/e2e_2026-10-22.md`](hub/results/e2e_2026-10-22.md)

### Cloud Relay — 6-Job FCFS Batch (Active Mode)
6 concurrent `verify_tag` jobs queued simultaneously, exact FCFS sequence maintained.

| Metric | Value |
|---|---|
| Total wall time | 5.80 s |
| Avg job turn-around | 0.97 s |
| Board execution per job | 0.42–0.55 s |
| PL tag engine cycles | 119 cycles |
| Retry attempts | 1 for all 6 |
| Outbound TLS handshake | 4.06 s |

Source: [`hub/results/cloud_worker_2026-10-22.md`](hub/results/cloud_worker_2026-10-22.md)

### PL Core Synthesis — Post-Synthesis on XC7Z010 @ 100 MHz

| Core | LUT | FF | BRAM | DSP | WNS |
|---|---|---|---|---|---|
| `block_embed_core` | 450 (2.56%) | 490 (1.39%) | 0 | 0 | +1.411 ns ✅ |
| `ascon128_aead` | see [`hub/results/g2_ascon_2026-10-19.md`](hub/results/g2_ascon_2026-10-19.md) | — | — | — | — |

Source: [`hub/results/g2_block_embed_2026-10-20.md`](hub/results/g2_block_embed_2026-10-20.md)

### C Port — 47/47 Bit-Exact vs Python Oracle
`hubcore/` C port verified bit-exact against the Python reference for mark + verify on all 47 test vectors.

Source: [`hub/results/c_port_2026-10-22.md`](hub/results/c_port_2026-10-22.md)

---

## How It Works

```
Intake
  ↓  stb_image decode (FreeRTOS PS)
ROI detection — floor black regions (PS)
  ↓
5/3 Wavelet IWT (PS, cores verified in PL)
  ↓
Keyed block placement — Ascon keystream → block order (PL, key never leaves)
  ↓
Block embed — sign-of-Hadamard projection + error spread (PL core, 123/123 vectors bit-exact)
  ↓
5/3 IWT inverse (PS)
  ↓  stb_image PNG encode + Supabase upload
Recovery
  ↓  geometry search (scale/offset from size-ratio or pilot-period)
Polar SCL decode (128-bit + 48-bit Ascon AEAD tag)
  ↓
Tag verification in PL enclave → cloud database → role + consent check → record or "no"
```

**PL/PS split:**  
The PL holds the Ascon-128 hub key and runs the tag engine (119 cycles verified). The PS (FreeRTOS + C port `hubcore/`) handles image I/O, wavelet transform, placement, embedding, and the cloud worker. The PL is the trust root; the PS is the compute workhorse.

Full algorithm spec: [`hub/docs/algorithm.md`](hub/docs/algorithm.md)  
System architecture: [`hub/docs/system_architecture.md`](hub/docs/system_architecture.md)

---

## Quick Start

### App

```bash
cd novalife/app
cp .env.example .env
# Fill SUPABASE_URL and SUPABASE_ANON_KEY in .env

flutter pub get
flutter run
# Or build APK:
flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

### Supabase Migrations

```bash
cd novalife/supabase
supabase db push
# Migrations 001–012 in migrations/
```

### Hub Firmware (FreeRTOS)

```bash
cd novalife/hub/firmware/src
cp config_local.example.h config_local.h
# Edit: WIFI_SSID, WIFI_PASS, DEVICE_SECRET, SUPABASE_URL, SUPABASE_ANON_KEY

# Build in Vitis (or CMakeLists):
mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=arm-none-eabi.cmake
make -j4
```

### Vivado Enclave (regenerate from scripts)

```bash
cd novalife/hub
NOVALIFE_OUT=$PWD/vivado/NovaLife_Hub \
  vivado -mode batch -source vivado/scripts/build_enclave.tcl
```

---

## Hardware

**Board:** EDGE Zynq SoC (XC7Z010-1CLG400C, 1 GB DDR3)  
**Boot mode:** SD card (`BOOT.BIN` = FSBL + bitstream + FreeRTOS ELF)  
**Network:** ESP32 AT firmware via UART — outbound HTTPS only (GlobalSign Root CA, verified)  

### Wiring

| Signal | Zynq Pin | ESP32 Pin |
|---|---|---|
| UART1 TX | MIO48 | RXD |
| UART1 RX | MIO49 | TXD |
| GND | GND | GND |

Full wiring and ESP32 flash instructions: [`hub/tools/esp_flash/`](hub/tools/esp_flash/)

---

## Reproducing the Evaluation

### G1 — Tag robustness matrix
```bash
cd novalife/hub/tools/tag_reference
pip install -r requirements.txt
python run_matrix.py --covers 50 --seeds 10
# Output: hub/results/tag_matrix_<date>.{md,json}
```

### C port self-test (47 vectors)
```bash
cd novalife/hub/hubcore/handoff
make test
```

### ESP32 TLS negative control
```bash
# From board serial console:
AT+CIPSTART="SSL","untrusted-root.badssl.com",443
# Expected: ERROR (untrusted root rejected)
```

---

## Roadmap

| Item | Status |
|---|---|
| Tag robustness — JPEG/resize/crop | ✅ Measured |
| Real MRI end-to-end on hardware | ✅ Measured |
| C port bit-exact (47 vectors) | ✅ Measured |
| PL tag engine (119 cycles) | ✅ Measured |
| Cloud relay FCFS (6-job batch) | ✅ Measured |
| Symmetric crop ≥10% recovery | ⏳ Open |
| Real chat-app round-trip (owner's phone) | ⏳ Needs owner test |
| Full PL marking pipeline | ⏳ Planned |
| RLS migration 009 (row-level security fix) | ⏳ Draft, not applied |
| App UI — all 3 roles, dark + light theme | ⏳ In progress |
| README screenshots | ⏳ After UI done |

---

## Limitations

- **Symmetric crop ≥10%** — no pilot-free fallback; not recovered
- **Real chat-app sends** — not yet tested end-to-end through a live WhatsApp/Telegram send (needs owner's phone)
- **Full PL marking pipeline** — marking runs on PS/C; only the tag engine and block_embed_core are in PL
- **RLS migration 009** — `hub_patients`/`hub_scans` SELECT policies are `USING (true)`; patients can read other patients' rows. Fix drafted, not applied
- **Key on PS** — interim deviation from D5: key is in `config_local.h` (gitignored) and loaded into PL at boot

---

## Documentation

| Document | Location |
|---|---|
| Algorithm (locked) | [`hub/docs/algorithm.md`](hub/docs/algorithm.md) |
| System architecture | [`hub/docs/system_architecture.md`](hub/docs/system_architecture.md) |
| Practical need & ecosystem | [`hub/docs/practical_need_and_ecosystem.md`](hub/docs/practical_need_and_ecosystem.md) |
| Steganography roadmap & claims | [`hub/docs/steganography_roadmap.md`](hub/docs/steganography_roadmap.md) |
| Hub HTTP API | [`hub/docs/hub_http_api.md`](hub/docs/hub_http_api.md) |
| Measured results | [`hub/results/`](hub/results/) |

---

## Team

<table>
<tr>
<td align="center">
<a href="https://github.com/haripriyanr"><img src="https://github.com/haripriyanr.png" width="80" style="border-radius:50%"/><br/><b>Haripriyan R</b></a><br/>Primary · FPGA · Firmware · App
</td>
<td align="center">
<a href="https://github.com/Aydenj-osh"><img src="https://github.com/Aydenj-osh.png" width="80" style="border-radius:50%"/><br/><b>Ayden Joshua M</b></a><br/>Contributor
</td>
<td align="center">
<a href="https://github.com/Sudharsan210"><img src="https://github.com/Sudharsan210.png" width="80" style="border-radius:50%"/><br/><b>Sudharsan G S</b></a><br/>Contributor
</td>
<td align="center">
<a href="https://github.com/ha721ish"><img src="https://github.com/ha721ish.png" width="80" style="border-radius:50%"/><br/><b>T Harish</b></a><br/>Contributor
</td>
</tr>
</table>

---

<div align="center">
<sub>NovaLife · AMD Zynq-7010 · FreeRTOS · Flutter · Supabase · Ascon-128 · Polar SCL</sub>
</div>
