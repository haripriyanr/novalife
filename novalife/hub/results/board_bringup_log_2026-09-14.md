# Phase 01 — Board Bring-Up (EdgeZ7_10 xc7z010clg400-1)

Date (UTC): 2026-09-14 ~13:54-14:00 UTC (local Mon Sep 14 19:26-19:29)
Board: EdgeZ7_10, xc7z010clg400-1, Digilent USB serial 210319A288EEA
Tools root: /home/user/develop/Xilinx/2026.1
Repo: /run/media/user/DATA/repos/embedded_proj
Log path (this file): results/board_bringup_log_2026-09-14.md (moved from .build/phases/ on 2026-10-11)

## Goal
Verify toolchain + JTAG + UART + LAN reachability baseline before Phase 02 (PL block design).
Pass criteria: Vivado 2026.1 reports version, EdgeZ7_10 board files selectable,
hw_server running, JTAG chain shows xc7z010, UART probed at 115200, LAN state recorded.

## Exact commands run + outputs

### 0. Pre-checks
```
ls -la novalife_hub/results/
ls -la /dev/ttyUSB* ; id ; date -u
```
Output:
```
crw-rw-rw- 1 root uucp 188, 0 ... /dev/ttyUSB0
crw-rw-rw- 1 root uucp 188, 1 ... /dev/ttyUSB1
date: Monday 14 September 2026 01:54:49 PM UTC
```

### 1. Toolchain version (PASS)
```
ls /home/user/develop/Xilinx/2026.1/
ls /home/user/develop/Xilinx/2026.1/Vivado/bin/hw_server /home/user/develop/Xilinx/2026.1/Vitis/bin/xsct
/home/user/develop/Xilinx/2026.1/Vivado/bin/vivado -version | head -n 30
/home/user/develop/Xilinx/2026.1/Vitis/bin/vitis -v | head -n 20
/home/user/develop/Xilinx/2026.1/Vivado/bin/bootgen -help | head -n 15
```
Output:
```
vivado v2026.1 (64-bit)
Tool Version Limit: 2026.06
SW Build 6511674 on Tue Jun 16 11:01:26 MDT 2026
IP Build 6504888 on Tue Jun 09 09:05:25 MDT 2026
Vitis v2026.1 (64-bit) SW Build 6497934 on 2026-06-16-10:22:29
Bootgen v2026.1 Build date: Jun 5 2026-04:58:28
hw_server + xsct binaries both exist
Vivado BASIC license detected, active, expires 27-jun-2027 (from vivado_jtag.log)
```

### 2. Board files EdgeZ7_10 (PASS)
```
find /home/user/develop/Xilinx/2026.1/Vivado/data/boards -maxdepth 4 -iname "*edge*"
ls /home/user/develop/Xilinx/2026.1/Vivado/data/boards/board_files/
ls -R /home/user/develop/Xilinx/2026.1/Vivado/data/boards/board_files/allaboutfpga.com/edgeZ7_10/
cat .../edgeZ7_10/A.0/board.xml | head -n 80
grep -m5 -i "xc7z010\|clg400\|ps7\|DDR" .../edgeZ7_10/A.0/preset.xml | head -n 20
```
Output:
```
/home/user/develop/Xilinx/2026.1/Vivado/data/boards/board_files/allaboutfpga.com/edgeZ7_10
board_files/ = allaboutfpga.com, genesys2
edgeZ7_10/A.0 = board.xml, EDGE-ZYNQ.jpg, part0_pins.xml, preset.xml
board.xml: vendor=allaboutfpga.com name=edgeZ7_10 display_name=EdgeZ7_10 part_name=xc7z010clg400-1
preset.xml: PCW_UIPARAM_DDR_FREQ_MHZ=266.6666, DDR_PARTNO=MT41K256M16 RE-125, DRAM_WIDTH=16 Bits
```

Vivado selectable check via batch Tcl (.build/board_check.tcl):
```
vivado -mode batch -source .build/board_check.tcl -log .build/vivado_board.log -journal .build/vivado_board.jou
# board_check.tcl contents: get_board_parts *edge*, *Z7_10*, *allaboutfpga*
```
Output (vivado_board.log):
```
BOARD_PARTS_EDGE: allaboutfpga.com:edgez7_10:part0:1.0
WARNING: [Vivado 12-4842] No board parts matched 'get_board_parts *Z7_10*'.
BOARD_PARTS_Z7_10: (empty — pattern is case-sensitive, use lowercase *edge*)
BOARD_PARTS_ALLABOUT: allaboutfpga.com:edgez7_10:part0:1.0
```
Note: use `allaboutfpga.com:edgez7_10:part0:1.0` in Phase 02 block-design Tcl.

### 3. USB/JTAG physical (PASS)
```
lsusb | head -n 20
ls -l /dev/ttyUSB*
udevadm info -a -n /dev/ttyUSB0 | head -n 40
udevadm info -a -n /dev/ttyUSB1 | head -n 40
ls -l /dev/serial/by-id/ /dev/serial/by-path/
```
Output:
```
Bus 001 Device 007: ID 0403:6010 Future Technology Devices International, Ltd FT2232C/D/H Dual UART/FIFO IC
ttyUSB0: ftdi_sio, interface Digilent USB Device 1-1:1.0 (JTAG channel A)
ttyUSB1: ftdi_sio, interface Digilent USB Device 1-1:1.1 (UART channel B)
/dev/serial/by-id: only usb-Digilent_Digilent_USB_Device_210319A288EE-if01-port0 -> ../../ttyUSB1
  (ttyUSB0 JTAG has no by-id symlink on this host; use /dev/ttyUSB0 directly)
```

### 4. hw_server start (PASS)
```
ps aux | grep hw_server
ss -tlnp | grep 3121  # initially: port 3121 not listening
nohup /home/user/develop/Xilinx/2026.1/Vivado/bin/hw_server -s TCP::3121 \
  -L/run/media/user/DATA/repos/embedded_proj/novalife_hub/.build/hw_server.log \
  > /run/media/user/DATA/repos/embedded_proj/novalife_hub/.build/hw_server.out 2>&1 &
sleep 5; ps aux | grep hw_server; ss -tlnp | grep 3121
```
Output:
```
hw_server PID 64640 (wrapper) -> loader 64686 -> unwrapped/lnx64.o/hw_server 64751
LISTEN 0.0.0.0:3121 users:(("hw_server",pid=64751,fd=5))
Log: .build/hw_server.log, stdout: .build/hw_server.out (0 bytes, banner goes to cs_server in Vivado log)
```
hw_server left RUNNING for resume. To stop: `kill 64751` (or pkill hw_server). To restart use same command above.

### 5. xsct vs xsdb (TOOLCHAIN NOTE — xsct disabled in 2026.1)
```
DISPLAY="" /home/user/develop/Xilinx/2026.1/Vitis/bin/xsct -eval "puts hello; exit"
cat /home/user/develop/Xilinx/2026.1/Vitis/bin/xsct (wrapper inspection)
/home/user/develop/Xilinx/2026.1/Vitis/bin/xsct -nodisp -eval "puts hello_xsct_ok; exit"
```
Output:
```
without -nodisp: ERROR: xlsclients is not available on the system
with -nodisp: [ERROR]********** XSCT is disabled in Vitis 2026.1 release **********
  Please use the Vitis Python Console for script-based projects creation and build,
  or use Python-based XSDB for debugging. Refer to UG1400.
```
Workaround verified:
```
/home/user/develop/Xilinx/2026.1/Vivado/bin/xsdb -eval "puts XSDB_OK; exit"  -> XSDB_OK
/home/user/develop/Xilinx/2026.1/Vivado/bin/xsdb -eval "puts START_MARKER; connect -url TCP:127.0.0.1:3121; puts CONNECTED_OK; targets; exit"
  -> START_MARKER, CONNECTED_OK (targets prints empty via xsdb stdout but hw_server side proves detection)
```
hw_server.log during xsdb connect (proof of Zynq detection):
```
TCF ... Detected Zynq-7000: PS version 4
TCF ... Command: Jtag getChildren / RunControl getChildren / Memory getChildren ...
```

### 6. JTAG chain via Vivado hw_manager (PASS — authoritative)
Script: `.build/jtag_probe.tcl`:
```
open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
puts "HW_SERVER_CONNECTED"
puts "TARGETS: [get_hw_targets]"
open_hw_target [lindex [get_hw_targets] 0]
puts "OPEN_TARGET_OK"
puts "DEVICES: [get_hw_devices]"
foreach d [get_hw_devices] { puts "DEVICE_DETAIL: $d PART=[get_property PART $d]" }
foreach t [get_hw_targets] { puts "TARGET_DETAIL: $t" }
refresh_hw_device [lindex [get_hw_devices] 0]
puts "REFRESH_OK"
close_hw_target
disconnect_hw_server
puts "DONE_JTAG_PROBE"
exit
```
Command:
```
vivado -mode batch -source .build/jtag_probe.tcl -log .build/vivado_jtag.log -journal .build/vivado_jtag.jou
```
Output (vivado_jtag.log, 2026-09-14 19:28:04 session):
```
INFO: [Labtools 27-2285] Connecting to hw_server url TCP:localhost:3121
HW_SERVER_CONNECTED
TARGETS: localhost:3121/xilinx_tcf/Digilent/210319A288EEA
INFO: [Labtoolstcl 44-466] Opening hw_target localhost:3121/xilinx_tcf/Digilent/210319A288EEA
OPEN_TARGET_OK
DEVICES: arm_dap_0 xc7z010_1
DEVICE_DETAIL: arm_dap_0 PART=arm_dap
DEVICE_DETAIL: xc7z010_1 PART=xc7z010
TARGET_DETAIL: localhost:3121/xilinx_tcf/Digilent/210319A288EEA
REFRESH_OK
INFO: [Labtoolstcl 44-464] Closing hw_target localhost:3121/xilinx_tcf/Digilent/210319A288EEA
DONE_JTAG_PROBE
```
First attempt failed with `Labtoolstcl 44-235 labtools not initialized` (missing open_hw_manager) — fixed.
Second attempt failed with `invalid command name get_hw_chains` — removed, not a valid Vivado Tcl cmd.

### 7. UART boot log 115200 on ttyUSB1 (SILENT — no data, port OK)
No picocom/screen/minicom/tio present; no pyserial. Used Python stdlib termios:
```
python3 -c "<termios 115200 8N1 raw, VMIN=0 VTIME=10, select 8s on /dev/ttyUSB1>"
stty -F /dev/ttyUSB1  # before: speed 9600 baud
```
Output:
```
UART_OPEN_OK 115200 8N1
TOTAL_BYTES=0
NO_DATA_TIMEOUT_8S
```
Interpretation: UART opens cleanly at 115200 8N1, but board emits 0 bytes in 8 s.
Expected: no FSBL/U-Boot running (no SD boot / no firmware programmed yet). JTAG proves power+chain OK.
No `.build/uart_boot.log` written (no bytes to save). Retry after Phase 04/05 programming with:
`python3 <same reader>` or install picocom and `picocom -b 115200 /dev/ttyUSB1`.

### 8. LAN reachability (BOARD IP UNKNOWN — host state recorded, PASS as notes)
```
ip link | head -n 40
ip addr | head -n 80
ip neigh | head -n 20
```
Output:
```
1 lo UP; 2 enp2s0 <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 state DOWN, MAC 40:c2:ba:a6:bc:7b
3 wlan0 UP, inet 192.168.31.192/24 brd 192.168.31.255, gateway 192.168.31.1 REACHABLE
ip neigh: only 192.168.31.1 (router) — no board entry
enp2s0 = host wired NIC with NO cable/link. Board Ethernet not visible to host.
```
Conclusion: board IP unknown until lwIP firmware runs (Phase 05). No ping attempted (no target).

How to set static IP later (for Phase 05 firmware + host):
1. Firmware (lwIP, PS GEM0): hardcode e.g. IP=192.168.1.10 NETMASK=255.255.255.0 GW=192.168.1.1
   (or 192.168.31.10/24 if joining existing WiFi-router subnet via Ethernet switch).
   Use `lwip_init()`, `netif_add(&netif, &ip, &mask, &gw, NULL, xemacpsif_init, tcpip_input)`,
   `netif_set_default()`, `netif_set_up()`. Print IP over UART on boot.
2. Host point-to-point (direct cable to enp2s0):
   ```
   sudo ip addr add 192.168.1.1/24 dev enp2s0
   sudo ip link set enp2s0 up
   ping 192.168.1.10
   ```
3. Host via router/switch (board + host on same LAN):
   ```
   # nothing to set if board uses 192.168.31.10/24 + host already 192.168.31.192/24
   ping 192.168.31.10
   ip neigh show dev <iface>
   ```
4. Verify: UART boot IP print -> `ping <board-ip>` -> `curl http://<board-ip>/` (Phase 05 REST).
5. Current blocker: enp2s0 NO-CARRIER — connect Ethernet cable board<->host/switch before Phase 08.

## Files touched (all inside .build; no /tmp used)
- CREATED `.build/jtag_probe.tcl` — Vivado hw_manager JTAG probe (open/connect/list/refresh/close)
- CREATED `.build/board_check.tcl` — get_board_parts *edge* check
- CREATED `.build/hw_server.log` (27K, TCF + Zynq-7000 detection) + `.build/hw_server.out` (0 B)
- CREATED `.build/vivado_jtag.log` + `.build/vivado_jtag.jou` (authoritative JTAG chain)
- CREATED `.build/vivado_board.log` + `.build/vivado_board.jou` (board-part proof)
- CREATED `.build/vivado_jtag_*.backup.log/.jou` (auto-rotated by Vivado on re-run)
- MOVED this file to `results/board_bringup_log_2026-09-14.md` (2026-10-11)
- NOT created: `.build/uart_boot.log` (0 bytes received, nothing to save)
- No board-file installs needed (stock allaboutfpga.com edgeZ7_10 already present)
- No writes outside `.build`; `hw_server` left running (PID 64751, port 3121)

## Pass/fail per check
- [PASS] Toolchain: Vivado v2026.1 SW Build 6511674 + Vitis v2026.1 Build 6497934 + Bootgen v2026.1 + BASIC license to 2027-06-27
- [PASS] Board files: allaboutfpga.com edgeZ7_10 A.0 present, part xc7z010clg400-1, selectable as allaboutfpga.com:edgez7_10:part0:1.0
- [PASS] hw_server: running on TCP::3121 (PID 64751), log in .build/hw_server.log
- [PASS] JTAG: target Digilent/210319A288EEA open OK, devices arm_dap_0 + xc7z010_1 (PART=xc7z010), refresh OK; hw_server.log also shows Detected Zynq-7000 PS v4
- [WARN/SILENT] UART: /dev/ttyUSB1 opens at 115200 8N1, 0 bytes in 8 s — no boot log present (expected pre-firmware)
- [INFO] LAN: board IP unknown until firmware runs; host enp2s0 DOWN/NO-CARRIER, wlan0 192.168.31.192/24; static-IP recipe recorded above
- [NOTE] xsct classic disabled in Vitis 2026.1 — use Vivado hw_manager Tcl + xsdb + Vitis python console (vitis -s) going forward

## Next step for resume (Phase 02)
1. hw_server already running on :3121 — reuse; if dead, restart with command in §4.
2. Phase 02: create Vivado block design Tcl using board_part `allaboutfpga.com:edgez7_10:part0:1.0`, PS + AXI DMA, verify preset DDR MT41K256M16.
3. UART: re-probe /dev/ttyUSB1 @115200 after first FSBL/hello-world .elf (expect Xilinx boot text); install picocom if desired.
4. LAN: connect board Ethernet cable (fix enp2s0 NO-CARRIER), then Phase 05 lwIP static IP + ping test.
