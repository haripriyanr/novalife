# 100 MHz clock constraint (post-synthesis timing check)
create_clock -name axi_lite_ctrl_clk -period 10.000 [get_ports s_axi_aclk]
