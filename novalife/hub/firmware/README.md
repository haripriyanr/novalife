# NovaLife HUB FreeRTOS firmware (phase 1)

FreeRTOS + lwIP + ESP32 Wi-Fi HTTP server on the EDGE ZYNQ (`xc7z010clg400-1`),
serving the three HUB endpoints (`docs/hub_http_api.md` Part 1), plus a FreeRTOS queue-driven mailbox implementing the full PS-PL command
protocol (BUILD_TAG, VERIFY_TAG, MARK_IMAGE, EXTRACT_TAG, STATUS, ADMIN_*). The mailbox probes for a loaded bitstream (`PL_STATUS_READY`); when none is
present it logs STUB and returns MB_ERR_NO_PL, so the firmware runs and is
testable over JTAG without the PL. When the bitstream lands, the same code
pokes the PL mailbox registers at `PL_BASE` and waits on the done flag. Loads and runs via JTAG.

## Layout

| Path | What |
|---|---|
| `novalife_ps_hw.xsa` | PS-only hardware handoff (PS7 + board preset, GEM0, UART0/1, SDIO, QSPI, USB; FCLK 100 MHz; M_AXI_GP0 clocked for the future mailbox) |
| `novalife_ps_uart1_wrapper.bit` | Minimal PL wrapper routing PS `UART1` EMIO signals to PL pins `R19` (`ESP_TX`) and `T19` (`ESP_RX`) so the onboard ESP-WROOM-32 Wi-Fi module reaches the LAN at `192.168.31.86:8080` when no RJ45 Ethernet cable is attached |
| `vivado_ps/` | Vivado project that generated the XSA |
| `vitis_ws/` | Vitis workspace: `novalife_ps_platform` (`freertos10_xilinx` domain on `ps7_cortexa9_0` + `lwip220`) + `novalife_hub_fw` app |
| `src/` | Sources (`main.c`, `http_server.c`, `vault.c/.h`, `mailbox.c/.h`), mirrored into `vitis_ws/novalife_hub_fw/src/` |

## FreeRTOS mechanisms used (learning notes)

1. **Tasks (`xTaskCreate`, `sys_thread_new`, `vTaskStartScheduler`)**:
   - `main_thrd` (`DEFAULT_THREAD_PRIO`): initialises lwIP (`lwip_init()`), spawns `NW_THRD`, waits up to 1.5 s for GEM0 DHCP (falling back to static `192.168.31.87/24` when no RJ45 cable is plugged in), then spawns `echod` and deletes itself (`vTaskDelete(NULL)`).
   - `NW_THRD` (`DEFAULT_THREAD_PRIO`): registers the Zynq GEM0 MAC (`xemac_add`), brings the interface up, spawns `xemacif_input_thread`, and pumps `dhcp_fine_tmr()` / `dhcp_coarse_tmr()` using `vTaskDelay()`.
   - `echod` (`DEFAULT_THREAD_PRIO`): initialises the shared vault mutex (`vault_init()`) and mailbox queue (`mailbox_init()`), spawns `espw`, and runs the lwIP BSD socket accept loop (`lwip_socket` / `lwip_bind` / `lwip_listen` / `lwip_accept`) on port `:80`.
   - `espw` (`tskIDLE_PRIORITY + 2`, stack 2048 words): drives the onboard ESP-WROOM-32 over `UART1` (`0xE0001000`, 115200 8N1 via EMIO `R19`/`T19`), verifies or establishes Wi-Fi station association (`192.168.31.86`), opens a TCP server on `:8080` (`AT+CIPMUX=1`, `AT+CIPSERVER=1,8080`), and dispatches incoming `+IPD` HTTP requests through the shared `build_http_response()` handler, yielding with `vTaskDelay(pdMS_TO_TICKS(5))` when idle so lower-priority tasks run.
   - `mbox` (`tskIDLE_PRIORITY + 1`, stack 1024 words): blocks on the mailbox command queue and forwards queued commands to the PL (arguments first, CMD write last = doorbell). Synchronous `mailbox_build_tag` / `mailbox_verify_tag` are serialised with a FreeRTOS **mutex** (`xSemaphoreCreateMutex`: priority inheritance, unlike a binary semaphore) because the mbox task and the HTTP handlers share one register file.

2. **TCP/IP thread model (lwIP)**:
   - lwIP runs its own internal `tcpip_thread`. Application code interacts with it through the thread-safe BSD sockets layer (`lwip_socket`, `lwip_bind`, `lwip_listen`, `lwip_accept`, `read`, `write`, `close`), which marshals operations to `tcpip_thread` via internal mailboxes.
   - Any thread calling into lwIP must be created with `sys_thread_new` so lwIP can allocate per-thread state.

3. **Queue (`xQueueCreate` / `xQueueSend` / `xQueueReceive` in `mailbox.c`)**:
   - `mb_queue` holds up to 8 `mb_cmd_t` enum values (`MB_BUILD_TAG`, `MB_VERIFY_TAG`, `MB_MARK_IMAGE`, `MB_EXTRACT_TAG`, `MB_STATUS`).
   - Producer (`POST /embed` in `http_server.c`): calls `mailbox_send(MB_MARK_IMAGE)` with `xQueueSend(mb_queue, &cmd, 0)` (0-tick non-blocking timeout) so the HTTP server never stalls if the queue is full.
   - Consumer (`mailbox_task` in `mailbox.c`): calls `xQueueReceive(mb_queue, &cmd, pdMS_TO_TICKS(10000))`. The 10-second block time puts `mbox` in the FreeRTOS `Blocked` state (consuming zero CPU cycles) until either a command arrives (`pdTRUE`) or the timeout expires (`pdFALSE`, printing a heartbeat line).

4. **Mutex (`xSemaphoreCreateMutex` / `xSemaphoreTake` / `xSemaphoreGive` in `vault.c`)**:
   - `vault_mutex` guards the 4-slot RAM vault (`slot_data`, `slot_len`, `next_slot`) shared between the `echod` (lwIP `:80`) task and the `espw` (ESP32 Wi-Fi `:8080`) task.
   - Unlike a binary semaphore, a FreeRTOS mutex includes **priority inheritance**: if a lower-priority task (`echod`) holds `vault_mutex` when a higher-priority task (`espw`) attempts `xSemaphoreTake(vault_mutex, portMAX_DELAY)`, FreeRTOS temporarily raises the holder's priority to prevent unbounded priority inversion.

5. **Tick & Delay (`vTaskDelay`, `pdMS_TO_TICKS`, `xTaskGetTickCount`)**:
   - Cooperative/time-sliced yielding during UART polling and DHCP timer loops uses `vTaskDelay(pdMS_TO_TICKS(ms))` instead of busy-wait spin loops, allowing the FreeRTOS scheduler to switch to ready tasks (`mbox`, `echod`, `IDLE`).
   - `GET /status` reports `xTaskGetTickCount()` as `"uptime_ticks"`.

## Endpoints (`http://192.168.31.86:8080` over Wi-Fi, `http://192.168.31.87:80` over GEM0)

- `GET /status` → `{"product":"novalife-hub","fw":"freertos-0.1","vault_files":<n>,"uptime_ticks":<ticks>,"mailbox":"stub","pl":"absent"}`
- `GET /vault/index.txt` → JSONL slot listing (`{"slot":0,"size":...}`).
- `POST /embed` → stores up to 1024 B in the next of 4 round-robin RAM slots, enqueues `MB_MARK_IMAGE` to `mb_queue`, and replies with JSON (`{"ok":true,"slot":...,"size":...}`) or echoes the cover `image/png` when called with multipart form data from the Flutter app.

## Honest limits (phase 1)

- Vault is RAM: contents reset on power-cycle/reboot.
- PL bitstream (`novalife_ps_uart1_wrapper.bit`) only wires `UART1` EMIO (`R19`/`T19`) for the onboard ESP32; no enclave logic. **`novalife_enclave.bit` / `novalife_enclave.xsa`** (2026-10-20, `vivado/scripts/build_enclave.tcl`) add the tag engine on M_AXI_GP0 at 0x4000_0000; with it loaded `/status` reports `"mailbox":"axi","pl":"present"` and `GET /enclave/verify?v=&hub=&handle=&tag=` runs VERIFY_TAG in the PL (board results: `results/hw_enclave_2026-10-20.md`). `POST /embed` answers 501 (MARK_IMAGE is not in the PL). Load: `xsdb vivado/scripts/board_fw_load.tcl [testkey]`.
