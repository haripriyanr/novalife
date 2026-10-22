# 100 MHz clock constraint (post-synthesis timing check)
create_clock -name tag_engine_clk -period 10.000 [get_ports clk]
