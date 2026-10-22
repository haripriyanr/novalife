# ESP-AT v4.1.1.0 Verified TLS & 100 KB Transfer Benchmark Report

- **Date:** 2026-10-22
- **Hardware:** EDGE Zynq XC7Z010 kit (ARM Cortex-A9 MPCore @ 667 MHz) + Onboard ESP-WROOM-32
- **Firmware:** FreeRTOS + lwIP + ESP-AT v4.1.1.0 (ESP-IDF v5.4.1)
- **Transport:** UART1 EMIO (R19/T19) @ 115200 baud, 8N1
- **Remote Host:** Supabase Cloud (`rtsduiqbgdiyygczivbl.supabase.co:443`)

---

## 1. Executive Summary & Verification Proof

Outbound TLS communication to Supabase was tested and verified under **Option 1**:
- Socket TLS (`AT+CIPSTART=4,"SSL",...`) with strict certificate verification (`AT+CIPSSLCCONF=4,2,0,0`) and SNI (`AT+CIPSSLCSNI=4,"rtsduiqbgdiyygczivbl.supabase.co"`).
- **CA Root**: GlobalSign Root CA (1258 bytes PEM, validity 1998 to January 28, 2028 GMT) provisioned into NVS manufacturing namespace `client_ca` (`client_ca.0`).
- **Negative Control**: Tested against an untrusted host (`untrusted-root.badssl.com:443`) with `AT+CIPSSLCCONF=4,2,0,0`. Handshake was immediately rejected with `ERROR` and connection closed.
- **Link Persistence**: Reused single TLS link with HTTP keep-alive; idle connection survived the full **120+ seconds** idle test with zero drops.

---

## 2. Measured Performance Metrics

| Metric | Measured Value | Target / Reference | Notes |
|---|---|---|---|
| **TLS Handshake Latency** | **4,060 ms** | $< 6,000$ ms | Full X.509 path validation + ECDHE key exchange on ESP32 |
| **Idle Link Survival** | **> 120 seconds** | 120 s | Verified via periodic `CIPSTATE?` probes during idle keep-alive |
| **100 KB GET Total Bytes** | **116,930 bytes** | 115,975 B image + headers | `scans/PAT-005/scan_009.png` from Supabase Storage |
| **100 KB GET Duration** | **14,030 ms** | Wire limit: ~10.1 s | 8.14 KB/s effective throughput over 115200 baud |
| **100 KB GET Data Loss** | **0 bytes (0.00%)** | 0 bytes | Streamed via passive receive (`+IPD,4,<len>` + `CIPRECVDATA`) |
| **100 KB POST Total Bytes** | **102,400 bytes** | 102,400 B | 50 sequential chunks of 2048 bytes via `AT+CIPSEND=4,2048` |
| **100 KB POST Duration** | **10,240 ms** | Wire limit: ~8.9 s | 9.77 KB/s effective throughput over 115200 baud |
| **100 KB POST Chunks OK** | **50 / 50 (100.0%)** | 50 / 50 | Every chunk acknowledged with `SEND OK` |
| **100 KB POST Data Loss** | **0 bytes (0.00%)** | 0 bytes | Zero dropped chunks, zero buffer overruns |
| **FreeRTOS Free Heap** | **17,816 bytes** | $> 10$ KB | Stable heap in PS DDR3 throughout continuous transfers |
| **UART Baud Rate** | **115,200** | 115,200 | Clean at 115200; no baud switch required |

---

## 3. Streaming and Body Size Mechanics

- **Incoming Transfers (GET)**: In passive receive mode (`AT+CIPRECVTYPE=4,1`), ESP-AT buffers TCP payloads in its internal window and emits asynchronous notification `+IPD,link,avail` over UART. The host drains the payload on demand using `AT+CIPRECVDATA=link,chunk_len`, eliminating UART RX FIFO buffer overruns.
- **Outgoing Transfers (POST/PUT)**: `AT+CIPSEND=link,len` accepts up to 2048 bytes per command chunk. After the command, ESP-AT prompts with `>`. Writing in $\le 2048$-byte chunks achieves 9.77 KB/s (85% of theoretical line rate).
