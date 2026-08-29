# ============================================================================
# node_a.tcl -- scripted block design for the SENTRY sensor head.
# DDR I/Q replay -> replay_gov (HLS, optional) -> frame_gen -> Aurora TX.
# ============================================================================
set part xczu9eg-ffvb1156-2-e

create_project -in_memory -part $part

set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps_e]
set_property -dict [list \
  CONFIG.PSU__FCLKPL0_FREQ {250} \
  CONFIG.PSU__UART0_BAUDRATE {115200} \
] $ps

add_files -fileset sources_1 [glob ../rtl/*.sv]
set_property top node_a_top [current_fileset]

# Instantiated in node_a_top: frame_gen (+ replay_gov HLS IP when synthesized
# from hls/replay_gov), CDC FIFOs, skid buffers, spec_ctrl (counters).

# Replay DMA: DDR -> MM2S -> frame_gen  (HP0, non-coherent on Node A)
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
  CONFIG.c_include_mm2s {1} \
  CONFIG.c_include_s2mm {0} \
  CONFIG.c_m_axi_mm2s_data_width {64} \
] $dma
connect_bd_net [get_bd_pins axi_dma_0/M_AXI_MM2S] \
  [get_bd_intf_pins ps_e/SAXIGP0_HP0]

validate_bd_design
save_bd_design
