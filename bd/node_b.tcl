# ============================================================================
# node_b.tcl -- scripted (non-project) block design for the SENTRY edge node.
# Skeleton for the Vivado build (ci/build.tcl consumes it). The verification
# authority for this design is the UVM regression; this BD wires the same
# RTL modules for hardware bring-up on the ZCU102.
# ============================================================================
set part xczu9eg-ffvb1156-2-e

create_project -in_memory -part $part

# ---- Zynq US+ PS: DDR, UART, GEM, FCLKs -------------------------------------
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps_e]
set_property -dict [list \
  CONFIG.PSU__FCLKPL0_FREQ {250} \
  CONFIG.PSU__FCLKPL1_FREQ {100} \
  CONFIG.PSU__UART0_BAUDRATE {115200} \
  CONFIG.PSU__ENET0_ENABLE {1} \
] $ps

# ---- clocks ------------------------------------------------------------------
set dsp_clk  [create_bd_port -dir I -type clk clk_dsp_p]
set ctrl_clk [create_bd_port -dir I -type clk clk_ctrl_p]

# ---- SENTRY RTL modules (from rtl/) -------------------------------------------
add_files -fileset sources_1 [glob ../rtl/*.sv]
set_property top node_b_top [current_fileset]

# Instantiated (in node_b_top) : spec_ctrl, frame_check, decouple, rm1_energy
# (DFX slot), cdc_async_fifo, skid_buffer. Aurora 64B/66B IP occupies the GT
# quad; see Lab05 flow for the GT wrapper parameters.

# ---- AXI Lite control plane (GP0) ---------------------------------------------
set ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic_ctrl]
set_property -dict [list CONFIG.NUM_MI {2}] $ic
connect_bd_net [get_bd_pins ps_e/maxihpm0_lpd_aclk] [get_bd_pins axi_ic_ctrl/ACLK]

# spec_ctrl @ 0x8000_0000, Aurora control @ 0x8001_0000 (ICD address map)
assign_bd_address -offset 0x80000000 -range 0x1000 [get_bd_addr_segs spec_ctrl/reg0]

# ---- stream datapath ----------------------------------------------------------
# frame_check -> decouple -> rm1_energy (DFX slot) -> S2MM DMA -> HPC0 (CCI)
# frame_gen   <- MM2S DMA <- HP0 (DDR IQ replay, Node A variant)
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
  CONFIG.c_include_mm2s {0} \
  CONFIG.c_include_s2mm {1} \
  CONFIG.c_m_axi_s2mm_data_width {64} \
] $dma
connect_bd_net [get_bd_pins axi_dma_0/M_AXI_S2MM] \
  [get_bd_intf_pins ps_e/SAXIGP2_HPC0]   ;# coherent port (course Section 4)

# DFX: pblock + decoupler around rm1_energy -- see dfx/ and Lab01 flow.

validate_bd_design
save_bd_design
