# NovaLife Hub Cloud Worker & ESP32 Outbound TLS Evaluation (2026-10-22)

## 1. Executive Summary

This document records the measured performance, stability, and concurrency behavior of the FreeRTOS `cloud_worker` executing on the Zynq-7000 Cortex-A9, communicating with Supabase PostgREST endpoints via an ESP32-WROOM-32 Wi-Fi modem over UART1 (115200 baud).

All reported data reflects real hardware measurements, live UART traces, and database rows in Supabase project `rtsduiqbgdiyygczivbl`.

---

## 2. Root Cause Analysis & Firmware Fixes

### 2.1 The 120-Second Concurrency Stall
In initial two-user concurrency testing, the first job claimed and completed immediately, but the second job waited for ~2m17s (e.g., job `4da33aab`, created 11:18:28, claimed 11:20:46, `attempts = 2`). The board did not take back-to-back jobs because it stalled until the Postgres 120s watchdog reset the job to `queued`.

### 2.2 Root Causes Identified
1. **Passive Receive Mode Notification Suppression**: In ESP-AT passive receive mode (`AT+CIPRECVTYPE=4,1`), `+IPD` notifications are suppressed once delivered until the socket buffer is fully drained. Replies frequently sat unread in the ESP32 internal buffer until the 6-second timeout expired.
2. **Buffer Flush in `esp_cipsend`**: When sending data and searching for `SEND OK`, earlier code dropped the ring buffer up to the index of `SEND OK`. Any incoming `+IPD` frames arriving between transmission and `SEND OK` were purged.
3. **Silent Cloudflare Socket Teardown**: Cloudflare edge proxies emit TCP FIN on idle keep-alive or specific RPC replies. The worker checked `s_cloud_link4_connected` without checking for `4,CLOSED`, leading to `esp_cipsend` failures without reconnect/retry.
4. **Stack Margin**: The FreeRTOS network task stack (8 KB) was marginal for 4-6 KB JSON request/response structures. Increased to 16 KB (4096 words).

### 2.3 Applied Fixes
- Implemented Content-Length and chunked-terminator aware response reader (`esp_link4_http_recv`).
- Replaced passive receive polling with active receive mode (`AT+CIPRECVTYPE=4,0` / `esp_link4_take_frames`) reducing claim delivery latency from 3.5–6.6 s down to 0.51 s.
- Added link closure purging (`esp_link4_purge_all_closed`) and reconnect/retry loop with exponential backoff.
- Added persistent undelivered completion queue (`s_pending_*`) so completed jobs are guaranteed delivered before claiming new tasks.
- Added `esp_reset_and_reinit()` on every 3rd consecutive `CIPSTART` failure (`AT+RST`, wait for `GOT IP`, reconfigure `CWMODE`, `CIPMUX`, and `:8080` server).

---

## 3. Measured Link & TLS Performance

| Metric | Measured Value | Measurement Method |
|---|---|---|
| **ESP32 Outbound TLS Handshake** | **4.06 s** | ESP-AT `AT+CIPSTART=4,"SSL"` to Supabase:443 with GlobalSign Root CA validation |
| **PC Outbound TLS Handshake** | **0.137 s** | Python `ssl.create_default_context()` on local PC |
| **Idle Link Survival** | **> 120 s** | Tested at 5s, 10s, 20s, 30s, 60s, 90s, 120s idle intervals. Link remains open; subsequent request latency is 0.09–0.38 s |
| **100 KB Download (GET)** | **14.03 s (8.14 KB/s)** | Passive chunked transfer over UART1 @ 115200 baud; 0% loss |
| **100 KB Upload (POST)** | **10.24 s (9.77 KB/s)** | 2048-byte segmented CIPSEND over UART1 @ 115200 baud; 0% loss |
| **FreeRTOS Free Heap** | **17,816 bytes** | `xPortGetFreeHeapSize()` after network task startup (plus 64 MB DDR heap) |
| **Hardware PL Tag Verification** | **119 cycles (1.19 µs)** | Hardware mailbox `te_ctrl` execution @ 100 MHz |

---

## 4. Concurrent Queue Verification (6 Jobs Back-to-Back)

### 4.1 Phase 1: Passive Receive Baseline (`AT+CIPRECVTYPE=4,1`)
At `2026-10-22 13:34:08 UTC`, 6 verification requests were submitted simultaneously with passive receive mode.
- **Total Execution Time**: **21.50 seconds** (average 3.58 s per job).
- **Claim read latency**: ~4.4 s.
- **Attempts**: 1 for every job.
- **Result**: Queue resolved cleanly, but passive polling introduced ~3.5–4.5 s latency per claim.

### 4.2 Phase 2: Active Receive Breakthrough (`AT+CIPRECVTYPE=4,0` + `esp_link4_take_frames`)
At `2026-10-22 14:13:39 UTC`, the identical 6-job concurrent batch was re-tested under active receive mode.

```sql
SELECT job_id, auth_uid, kind, status, device_id, attempts, created_at, claimed_at, finished_at,
       claim_lag_s, run_time_s, total_time_s, verdict, pl_cycles
FROM public.hub_jobs WHERE created_at >= '2026-10-22 14:13:00+00'
ORDER BY created_at ASC;
```

**Measured Database Records (`public.hub_jobs`):**

| Job ID | Role | Handle Tested | Created At (UTC) | Claimed At (UTC) | Finished At (UTC) | Claim Lag | Run Time | Total Time | Verdict | Attempts | PL Cycles |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `ebeec8a5` | `doctor_001` | `0x8877665544332211` | 14:13:39.161 | 14:13:39.901 | 14:13:40.459 | 0.740 s | 0.558 s | 1.298 s | `revoked` | 1 | 119 |
| `0b73ca02` | `patient_001` | `0x1122334455667788` | 14:13:39.643 | 14:13:41.252 | 14:13:41.678 | 1.609 s | 0.426 s | 2.035 s | `pass` | 1 | 119 |
| `f097feb1` | `lab_tech_001` | `0xaabbccddeeff0011` | 14:13:39.842 | 14:13:42.061 | 14:13:42.489 | 2.219 s | 0.428 s | 2.647 s | `unknown` | 1 | 119 |
| `7d6b98e9` | `doctor_001` | `0x1122334455667788` | 14:13:40.049 | 14:13:42.889 | 14:13:43.321 | 2.841 s | 0.432 s | 3.272 s | `pass` | 1 | 119 |
| `d309ccdd` | `patient_001` | Mutated tag | 14:13:40.481 | 14:13:43.700 | 14:13:44.135 | 3.219 s | 0.436 s | 3.655 s | `fail` | 1 | 119 |
| `da56e54c` | `lab_tech_001` | `0x8877665544332211` | 14:13:40.687 | 14:13:44.548 | 14:13:44.966 | 3.861 s | 0.419 s | 4.279 s | `revoked` | 1 | 119 |

- **Total Batch Execution Time**: **5.80 seconds** for all 6 jobs (**3.7× speedup** over passive mode).
- **Execution Run Time per Job**: **0.42 s – 0.55 s** (vs 2.47 s – 4.58 s in passive mode).
- **Hardware Telemetry (`mklog.sh`)**:
  - `claim send`: 80 ms, `claim recv`: **300–320 ms** (meeting the < 1.0 s target).
  - `complete send`: 90–100 ms, `complete recv`: **160–240 ms**.
  - `PL execution`: 119 cycles (1.19 µs).
- **Attempts**: Exactly **1** for all 6 jobs.
- **Queue Order**: Exact First-Come-First-Served (FCFS) matching database insertion order.

---

## 5. Handle Verification Correctness Matrix

| Handle | Tag | Status in DB | Expected | Measured Result | Audit Log |
|---|---|---|---|---|---|
| `0x1122334455667788` | `0xf5f32aa79861` | Active (`tag_handles`) | `pass` | `pass` (tag genuine, handle active) | Written |
| `0x8877665544332211` | `0x7f61f0b00e90` | Revoked (`tag_handles.revoked_at` set) | `revoked` | `revoked` (tag genuine, handle revoked) | Written |
| `0xaabbccddeeff0011` | `0x0cf11b924974` | Not present in DB | `unknown` | `unknown` (tag genuine, handle unknown) | Written |
| `0x1122334455667788` | `0xdeadbeef1234` | Altered / forged tag | `fail` | `fail` (tag forged / PL tag mismatch) | Written |

---

## 6. Manual Bench Jobs & Diagnostics Note

During debugging and AT bridge profiling sessions, the following manual entries were recorded:
- Job `63765dfc-d345-4ad3-a785-e81d1ee76624`: Created 13:37:31 UTC, manually marked failed at 13:38:15 UTC (`"bench test (manual claim through bridge)"`).
- Job `c6aa60c0-64af-4c69-b46c-c99b88761062`: Created 13:38:15 UTC, claimed through the bridge during active timing benchmarks, then re-queued after the 120s watchdog and finished at 13:45:35 UTC (`attempts = 2`, `pass`).
