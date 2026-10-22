# 100 MHz clock constraint (post-synthesis timing check)
create_clock -name polar_encoder_clk -period 10.000 [get_ports clk]
