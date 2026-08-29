// ============================================================================
// TB Top: tb_spec_ctrl  (Stage B1 -- spec_ctrl unit verification)
// DUT: spec_ctrl. The UVM test drives the AXI4-Lite plane through the RAL
// and wiggles event pins through ctrl_if, exactly like the A53 + datapath
// would in the real system.
// ============================================================================
`timescale 1ns/1ps
import uvm_pkg::*;
import sentry_uvm_pkg::*;
module tb_spec_ctrl;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;                 // 100 MHz control plane
  initial begin
    repeat (5) @(posedge clk);
    rst_n <= 1;
  end

  axi_lite_if #(.AW(6), .DW(32)) axil_if (clk, rst_n);
  ctrl_if                        c_if    (clk, rst_n);

  initial begin
    c_if.ev_frame    = 0;
    c_if.ev_crc      = 0;
    c_if.ev_drop     = 0;
    c_if.ev_det      = 0;
    c_if.ev_swap_done= 0;
    c_if.stream_lock = 0;
    c_if.lane_up     = 0;
    c_if.swapping    = 0;
    c_if.rm_sig      = 32'h0;
    c_if.decouple_en = 0;
  end

  spec_ctrl dut (
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
    .i_ev_frame       (c_if.ev_frame),
    .i_ev_crc         (c_if.ev_crc),
    .i_ev_drop        (c_if.ev_drop),
    .i_ev_det         (c_if.ev_det),
    .i_ev_swap_done   (c_if.ev_swap_done),
    .i_stream_lock    (c_if.stream_lock),
    .i_lane_up        (c_if.lane_up),
    .i_rm_sig         (c_if.rm_sig),
    .i_swapping       (c_if.swapping),
    .o_ctrl           (),
    .o_thr            (),
    .o_tile_rate      (),
    .o_irq            ()
  );

  initial begin
    uvm_config_db#(virtual axi_lite_if)::set(null, "uvm_test_top.env.axil_ag.*",
                                            "vif", axil_if);
    uvm_config_db#(virtual ctrl_if)::set(null, "*", "ctrl_if", c_if);
        uvm_config_db#(virtual axi_lite_if)::set(null, "*", "axil_vif", axil_if);
    run_test("spec_ctrl_test");
  end

endmodule : tb_spec_ctrl
