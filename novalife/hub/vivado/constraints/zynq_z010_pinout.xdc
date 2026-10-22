## ============================================================================
## Pin Constraint File: edge_zynq_soc.xdc
## Target Board:         EDGE ZYNQ SoC FPGA Kit (xc7z010clg400-1)
## Project:              NovaLife HUB Edge Intelligence Gateway
## Source Reference:     https://allaboutfpga.com/edge-zynq-soc-fpga-kit-xdc-pin-details/
## ============================================================================

# ----------------------------------------------------------------------------
# Clock Signal (125 MHz Onboard Oscillator)
# ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 8.000 -waveform {0 4} [get_ports { clk }];

# ----------------------------------------------------------------------------
# Status LEDs
# ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]; # LSB - Heartbeat LED (1 Hz)
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]; # Arrhythmia Alert LED
set_property -dict { PACKAGE_PIN T17 IOSTANDARD LVCMOS33 } [get_ports { led[2] }]; # Stegano DWT+AES Active LED
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]; # MSB - LwIP Network Activity LED

# ----------------------------------------------------------------------------
# Audio Alert & Alarm Buzzer
# ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN L19 IOSTANDARD LVCMOS33 } [get_ports { Buzzer }]; # Arrhythmia Alarm Buzzer

# ----------------------------------------------------------------------------
# DIP Switches
# ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]; # LSB
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }];
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]; # MSB

# ----------------------------------------------------------------------------
# Push Buttons
# ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { pb[0] }]; # Manual Anomaly Trigger
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports { pb[1] }]; # Reset

# ----------------------------------------------------------------------------
# ESP32 WiFi / Bluetooth UART Transceiver
# ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN T19 IOSTANDARD LVCMOS33 } [get_ports { ESP_TXD }];
set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports { ESP_RXD }];

# ----------------------------------------------------------------------------
# 7-Segment Display (Digit Select + Segment Control)
# ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports { digit[0] }]; # LSB
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { digit[1] }];
set_property -dict { PACKAGE_PIN T12 IOSTANDARD LVCMOS33 } [get_ports { digit[2] }];
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports { digit[3] }]; # MSB

set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports { Seven_Segment[7] }]; # A
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { Seven_Segment[6] }]; # B
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { Seven_Segment[5] }]; # C
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports { Seven_Segment[4] }]; # D
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { Seven_Segment[3] }]; # E
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports { Seven_Segment[2] }]; # F
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports { Seven_Segment[1] }]; # G
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports { Seven_Segment[0] }]; # DP
