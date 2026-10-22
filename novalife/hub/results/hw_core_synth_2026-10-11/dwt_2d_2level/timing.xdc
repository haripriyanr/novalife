# 100 MHz clock constraint (post-synthesis timing check)
create_clock -name dwt_2d_2level_clk -period 10.000 [get_ports clk]
