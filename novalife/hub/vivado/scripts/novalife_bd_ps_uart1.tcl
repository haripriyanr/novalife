# NovaLife HUB - PS + EMIO UART1 BD for ESP32 link
# UART1 via EMIO -> R19 (ESP_TX into Zynq RX) / T19 (Zynq TX into ESP_RX)
create_bd_design "novalife_ps_uart1"

# Create PS7
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# Board automation (EdgeZ7_10: UART0/MIO14-15, GEM0, SDIO0, QSPI, USB)
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1"} [get_bd_cells processing_system7_0]

# Minimal PL config + UART1 on EMIO (ESP32 link, ref clock from IO PLL)
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0 {0} \
    CONFIG.PCW_USE_S_AXI_HP0 {0} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {EMIO} \
] [get_bd_cells processing_system7_0]

# Expose EMIO UART pins as top-level ports
# R19 carries ESP_TX -> Zynq, so it feeds UART1_RX.
# T19 carries Zynq TX -> ESP_RX, so it is driven by UART1_TX.
make_bd_pins_external [get_bd_pins processing_system7_0/UART1_RX]
make_bd_pins_external [get_bd_pins processing_system7_0/UART1_TX]
set_property name ESP_TX [get_bd_ports UART1_RX_0]
set_property name ESP_RX [get_bd_ports UART1_TX_0]

regenerate_bd_layout
validate_bd_design
save_bd_design
puts "BD_UART1_PORTS: [get_bd_ports]"
puts "BD CREATED WITH UART1 EMIO"
