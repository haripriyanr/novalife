# ============================================================================
# Vivado Automated Batch Build Script
# Target: AMD/Xilinx Zynq Z-7010 (xc7z010clg400-1)
# Project: NovaLife HUB Edge Gateway Hardware Acceleration System
# ============================================================================

# 1. Setup Project Environment
set proj_name "novalife_hub_vivado"
set proj_dir [file join [file dirname [info script]] ".." "build"]
set part_num "xc7z010clg400-1"

puts "======================================================================"
puts "  STARTING NOVALIFE HUB VIVADO SYNTHESIS & BITSTREAM GENERATION      "
puts "  Target Part: $part_num                                              "
puts "======================================================================"

create_project -force $proj_name $proj_dir -part $part_num

# 2. Add the product IP cores and constraints. The algorithm they implement is
#    specified in ../../docs/algorithm.md. Cores that were tried and rejected
#    (chaos/DNA/AES-CTR) were removed; if one is ever reintroduced, add it explicitly.
add_files [glob -nocomplain "$ip_repo_dir/*/*.v"]
add_files [file normalize [file join [file dirname [info script]] ".." "constraints" "zynq_z010_pinout.xdc"]]

# 3. Create Zynq-7000 Processing System Block Design
create_bd_design "novalife_zynq_soc"

# Instantiate Zynq 7 Processing System IP
set zynq_ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_axi_leader "0" } $zynq_ps

# Configure Zynq PS Clocks
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
] $zynq_ps

# Connect AXI Clocks to FCLK_CLK0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]

# Generate HDL Wrapper
make_wrapper -files [get_files [get_property FILE_NAME [current_bd_design]]] -top
add_files -norecurse [file join $proj_dir "$proj_name.srcs" "sources_1" "bd" "novalife_zynq_soc" "hdl" "novalife_zynq_soc_wrapper.v"]
set_property top novalife_zynq_soc_wrapper [current_fileset]

# 4. Run Synthesis
puts "----------------------------------------------------------------------"
puts "  RUNNING SYNTHESIS...                                                "
puts "----------------------------------------------------------------------"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

# 5. Run Implementation & Write Bitstream
puts "----------------------------------------------------------------------"
puts "  RUNNING IMPLEMENTATION & PLACE-AND-ROUTE...                         "
puts "----------------------------------------------------------------------"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

# 6. Export Hardware Handoff (.xsa) for Vitis / FreeRTOS
set xsa_file [file join [file dirname [info script]] ".." "novalife_hub_hw.xsa"]
write_hw_platform -fixed -include_bit -force -file $xsa_file

puts "======================================================================"
puts "  SUCCESS: VIVADO BITSTREAM & HARDWARE Spec GENERATED!                "
puts "  Output XSA File: $xsa_file                                         "
puts "======================================================================"
exit 0
