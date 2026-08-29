# ============================================================================
# kr260/node_a.xdc -- SENTRY sensor head on Kria KR260 (K26 SOM, XCK26)
# Logical constraints (clocks, CDC) are board-independent; physical pins
# live in kr260/carrier_pins.xdc which MUST be filled from AMD's official
# files (see the header of that file).
# ============================================================================

create_clock -period 4.000 -name pl_clk_dsp  [get_ports -quiet clk_dsp_p]

# Aurora user clock (156.25 MHz from MGTREFCLK0_224 on the KR260 carrier)
set_false_path -from [get_clocks pl_clk_dsp]     -to [get_clocks user_clk_aurora]
set_false_path -from [get_clocks user_clk_aurora] -to [get_clocks pl_clk_dsp]

set_false_path -from [get_ports -quiet rst_n_async]

set_output_delay -clock pl_clk_dsp -max 5.0 [get_ports -quiet {led[*]}]
set_output_delay -clock pl_clk_dsp -min 1.0 [get_ports -quiet {led[*]}]
