# ============================================================================
# kr260/node_b.xdc -- SENTRY edge node on Kria KR260 (K26 SOM, XCK26)
# Logical constraints (clocks, CDC) are board-independent; physical pins
# live in kr260/carrier_pins.xdc which MUST be filled from AMD's official
# files (see the header of that file).
# ============================================================================

create_clock -period 3.200 -name pl_clk_dsp    [get_ports -quiet clk_dsp_p]
create_clock -period 4.000 -name pl_clk_ctrl   [get_ports -quiet clk_ctrl_p]

set_false_path -from [get_clocks pl_clk_dsp]    -to [get_clocks user_clk_aurora]
set_false_path -from [get_clocks user_clk_aurora] -to [get_clocks pl_clk_dsp]

set_false_path -to [get_cells -hier -filter {NAME =~ *cdc_async_fifo*wq1*}]
set_false_path -to [get_cells -hier -filter {NAME =~ *cdc_async_fifo*rq1*}]

set_false_path -from [get_ports -quiet decouple_en]
set_false_path -from [get_ports -quiet rst_n_async]

set_output_delay -clock pl_clk_ctrl -max 5.0 [get_ports -quiet {led[*]}]
set_output_delay -clock pl_clk_ctrl -min 1.0 [get_ports -quiet {led[*]}]
