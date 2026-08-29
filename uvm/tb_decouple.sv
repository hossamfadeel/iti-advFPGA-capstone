// ============================================================================
// TB Top: tb_decouple  (Stage B3 -- DFX decoupler verification)
// DUT: decouple. Stream 450 golden beats through while the test toggles
// decouple_en three times mid-stream. Sink must observe the identical
// sequence (no loss, no duplication); swapping/rm_rstn behavior checked.
// ============================================================================
`timescale 1ns/1ps
import uvm_pkg::*;
import sentry_uvm_pkg::*;
module tb_decouple;

  logic clk = 0, rst_n = 0;
  always #4 clk = ~clk;                 // 250 MHz
  initial begin
    repeat (5) @(posedge clk);
    rst_n <= 1;
  end

  axis_if #(.TDW(64)) in_if  (clk, rst_n);
  axis_if #(.TDW(64)) out_if (clk, rst_n);
  ctrl_if              c_if   (clk, rst_n);

  initial begin
    c_if.decouple_en = 0;
    c_if.swapping    = 0;
  end

  logic rm_rstn, swapping;

  decouple dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .decouple_en (c_if.decouple_en),
    .rm_rstn     (rm_rstn),
    .swapping    (swapping),
    .s_tvalid    (in_if.tvalid),
    .s_tready    (in_if.tready),
    .s_tdata     (in_if.tdata),
    .s_tlast     (in_if.tlast),
    .m_tvalid    (out_if.tvalid),
    .m_tready    (out_if.tready),
    .m_tdata     (out_if.tdata),
    .m_tlast     (out_if.tlast)
  );

  // Track that rm_rstn actually asserts during swaps
  int rst_low_cycles = 0;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) rst_low_cycles <= 0;
    else if (swapping && !rm_rstn) rst_low_cycles <= rst_low_cycles + 1;
  end

  initial begin
    uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.stream_in_ag.*",
                                         "vif", in_if);
    uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.stream_out_ag.*",
                                         "vif", out_if);
    uvm_config_db#(virtual ctrl_if)::set(null, "*", "ctrl_if", c_if);
    run_test("decouple_test");
  end

endmodule : tb_decouple
