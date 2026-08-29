# ============================================================================
# node_a.xdc -- SPECTRUM SENTRY sensor head (ZCU102, XCZU9EG)
# Node A: DDR replay -> frame_gen -> (Aurora TX). Single DSP clock domain
# plus the Aurora user clock.
# ============================================================================

create_clock -period 4.000 -name pl_clk_dsp  [get_ports -quiet clk_dsp_p]

# Aurora user clock (156.25 MHz) crossing at the TX framing interface
set_false_path -from [get_clocks pl_clk_dsp]   -to [get_clocks user_clk_aurora]
set_false_path -from [get_clocks user_clk_aurora] -to [get_clocks pl_clk_dsp]

set_false_path -from [get_ports -quiet rst_n_async]

set_output_delay -clock pl_clk_dsp -max 5.0 [get_ports -quiet {led[*]}]
set_output_delay -clock pl_clk_dsp -min 1.0 [get_ports -quiet {led[*]}]
