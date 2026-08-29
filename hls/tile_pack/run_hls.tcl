# tile_pack: csim (regression) + optional csynth
open_project -reset tile_pack_proj
set_top tile_pack
add_files src/tile_pack.cpp
add_files -tb tb/tb_tile_pack.cpp -cflags "-Isrc"
open_solution sol1 -flow_target vivado
# Board-agnostic csim; csynth part selected by environment:
#   HLS_PART=xck26-sfvc784-2LV-c  (Kria KR260 / K26 SOM)
#   HLS_PART=xczu9eg-ffvb1156-2-e  (ZCU102, default)
if {[info exists ::env(HLS_PART)]} { set_part $::env(HLS_PART) } else { set_part xczu9eg-ffvb1156-2-e }
create_clock -period 4
# DSE knobs (compare schedule reports):
#   set_directive_pipeline -II 1 "ROW"
#   set_directive_pipeline -II 1 "OUT"
csim_design
# csynth_design
exit
