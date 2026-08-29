# fir_chan (stretch): csim (regression) + optional csynth
open_project -reset fir_chan_proj
set_top fir_chan
add_files src/fir_chan.cpp
add_files -tb tb/tb_fir_chan.cpp -cflags "-Isrc"
open_solution sol1 -flow_target vivado
set_part xczu9eg-ffvb1156-2-e
create_clock -period 4
# DSE knobs (compare schedule reports):
#   set_directive_array_partition -type complete variable coeff
#   set_directive_pipeline -II 1 "TAP"
#   set_directive_unroll factor=8 "TAP"
csim_design
# csynth_design
exit
