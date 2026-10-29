#!/usr/bin/env python3
"""Create the Vitis workspace for CPU1 (bare-metal verify worker).

    vitis -s firmware/core1/create_core1_ws.py

Builds a separate platform (standalone on ps7_cortexa9_1) from the same XSA as the FreeRTOS platform, so
the working CPU0 workspace (firmware/vitis_ws) is never touched.  Output: firmware/vitis_ws_core1 (gitignored).
"""
import os
import vitis

here = os.path.dirname(os.path.abspath(__file__))
fw = os.path.dirname(here)
ws = os.path.join(fw, "vitis_ws_core1")
xsa = os.path.join(fw, "novalife_ps_hw.xsa")

client = vitis.create_client()
client.set_workspace(ws)
plat = client.create_platform_component(name="core1_platform", hw_design=xsa, os="standalone",
                                        cpu="ps7_cortexa9_1", domain_name="standalone_a9_1",
                                        no_boot_bsp=True)
dom = plat.get_domain("standalone_a9_1")
# CPU1 owns no peripheral: UART1 is the ESP32 link driven by CPU0, UART0 is not routed.
dom.set_config("os", "standalone_stdout", "None")
dom.set_config("os", "standalone_stdin", "None")
# AMP: leave the SCU, the shared L2 cache and the global timer to CPU0 (boot.S / xil-crt0.S guards).
dom.set_config("proc", "proc_extra_compiler_flags",
               " -O2 -g -Wall -Wextra -fno-tree-loop-distribute-patterns -DUSE_AMP=1")
plat.build()
vitis.dispose()
