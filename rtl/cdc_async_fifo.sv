// ============================================================================
// Module: cdc_async_fifo
// Description: Gray-coded dual-clock FIFO (Cummings style) with an AXI-Stream
//              tlast sideband bit -- exactly what an Aurora 64B/66B user
//              interface preserves across the link. Used for the Aurora
//              user-clock (156.25 MHz) -> DSP-clock (250 MHz) crossing.
//              Two-flop pointer synchronizers; pessimistic-but-safe flags.
//              Course CDC knowledge (gray pointers, async FIFO, MTBF) reused.
// ============================================================================
// Clock Domain: wr_clk / rd_clk (asynchronous to each other)
// Reset: rst_n (active-low, asynchronous assert, synchronous deassert per
//        domain via the two-flop synchronizers)
// Note : DEPTH >= 4 required (pointer MSB-pair comparison).
// ============================================================================
module cdc_async_fifo #(
  parameter int TDW   = 64,
  parameter int DEPTH = 16,
  parameter int AW    = $clog2(DEPTH)
) (
  input  logic           wr_clk,
  input  logic           rst_n,
  input  logic           wr_en,
  input  logic [TDW-1:0] wr_data,
  input  logic           wr_tlast,
  output logic           wr_full,
  input  logic           rd_clk,
  input  logic           rd_en,
  output logic [TDW-1:0] rd_data,
  output logic           rd_tlast,
  output logic           rd_empty
);

  logic [AW:0] wbin, wgray, rbin, rgray;
  logic [AW:0] wq1_rgray, wq2_rgray, rq1_wgray, rq2_wgray;
  logic [AW:0] wbin_next, wgray_next, rbin_next, rgray_next;
  logic        wfull, rempty;
  logic [TDW:0] mem [DEPTH];   // {tlast, tdata}

  initial for (int i = 0; i < DEPTH; i++) mem[i] = '0;

  // ---- write domain -------------------------------------------------------
  assign wbin_next  = wbin + {{AW{1'b0}}, (wr_en & ~wfull)};
  assign wgray_next = (wbin_next >> 1) ^ wbin_next;

  always_ff @(posedge wr_clk or negedge rst_n) begin
    if (!rst_n) begin
      wbin  <= '0;
      wgray <= '0;
    end else begin
      wbin  <= wbin_next;
      wgray <= wgray_next;
    end
  end

  // read-gray pointer synchronized into write domain (two-flop)
  always_ff @(posedge wr_clk or negedge rst_n) begin
    if (!rst_n) begin
      wq1_rgray <= '0;
      wq2_rgray <= '0;
    end else begin
      wq1_rgray <= rgray;
      wq2_rgray <= wq1_rgray;
    end
  end

  // full when next write gray equals read gray with the two MSBs inverted
  assign wfull = (wgray_next == {~wq2_rgray[AW:AW-1], wq2_rgray[AW-2:0]});

  always_ff @(posedge wr_clk) begin
    if (wr_en & ~wfull) mem[wbin[AW-1:0]] <= {wr_tlast, wr_data};
  end

  assign wr_full = wfull;

  // ---- read domain --------------------------------------------------------
  assign rbin_next  = rbin + {{AW{1'b0}}, (rd_en & ~rempty)};
  assign rgray_next = (rbin_next >> 1) ^ rbin_next;

  always_ff @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) begin
      rbin  <= '0;
      rgray <= '0;
    end else begin
      rbin  <= rbin_next;
      rgray <= rgray_next;
    end
  end

  // write-gray pointer synchronized into read domain (two-flop)
  always_ff @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) begin
      rq1_wgray <= '0;
      rq2_wgray <= '0;
    end else begin
      rq1_wgray <= wgray;
      rq2_wgray <= rq1_wgray;
    end
  end

  assign rempty  = (rgray == rq2_wgray);
  assign rd_empty = rempty;
  assign {rd_tlast, rd_data} = mem[rbin[AW-1:0]];

endmodule : cdc_async_fifo
