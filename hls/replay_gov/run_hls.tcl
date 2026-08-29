# replay_gov: csim (regression) + optional csynth
open_project -reset replay_gov_proj
set_top replay_gov
add_files src/replay_gov.cpp
add_files -tb tb/tb_replay_gov.cpp -cflags "-Isrc"
open_solution sol1 -flow_target vivado
set_part xczu9eg-ffvb1156-2-e
create_clock -period 4
# DSE knob: set_directive_pipeline -II 1 "SAMP"
csim_design
# csynth_design
exit
