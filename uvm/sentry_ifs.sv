// ============================================================================
// File: sentry_ifs.sv
// Description: Testbench interfaces for the SENTRY UVM environment.
//   axi_lite_if : AXI4-Lite subordinate-side pins + driver/monitor clocking
//   axis_if     : AXI4-Stream pins + driver/monitor clocking
//   ctrl_if     : quasi-static control/event pins (decouple_en, events)
// ============================================================================
`timescale 1ns/1ps

interface axi_lite_if #(parameter int AW = 6, DW = 32)
                      (input logic clk, input logic rst_n);
  logic [AW-1:0] awaddr;
  logic           awvalid, awready;
  logic [DW-1:0]  wdata;
  logic [3:0]     wstrb;
  logic           wvalid, wready;
  logic [1:0]     bresp;
  logic           bvalid, bready;
  logic [AW-1:0] araddr;
  logic           arvalid, arready;
  logic [DW-1:0]  rdata;
  logic [1:0]     rresp;
  logic           rvalid, rready;

  clocking drv_cb @(posedge clk);
    output awaddr, awvalid, wdata, wstrb, wvalid, bready,
           araddr, arvalid, rready;
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input awaddr, awvalid, awready, wdata, wstrb, wvalid, wready,
          bresp, bvalid, bready, araddr, arvalid, arready,
          rdata, rresp, rvalid, rready;
  endclocking
endinterface : axi_lite_if

interface axis_if #(parameter int TDW = 64)
                   (input logic clk, input logic rst_n);
  logic [TDW-1:0] tdata;
  logic           tvalid, tready, tlast;

  clocking drv_cb @(posedge clk);
    output tdata, tvalid, tlast;
    input  tready;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input tdata, tvalid, tready, tlast;
  endclocking
endinterface : axis_if

// Quasi-static control pins shared across TBs (events, decouple, status)
interface ctrl_if (input logic clk, input logic rst_n);
  logic ev_frame, ev_crc, ev_drop, ev_det, ev_swap_done;
  logic stream_lock, lane_up, swapping;
  logic [31:0] rm_sig;
  logic decouple_en;
  logic det_arm;
  logic [31:0] thr;

  clocking cb @(posedge clk);
    default input #1step;
    input ev_frame, ev_crc, ev_drop, ev_det, ev_swap_done;
  endclocking

  clocking drv_cb @(posedge clk);
    output ev_frame, ev_crc, ev_drop, ev_det, ev_swap_done,
           stream_lock, lane_up, rm_sig, decouple_en;
  endclocking
endinterface : ctrl_if
