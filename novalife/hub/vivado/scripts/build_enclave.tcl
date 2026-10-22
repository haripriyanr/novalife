# ============================================================================
# NovaLife HUB - PS + PL enclave bitstream (tag engine behind AXI4-Lite at 0x40000000)
# ----------------------------------------------------------------------------
# PS7 with the EdgeZ7_10 board preset (as firmware/vivado_ps), UART1 on EMIO to the ESP32
# (R19 = ESP_TX into the Zynq, T19 = Zynq TX into the ESP), M_AXI_GP0 enabled, FCLK0 100 MHz,
# and the RTL module `enclave_axi` (tag_engine + ascon128_aead) on GP0 at 0x4000_0000.
#
# Runs synthesis, implementation (place + route) and write_bitstream, writes the post-route
# utilisation/timing reports and the XSA.  enclave_axi is built with ALLOW_AXI_KEY = 1: a
# bring-up deviation from D5, see the module header.
#
#   cd vivado/build_enclave_out && vivado -mode batch -source ../scripts/build_enclave.tcl
# ============================================================================

set here    [file normalize [file dirname [info script]]]
set root    [file normalize [file join $here ..]]
set ip      [file join $root ip_repo]
set out     [file join $root build_enclave]
# NOVALIFE_PROJECT_ONLY=1: build the project and block design, then stop (open the .xpr in the GUI).
# NOVALIFE_OUT=<dir>: where the project goes (default vivado/build_enclave).
if {[info exists ::env(NOVALIFE_OUT)]} { set out [file normalize $::env(NOVALIFE_OUT)] }
set part    xc7z010clg400-1

file mkdir $out
create_project -force novalife_enclave [file join $out proj] -part $part
set_property board_part allaboutfpga.com:edgez7_10:part0:1.0 [current_project]

add_files [list \
    [file join $ip enclave_axi enclave_axi.v] \
    [file join $ip tag_engine tag_engine.v] \
    [file join $ip ascon_core ascon128_aead.v] ]
# Verified cores not yet wired into the block design: present in the project, unused by it
# (the top is the block-design wrapper).  The marking datapath is integrated core by core.
add_files [list \
    [file join $ip block_embed_core block_embed_core.v] \
    [file join $ip iwt_53_core iwt_53_core.v] \
    [file join $ip iiwt_53_core iiwt_53_core.v] \
    [file join $ip perceptual_mask_core perceptual_mask_core.v] \
    [file join $ip polar_encoder polar_encoder.v] \
    [file join $ip polar_encoder polar_params.vh] \
    [file join $ip polar_scl_decoder polar_scl_decoder.v] ]
update_compile_order -fileset sources_1

# constraints: the two ESP32 UART pins
set xdc [file join $out enclave.xdc]
set fh [open $xdc w]
puts $fh "set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} \[get_ports ESP_TX\]"
puts $fh "set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} \[get_ports ESP_RX\]"
close $fh
add_files -fileset constrs_1 $xdc

create_bd_design "novalife_enclave"
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} [get_bd_cells processing_system7_0]
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {0} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {EMIO} \
] [get_bd_cells processing_system7_0]

make_bd_pins_external [get_bd_pins processing_system7_0/UART1_RX]
make_bd_pins_external [get_bd_pins processing_system7_0/UART1_TX]
set_property name ESP_TX [get_bd_ports UART1_RX_0]
set_property name ESP_RX [get_bd_ports UART1_TX_0]

create_bd_cell -type module -reference enclave_axi enclave_0
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto"} \
    [get_bd_intf_pins enclave_0/s_axi]

# 4 KB window at 0x4000_0000 (firmware/src/mailbox.h PL_BASE)
set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data] -filter {NAME =~ "*enclave_0*"}]
if {$seg eq ""} { set seg [lindex [get_bd_addr_segs processing_system7_0/Data/*] 0] }
set_property offset 0x40000000 $seg
set_property range 4K $seg

regenerate_bd_layout
validate_bd_design
save_bd_design
puts "ADDRESS MAP:"
foreach s [get_bd_addr_segs processing_system7_0/Data/*] {
    puts "  $s offset [get_property offset $s] range [get_property range $s]"
}

make_wrapper -files [get_files novalife_enclave.bd] -top
add_files -norecurse [glob [file join $out proj novalife_enclave.gen sources_1 bd novalife_enclave hdl novalife_enclave_wrapper.v]]
set_property top novalife_enclave_wrapper [current_fileset]

if {[info exists ::env(NOVALIFE_PROJECT_ONLY)]} {
    puts "PROJECT_ONLY_DONE xpr=[file join $out proj novalife_enclave.xpr]"
    exit 0
}

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "ERROR: synthesis failed"; exit 1 }

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "ERROR: implementation failed"; exit 1 }

open_run impl_1
report_utilization    -file [file join $out post_route_util.rpt]
report_utilization -hierarchical -file [file join $out post_route_util_hier.rpt]
report_timing_summary -file [file join $out post_route_timing.rpt]
report_power          -file [file join $out post_route_power.rpt]

set bit [glob [file join $out proj novalife_enclave.runs impl_1 *.bit]]
file copy -force $bit [file join $out novalife_enclave.bit]
write_hw_platform -fixed -include_bit -force -file [file join $out novalife_enclave.xsa]
puts "BUILD_ENCLAVE_DONE bit=[file join $out novalife_enclave.bit]"
