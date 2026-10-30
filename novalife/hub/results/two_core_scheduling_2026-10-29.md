# Two-core job lanes, 921600 baud link, doctor priority and the scheduling trace (2026-10-29/30, hardware)

> **Board measurements.** EDGE Zynq XC7Z010, FreeRTOS V10.6.1 on CPU0, bare-metal verify worker on CPU1,
> ESP32 (ESP-AT) on UART1, Supabase project `rtsduiqbgdiyygczivbl`. Times are end to end: job row
> `created_at` to `finished_at` in `hub_jobs`, plus the per-phase times the board writes into each job's
> `result` (`t_ms.dl`, `t_ms.cpu`, `t_ms.up`, `exec.cpu`, `link`). Same marked/unmarked scan files in each
> before/after pair. The `hub_jobs` rows were wiped on 2026-10-30 (team data reset); the numbers below were
> read from them before that.

## 1. ESP32 link: 115200 baud polled -> 921600 baud with an interrupt-driven ring

UART1 RX now raises an interrupt (RX trigger 32, RX timeout 10) into a 32 KB ring; divisors CD = 18, BDIV = 5
give 100 MHz / (18 x 6) = 925,926 baud (0.47 % above 921600). `AT+UART_CUR=921600,8,1,0,0`, 115200 fallback.

| Job (one core) | 115200, polled | 921600, IRQ ring |
|---|---|---|
| mark_image | 31.9 s | 11.5 s (download 2.4 s, compute 3.8 s, upload 4.3 s) |
| verify_image | 22.9 s | 11.1 s (download 3.1 s, compute 6.4 s) |

Link counters after the runs: 0 RX overruns, 0 ring drops.

## 2. Handles

`hg_next_handle()` (firmware/src/handle_gen.c): Ascon-AEAD128 keyed PRF over a chain value, a counter, the
global timer, an interrupt-timing pool and the job UUID; output = first 64 bits. PC test: 200,000 handles,
no duplicate; the C output equals the Python `ascon_aead_encrypt` reference for the same input
(`35689bc1ce653b00`). Before: every board handle began `dc1b77ae0bf3...` (a fixed-seed PRNG).

## 3. Priority (migration 015) and lanes (migration 016)

- A trigger sets `priority` from the user's role (doctor 2, others 0). An insert that asked for priority 99
  was stored as 0.
- The board scores `priority x 60 + age_s` and picks the best job for a free lane. With 2 jobs queued, the
  doctor's job was picked over an older lab job; a lab job that had waited 150 s was picked over a fresh
  doctor job (aging).
- Verify runs on CPU1, mark on CPU0; the server allows one running job per lane.

| Doctor verify submitted while a lab mark runs | Doctor verify, end to end |
|---|---|
| two cores, no hold (JTAG load) | 9.0 s |
| two cores + 4 s hold of other link operations while a doctor job computes (JTAG load) | 4.9 s (download 2.84 s, CPU1 1.27 s) |
| same, booted from SD (no JTAG) | 4.7 s (download 3.11 s, CPU1 1.27 s); the lab mark took 16.3 s |

CPU1 verify alone: compute 1.2-1.5 s, end to end 3.7-3.8 s, correct pass/fail verdicts.

## 4. Scheduling trace (trace_viewer/)

- Rings in non-cacheable DDR at 0x1FF0_0000; xsdb `mrd -force` reads them without halting a CPU:
  1.4 ms per 8-word read, ~640 KB/s bulk (102 ms per 16384 words).
- First run recorded every `vTaskSwitchContext`: 3,315,005 events in 207 s (about 16,000/s), of which
  99.6 % were `espw -> espw` (the scheduler picking the same task again on a yield). The JSON-lines
  recording was 135 MB and the reader lost events 145 times (ring overflow). Filtering same-task
  reschedules leaves 39,627 events, 0.79 MB as 20-byte binary records.
- Real task switches: 162 and 193 per second in 60 s windows of the first run, 90 per second in the window
  below.  Replay of `trace_20261029_152227.bin` (17 min): in a 24 s window
  holding a lab mark and a doctor verify, CPU0 was busy 84.9 % (espw 73.7 %, img_work 11.2 %) and the
  doctor job `7beaa78c` took 4.747 s from claim to idle, of which 0.896 s compute on CPU1.

## 5. Open

- SD power-up: the FSBL DDR sanity check (`DDRInitCheck`) failed on 4 power-ups on 2026-10-29 and passed
  on the others; reset reason POR every time. Not caused by the image contents (the check runs before any
  partition is read); power supply suspected, not measured.
- CPU0 is compiled at -O0.

## Reproduce

Firmware: `hub/firmware` (CPU0 Vitis app, CPU1 `core1/Makefile`, `boot/boot.bif`). Trace:
`python3 trace_viewer/server.py` (live) or `--replay trace_viewer/recordings/<file>.bin`.
