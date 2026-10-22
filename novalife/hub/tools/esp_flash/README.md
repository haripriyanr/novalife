# Flashing the ESP32 (ESP-WROOM-32) on the EDGE Zynq board with no USB-UART adapter (2026-10-22)

The board's own USB-serial (PS UART0, /dev/ttyUSB1) is bridged by a small bare-metal program on the ARM
(`bridge.c`, UART0 <-> UART1 EMIO) to the ESP32's flashing UART, which is J9 (TXD/RXD/IO0/GND), NOT the
Zynq's normal AT link (R19/T19, which is the ESP32 AT port, UART1).

Wiring (board off): J9 RXD -> J13 pin 20 (Zynq J16), J9 TXD -> J13 pin 19 (Zynq K16), jumper IO0-GND on J9,
J8 on E.  J13 pin map: vendor manual (pin 19 = K16, pin 20 = J16, pin 4 = GND, pin 1 = 5 V: never use).
Steps: `xsdb vivado/scripts/load_flashbridge.tcl`; reset the ESP32 with J8 E->D->E (D cuts its power);
`esptool --port /dev/ttyUSB1 --baud 115200 --before no-reset --after no-reset <command>` (esptool v5.6.0, in a
scratch venv).  Remove the IO0 jumper and the two wires afterwards.
Done: chip ESP32-D0WDQ6 v1.0, 40 MHz crystal, 4 MB flash; backup `backup/esp32_original_4MB.bin` (sha256
a4fc0a96e262e9d4be387d58641a831aa0db41731b13c2800267d6cfea533eef); flashed ESP-AT v4.1.1.0 WROOM-32
(zip sha256 c1482d37f7378612b5b0c2fbc161e1b492ddc5f90c25009a0adec98519d60507, from dl.espressif.com) at the
addresses of its download.config; AT+GMR reports v4.1.1.0, SDK v5.4.1; HTTPCLIENT/HTTPCGET/HTTPCPOST/HTTPCPUT,
CIPSSLCCONF, SYSMFG present.  Restore the old firmware with `write-flash 0x0 backup/esp32_original_4MB.bin`.

## CA Certificate Provisioning and Rotation (January 28, 2028 Expiry)

Outbound HTTPS connections to Supabase (`rtsduiqbgdiyygczivbl.supabase.co`) use genuine X.509 server
certificate path validation (`AT+CIPSSLCCONF=4,2,0,0` with `AT+CIPSSLCSNI`).

### Provisioning Procedure
1. Supabase's certificate chain terminates at the **GlobalSign Root CA** (serial `04:00:00:00:00:01:15:4b:5a:39:4e`,
   SHA-256 fingerprint `11:a0:7c:39:8c:0e:52:81:58:65:02:60:20:ce:7f:8d:65:47:1d:3d:96:60:ca:b4:49:50:31:98:e8:18:4c:3c`).
2. The CA certificate is 1258 bytes in clean PEM format.
3. It is provisioned into the ESP32's NVS manufacturing partition (`mfg_nvs`) using the `AT+SYSMFG` command:
   ```
   AT+SYSMFG=2,"client_ca","client_ca.0",1,1258
   ```
4. Upon receiving the `>` prompt, the raw 1258 bytes of the PEM certificate are transmitted over UART1.
5. The certificate is also mirrored to `https_ca.0` via `AT+SYSMFG=2,"https_ca","https_ca.0",1,1258`.

### Verification
- Connect with CA verification enabled: `AT+CIPSSLCCONF=4,2,0,0` and `AT+CIPSSLCSNI=4,"rtsduiqbgdiyygczivbl.supabase.co"`.
- Valid connection to Supabase yields `4,CONNECT OK` (handshake ~4.2 - 4.4 s).
- Negative control: Connecting to an untrusted host (e.g., `untrusted-root.badssl.com:443`) immediately returns `ERROR` and aborts the connection.

### Rotation Steps (Expiry: January 28, 2028 12:00:00 GMT)
The GlobalSign Root CA expires on January 28, 2028 GMT. When rotating:
1. Obtain the new Root CA certificate (PEM format) corresponding to the Supabase endpoint certificate chain.
2. Measure the exact byte size of the PEM file (e.g. `wc -c new_ca.pem`).
3. Connect to the ESP32 AT interface and issue:
   ```
   AT+SYSMFG=2,"client_ca","client_ca.0",1,<byte_length>
   ```
4. At the `>` prompt, send the new PEM certificate bytes within the timeout.
5. Verify the new certificate against the target host using `AT+CIPSSLCCONF=4,2,0,0` and test a negative control with an untrusted host.
6. Flash/NVS state persists across ESP32 reboots and power cycles.

