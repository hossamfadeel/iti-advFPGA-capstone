// ============================================================================
// Module: spec_ctrl
// Description: Custom AXI4-Lite control/status register file (ICD section 2).
//              16 registers at GP0 offset 0x8000_0000. Counters/STATUS/RM_SIG
//              are hardware inputs (from frame_check, decouple, RM); CTRL,
//              THR, TILE_RATE, SCRATCH are RW; IRQ_FLAGS is RCW1.
// ============================================================================
// Clock Domain: clk (pl_clk_ctrl or pl_clk_dsp -- single domain)
// Reset: rst_n (active-low, synchronous)
// ============================================================================
module spec_ctrl (
  input  logic             clk,
  input  logic             rst_n,
  // ---- AXI4-Lite subordinate interface ------------------------------------
  input  logic [5:0]       s_axil_awaddr,
  input  logic             s_axil_awvalid,
  output logic             s_axil_awready,
  input  logic [31:0]      s_axil_wdata,
  input  logic [3:0]       s_axil_wstrb,
  input  logic             s_axil_wvalid,
  output logic             s_axil_wready,
  output logic [1:0]       s_axil_bresp,
  output logic             s_axil_bvalid,
  input  logic             s_axil_bready,
  input  logic [5:0]       s_axil_araddr,
  input  logic             s_axil_arvalid,
  output logic             s_axil_arready,
  output logic [31:0]      s_axil_rdata,
  output logic [1:0]       s_axil_rresp,
  output logic             s_axil_rvalid,
  input  logic             s_axil_rready,
  // ---- hardware event inputs ----------------------------------------------
  input  logic             i_ev_frame,     // pulse: good frame counted
  input  logic             i_ev_crc,       // pulse: CRC error counted
  input  logic             i_ev_drop,      // pulse: sequence-gap drop counted
  input  logic             i_ev_det,       // pulse: detection emitted
  input  logic             i_ev_swap_done, // pulse: RM swap completed
  input  logic             i_stream_lock,
  input  logic             i_lane_up,
  input  logic [31:0]      i_rm_sig,
  input  logic             i_swapping,
  // ---- outputs to the platform --------------------------------------------
  output logic [31:0]      o_ctrl,         // CTRL mirror for datapath
  output logic [31:0]      o_thr,          // detection threshold
  output logic [31:0]      o_tile_rate,
  output logic             o_irq
);

  import sentry_defs::*;

  // ---- register storage ----------------------------------------------------
  logic [31:0] r_ctrl, r_thr, r_tile_rate, r_scratch;
  logic [31:0] r_frame_cnt, r_crc_err, r_drop_cnt, r_det_count;
  logic [31:0] r_irq_flags;

  // ---- write channel -------------------------------------------------------
  logic        aw_fire, w_fire;
  assign aw_fire = s_axil_awvalid && s_axil_awready;
  assign w_fire  = s_axil_wvalid  && s_axil_wready;

  // Single-beat address/data acceptance (AW and W advance together)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_axil_awready <= 1'b0;
      s_axil_wready  <= 1'b0;
    end else begin
      if (!s_axil_awready) begin
        s_axil_awready <= s_axil_awvalid;
        s_axil_wready  <= s_axil_wvalid;
      end else begin
        s_axil_awready <= 1'b0;
        s_axil_wready  <= 1'b0;
      end
    end
  end

  // Combinational decode of the accepted write (AW/W fire same cycle)
  logic        wr_en;
  logic [5:0]  wr_addr;
  assign wr_en   = aw_fire && w_fire;
  assign wr_addr = s_axil_awaddr;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      r_ctrl      <= 32'h0;
      r_thr       <= 32'h0;
      r_tile_rate <= 32'd8;
      r_scratch   <= 32'h0;
    end else if (wr_en) begin
      case (wr_addr)
        REG_CTRL:      r_ctrl      <= s_axil_wdata;
        REG_THR:       r_thr       <= s_axil_wdata;
        REG_TILE_RATE: r_tile_rate <= s_axil_wdata;
        REG_SCRATCH:   r_scratch   <= s_axil_wdata;
        default: ;
      endcase
    end
  end

  // ---- event counters + RCW1 irq flags -------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      r_frame_cnt <= 32'h0;
      r_crc_err   <= 32'h0;
      r_drop_cnt  <= 32'h0;
      r_det_count <= 32'h0;
      r_irq_flags <= 32'h0;
    end else begin
      if (i_ev_frame) r_frame_cnt <= r_frame_cnt + 32'd1;
      if (i_ev_crc)   r_crc_err   <= r_crc_err   + 32'd1;
      if (i_ev_drop)  r_drop_cnt  <= r_drop_cnt  + 32'd1;
      if (i_ev_det)   r_det_count <= r_det_count + 32'd1;
      if (i_ev_swap_done) r_irq_flags[IRQ_SWAP_DONE] <= 1'b1;
      if (i_ev_frame)     r_irq_flags[IRQ_FRAME]     <= 1'b1;
      if (i_ev_crc)       r_irq_flags[IRQ_CRC]       <= 1'b1;
      if (i_ev_det)       r_irq_flags[IRQ_DET]       <= 1'b1;
      // RCW1 clear (write-1-to-clear has priority over set on same bit)
      if (wr_en && wr_addr == REG_IRQ_FLAGS)
        r_irq_flags <= r_irq_flags & ~s_axil_wdata;
    end
  end

  // ---- read channel --------------------------------------------------------
  logic [31:0] status_word;
  assign status_word = {23'h0, i_swapping, 5'h0, (i_rm_sig != 32'h0),
                        i_lane_up, i_stream_lock};

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_axil_arready <= 1'b0;
      s_axil_rvalid  <= 1'b0;
      s_axil_rdata   <= 32'h0;
      s_axil_rresp   <= 2'b00;
    end else begin
      if (!s_axil_arready && s_axil_arvalid) begin
        s_axil_arready <= 1'b1;
        s_axil_rvalid  <= 1'b1;
        s_axil_rresp   <= 2'b00;
        case (s_axil_araddr)
          REG_ID:        s_axil_rdata <= REG_ID_VAL;
          REG_VERSION:   s_axil_rdata <= REG_VERSION_VAL;
          REG_CTRL:      s_axil_rdata <= r_ctrl;
          REG_STATUS:    s_axil_rdata <= status_word;
          REG_FRAME_CNT: s_axil_rdata <= r_frame_cnt;
          REG_CRC_ERR:   s_axil_rdata <= r_crc_err;
          REG_DROP_CNT:  s_axil_rdata <= r_drop_cnt;
          REG_DET_COUNT: s_axil_rdata <= r_det_count;
          REG_THR:       s_axil_rdata <= r_thr;
          REG_TILE_RATE: s_axil_rdata <= r_tile_rate;
          REG_RM_SIG:    s_axil_rdata <= i_rm_sig;
          REG_IRQ_FLAGS: s_axil_rdata <= r_irq_flags;
          REG_SCRATCH:   s_axil_rdata <= r_scratch;
          default:       s_axil_rdata <= 32'h0; // rsvd reads as zero
        endcase
      end else begin
        s_axil_arready <= 1'b0;
        if (s_axil_rvalid && s_axil_rready) s_axil_rvalid <= 1'b0;
      end
    end
  end

  // ---- write response ------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_axil_bvalid <= 1'b0;
      s_axil_bresp  <= 2'b00;
    end else begin
      if (wr_en) begin
        s_axil_bvalid <= 1'b1;
        s_axil_bresp  <= 2'b00;
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end
    end
  end

  // ---- outputs -------------------------------------------------------------
  assign o_ctrl      = r_ctrl;
  assign o_thr       = r_thr;
  assign o_tile_rate = r_tile_rate;
  assign o_irq = r_ctrl[C_IRQ_EN] && |r_irq_flags[3:0];

endmodule : spec_ctrl
