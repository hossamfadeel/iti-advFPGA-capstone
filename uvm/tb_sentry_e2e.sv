// ============================================================================
// TB Top: tb_sentry_e2e  (Stage C -- full-system integration)
// DUT chain (the ARCHITECTURE.md section 2 picture):
//   frame_gen @ wr_clk (156.25 MHz, "Aurora user side")
//     -> cdc_async_fifo (gray-pointer CDC, tlast preserved)
//     -> frame_check -> decouple (idle) -> rm1_energy @ clk (250 MHz)
//   spec_ctrl closes the loop: THR/det_arm written via RAL ("the PS"),
//   counters checked against vectors/e2e_summary.txt.
// Detections compared against vectors/det_expected.mem, zero tolerance.
// ============================================================================
`timescale 1ns/1ps
import uvm_pkg::*;
import sentry_uvm_pkg::*;
module tb_sentry_e2e;

  logic wr_clk = 0;                     // 156.25 MHz
  logic clk    = 0;                     // 250 MHz
  logic rst_n  = 0;
  always #3.2 wr_clk = ~wr_clk;
  always #2.0 clk    = ~clk;
  initial begin
    repeat (10) @(posedge clk);
    rst_n <= 1;
  end

  // ---- interfaces ----------------------------------------------------------
  axis_if #(.TDW(64)) in_wr_if (wr_clk, rst_n);   // stimulus -> frame_gen
  axis_if #(.TDW(64)) out_if   (clk, rst_n);      // rm1 detections -> sink
  axi_lite_if #(.AW(6), .DW(32)) axil_if (clk, rst_n);
  ctrl_if c_if (clk, rst_n);

  initial begin
    c_if.decouple_en = 0;
    c_if.swapping    = 0;
  end

  // ---- chain signals (declared before all instantiations) ------------------
  logic           fg_valid, fg_last, fifo_wfull;
  logic [63:0]    fg_data;
  logic           fifo_rempty, fifo_rlast;
  logic [63:0]    fifo_rdata;
  logic           fc_sready, ev_frame, ev_crc, ev_drop, ev_det;
  logic           dc_svalid, dc_sready, dc_slast;
  logic [63:0]    dc_sdata;
  logic           dc_mvalid, dc_mready, dc_mlast;
  logic [63:0]    dc_mdata;
  logic           rm_rstn, swapping, rm_sready;
  logic [31:0]    sc_ctrl_w, sc_thr_w;

  // ---- TX framer (wr domain) -------------------------------------------------
  frame_gen dut_fg (
    .clk      (wr_clk),
    .rst_n    (rst_n),
    .s_tvalid (in_wr_if.tvalid),
    .s_tready (in_wr_if.tready),
    .s_tdata  (in_wr_if.tdata),
    .m_tvalid (fg_valid),
    .m_tready (!fifo_wfull),
    .m_tdata  (fg_data),
    .m_tlast  (fg_last),
    .o_seq    ()
  );

  // ---- CDC crossing (Aurora user clk -> DSP clk, tlast preserved) -----------
  cdc_async_fifo #(.TDW(64), .DEPTH(16)) dut_fifo (
    .wr_clk  (wr_clk),
    .rst_n   (rst_n),
    .wr_en   (fg_valid && !fifo_wfull),
    .wr_data (fg_data),
    .wr_tlast(fg_last),
    .wr_full (fifo_wfull),
    .rd_clk  (clk),
    .rd_en   (fc_sready && !fifo_rempty),
    .rd_data (fifo_rdata),
    .rd_tlast(fifo_rlast),
    .rd_empty(fifo_rempty)
  );

  // ---- RX checker (DSP domain) ----------------------------------------------
  frame_check dut_fc (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_tvalid   (!fifo_rempty),
    .s_tready   (fc_sready),
    .s_tdata    (fifo_rdata),
    .s_tlast    (fifo_rlast),
    .m_tvalid   (dc_svalid),
    .m_tready   (dc_sready),
    .m_tdata    (dc_sdata),
    .m_tlast    (dc_slast),
    .o_ev_frame (ev_frame),
    .o_ev_crc   (ev_crc),
    .o_ev_drop  (ev_drop)
  );

  // ---- DFX gate (idle in this test; wiring proven by tb_decouple) -----------
  decouple dut_dc (
    .clk         (clk),
    .rst_n       (rst_n),
    .decouple_en (c_if.decouple_en),
    .rm_rstn     (rm_rstn),
    .swapping    (swapping),
    .s_tvalid    (dc_svalid),
    .s_tready    (dc_sready),
    .s_tdata     (dc_sdata),
    .s_tlast     (dc_slast),
    .m_tvalid    (dc_mvalid),
    .m_tready    (rm_sready),
    .m_tdata     (dc_mdata),
    .m_tlast     (dc_mlast)
  );

  // ---- RM1 energy detector (the DFX slot occupant) ---------------------------
  rm1_energy dut_rm (
    .clk      (clk),
    .rst_n    (rm_rstn),
    .s_tvalid (dc_mvalid),
    .s_tready (rm_sready),
    .s_tdata  (dc_mdata),
    .s_tlast  (dc_mlast),
    .m_tvalid (out_if.tvalid),
    .m_tready (out_if.tready),
    .m_tdata  (out_if.tdata),
    .m_tlast  (out_if.tlast),
    .i_det_arm(sc_ctrl_w[0]),
    .i_thr    (sc_thr_w),
    .o_ev_det (ev_det),
    .o_rm_sig ()
  );

  // ---- control plane ("PS" via RAL) ------------------------------------------
  spec_ctrl dut_sc (
    .clk              (clk),
    .rst_n            (rst_n),
    .s_axil_awaddr    (axil_if.awaddr),
    .s_axil_awvalid   (axil_if.awvalid),
    .s_axil_awready   (axil_if.awready),
    .s_axil_wdata     (axil_if.wdata),
    .s_axil_wstrb     (axil_if.wstrb),
    .s_axil_wvalid    (axil_if.wvalid),
    .s_axil_wready    (axil_if.wready),
    .s_axil_bresp     (axil_if.bresp),
    .s_axil_bvalid    (axil_if.bvalid),
    .s_axil_bready    (axil_if.bready),
    .s_axil_araddr    (axil_if.araddr),
    .s_axil_arvalid   (axil_if.arvalid),
    .s_axil_arready   (axil_if.arready),
    .s_axil_rdata     (axil_if.rdata),
    .s_axil_rresp     (axil_if.rresp),
    .s_axil_rvalid    (axil_if.rvalid),
    .s_axil_rready    (axil_if.rready),
    .i_ev_frame       (ev_frame),
    .i_ev_crc         (ev_crc),
    .i_ev_drop        (ev_drop),
    .i_ev_det         (ev_det),
    .i_ev_swap_done   (1'b0),
    .i_stream_lock    (1'b1),
    .i_lane_up        (1'b1),
    .i_rm_sig         (32'h524D3100),
    .i_swapping       (swapping),
    .o_ctrl           (sc_ctrl_w),
    .o_thr            (sc_thr_w),
    .o_tile_rate      (),
    .o_irq            ()
  );

  // Debug heartbeat: chain state every 500 ns
  int unsigned hb = 0;
  always #500 begin
    $display("[E2E %0t] fg=%b fifo_f=%b fifo_e=%b fc_rdy=%b dc_v=%b rm_rdy=%b out_v=%b",
             $time, fg_valid, fifo_wfull, fifo_rempty, fc_sready, dc_mvalid,
             rm_sready, out_if.tvalid);
    hb++;
    if (hb == 20) begin
      $display("FATAL: e2e heartbeat timeout");
      $finish;
    end
  end

  initial begin
    uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.stream_in_ag.*",
                                         "vif", in_wr_if);
    uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.stream_out_ag.*",
                                         "vif", out_if);
    uvm_config_db#(virtual axi_lite_if)::set(null, "uvm_test_top.env.axil_ag.*",
                                            "vif", axil_if);
    uvm_config_db#(virtual ctrl_if)::set(null, "*", "ctrl_if", c_if);
        uvm_config_db#(virtual axi_lite_if)::set(null, "*", "axil_vif", axil_if);
    run_test("e2e_test");
  end

endmodule : tb_sentry_e2e
