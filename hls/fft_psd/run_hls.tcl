# ============================================================================
# run_hls.tcl -- fft_psd: csim (regression) + optional csynth
# 2025.x flow: vitis-run --tcl run_hls.tcl --work_dir <kernel-dir>
# csim compares against the golden integer vectors (zero tolerance).
# For synthesis reports (DSE exercise): uncomment csynth_design/export_design.
# ============================================================================
open_project -reset fft_psd_proj
set_top fft_psd
add_files src/fft_psd.cpp
add_files -tb tb/tb_fft_psd.cpp -cflags "-Isrc"
open_solution sol1 -flow_target vivado
set_part xczu9eg-ffvb1156-2-e
create_clock -period 4

# --- DSE directives (course Section 2 applied for real) --------------------
# Baseline kept clean; try these in a variant solution and compare the
# Latency/DSP columns of the schedule report:
#   set_directive_pipeline -II 1 "STAGE"
#   set_directive_array_partition -type block -factor 4 variable rt
#   set_directive_array_partition -type block -factor 4 variable it
#   set_directive_dataflow "fft_psd"

csim_design
# csynth_design
# export_design -format ip_catalog
exit
