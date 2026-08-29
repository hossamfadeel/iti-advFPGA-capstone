// ============================================================================
// TB Top: tb_frame_check  (Stage B2 -- link checker unit verification)
// DUT chain: frame_check + spec_ctrl (counters). Golden frames from
// vectors/frames_tx.mem; expected payload beats from frames_rx_expected.mem;
// counters triple-checked: DUT vs UVM model vs golden summary.
// ============================================================================
`timescale 1ns/1ps
import uvm_pkg::*;
import sentry_uvm_pkg::*;
module tb_frame_check;

  logic clk = 0, rst_n = 0;
  always #4 clk = ~clk;                 // 250 MHz DSP domain
  initial begin
    repeat (5) @(posedge clk);
    rst_n <= 1;
  end

  axi_lite_if #(.AW(6), .DW(32)) axil_if (clk, rst_n);
  axis_if  #(.TDW(64))           in_if   (clk, rst_n);
  axis_if  #(.TDW(64))           out_if  (clk, rst_n);

  logic ev_frame, ev_crc, ev_drop;

  frame_check dut_fc (
    .clk         (clk),
    .rst_n       (rst_n),
    .s_tvalid    (in_if.tvalid),
    .s_tready    (in_if.tready),
    .s_tdata     (in_if.tdata),
    .s_tlast     (in_if.tlast),
    .m_tvalid    (out_if.tvalid),
    .m_tready    (out_if.tready),
    .m_tdata     (out_if.tdata),
    .m_tlast     (out_if.tlast),
    .o_ev_frame  (ev_frame),
    .o_ev_crc    (ev_crc),
    .o_ev_drop   (ev_drop)
  );

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
    .i_ev_det         (1'b0),
    .i_ev_swap_done   (1'b0),
    .i_stream_lock    (1'b1),
    .i_lane_up        (1'b1),
    .i_rm_sig         (32'h524D3100),
    .i_swapping       (1'b0),
    .o_ctrl           (),
    .o_thr            (),
    .o_tile_rate      (),
    .o_irq            ()
  );

  initial begin
    uvm_config_db#(virtual axi_lite_if)::set(null, "uvm_test_top.env.axil_ag.*",
                                            "vif", axil_if);
    uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.stream_in_ag.*",
                                         "vif", in_if);
    uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.stream_out_ag.*",
                                         "vif", out_if);
        uvm_config_db#(virtual axi_lite_if)::set(null, "*", "axil_vif", axil_if);
    run_test("frame_check_test");
  end

endmodule : tb_frame_check
