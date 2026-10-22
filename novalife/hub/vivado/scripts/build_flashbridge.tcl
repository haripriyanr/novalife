# ============================================================================
# NovaLife HUB - "flash bridge" bitstream: PS UART1 (EMIO) routed to two expansion IO pins so the
# board's own USB-serial (PS UART0) can flash the ESP32 through J9 (see tools/esp_flash/README.md).
# PS7 + board preset only, no other logic.  Pins (from the board file part0_pins.xml):
#   FLASH_TX (Zynq -> J9 RXD) = IO1 = J16     FLASH_RX (J9 TXD -> Zynq) = IO2 = K16
#   cd vivado/build_flashbridge_out && vivado -mode batch -source ../scripts/build_flashbridge.tcl
# ============================================================================
set here [file normalize [file dirname [info script]]]
set root [file normalize [file join $here ..]]
set out  [file join $root build_flashbridge]
file mkdir $out
create_project -force flashbridge [file join $out proj] -part xc7z010clg400-1
set_property board_part allaboutfpga.com:edgez7_10:part0:1.0 [current_project]

set fh [open [file join $out flash.xdc] w]
puts $fh "set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} \[get_ports FLASH_TX\]"
puts $fh "set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33 PULLUP true} \[get_ports FLASH_RX\]"
close $fh
add_files -fileset constrs_1 [file join $out flash.xdc]

create_bd_design "flashbridge"
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} [get_bd_cells processing_system7_0]
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} CONFIG.PCW_USE_M_AXI_GP0 {0} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} CONFIG.PCW_UART1_UART1_IO {EMIO}] [get_bd_cells processing_system7_0]
make_bd_pins_external [get_bd_pins processing_system7_0/UART1_RX]
make_bd_pins_external [get_bd_pins processing_system7_0/UART1_TX]
set_property name FLASH_RX [get_bd_ports UART1_RX_0]
set_property name FLASH_TX [get_bd_ports UART1_TX_0]
validate_bd_design
save_bd_design
make_wrapper -files [get_files flashbridge.bd] -top
add_files -norecurse [glob [file join $out proj flashbridge.gen sources_1 bd flashbridge hdl flashbridge_wrapper.v]]
set_property top flashbridge_wrapper [current_fileset]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "ERROR: implementation failed"; exit 1 }
file copy -force [glob [file join $out proj flashbridge.runs impl_1 *.bit]] [file join $out flashbridge.bit]
write_hw_platform -fixed -include_bit -force -file [file join $out flashbridge.xsa]
puts "FLASHBRIDGE_DONE [file join $out flashbridge.bit]"
