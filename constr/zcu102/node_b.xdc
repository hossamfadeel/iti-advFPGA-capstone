# ============================================================================
# node_b.xdc -- SPECTRUM SENTRY edge node (ZCU102, XCZU9EG)
# Verification-first design: the UVM regression is the signoff gate; these
# constraints define the physical intent for the Vivado non-project flow.
# ============================================================================

# ---- clocks (created on PS FCLK pins in bd/node_b.tcl; periods asserted here)
create_clock -period 3.200 -name pl_clk_dsp    [get_ports -quiet clk_dsp_p]
create_clock -period 4.000 -name pl_clk_ctrl   [get_ports -quiet clk_ctrl_p]

# Aurora user clock comes from the GT wrapper (156.25 MHz): created by the
# Aurora IP; assert the CDC relationship here for the FIFO crossing.
set_false_path -from [get_clocks pl_clk_dsp]  -to [get_clocks user_clk_aurora]
set_false_path -from [get_clocks user_clk_aurora] -to [get_clocks pl_clk_dsp]

# ---- CDC: async FIFO pointer synchronizers (two-flop) ----------------------
# Gray pointer registers are synchronized by construction; cut timing on the
# first sync stage of every *_sync* register in cdc_async_fifo.
set_false_path -to [get_cells -hier -filter {NAME =~ *cdc_async_fifo*wq1*}]
set_false_path -to [get_cells -hier -filter {NAME =~ *cdc_async_fifo*rq1*}]

# ---- decouple control input (quasi-static from PS) --------------------------
set_false_path -from [get_ports -quiet decouple_en]

# ---- asynchronous system reset assertion ------------------------------------
set_false_path -from [get_ports -quiet rst_n_async]

# ---- I/O: JTAG/UART-adjacent LED heartbeat (bring-up aid) -------------------
set_output_delay -clock pl_clk_ctrl -max 5.0 [get_ports -quiet {led[*]}]
set_output_delay -clock pl_clk_ctrl -min 1.0 [get_ports -quiet {led[*]}]

# ---- design hygiene gates (CI: WNS >= 0, util < 80%) ------------------------
# enforced by ci/build.tcl and ci/gates/wns_gate.tcl
