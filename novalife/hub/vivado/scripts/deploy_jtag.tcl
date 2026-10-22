# ============================================================================
# JTAG FPGA Bitstream Flashing Script
# Target: AMD/Xilinx Zynq Z-7010 (xc7z010_1)
# ============================================================================

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target

set bit_file [file normalize [file join [file dirname [info script]] ".." "build" "novalife_hub_vivado.runs" "impl_1" "novalife_zynq_soc_wrapper.bit"]]

puts "======================================================================"
puts "  PROGRAMMING ZYNQ Z010 FPGA VIA JTAG                                "
puts "  Bitstream File: $bit_file                                          "
puts "======================================================================"

set dev [get_hw_devices xc7z010_1]
set_property PROGRAM.FILE $bit_file $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "======================================================================"
puts "  SUCCESS: FPGA BITSTREAM PROGRAMMED ON PHYSICAL BOARD!              "
puts "======================================================================"

close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
