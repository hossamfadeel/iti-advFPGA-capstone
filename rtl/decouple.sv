// ============================================================================
// Module: decouple
// Description: Educational DFX decoupler. While decouple_en is asserted the
//              reconfigurable module is isolated: no new stream beats are
//              offered to it (m_tvalid forced low), no beats are accepted
//              from the static side (s_tready forced low), and rm_rstn is
//              released low so the RP is held in reset across the partial
//              bitstream load. Data is never dropped or duplicated: the
//              producer simply sees backpressure for the quiesce window.
// ============================================================================
// Clock Domain: clk
// Reset: rst_n (active-low, synchronous)
// ============================================================================
module decouple (
  input  logic           clk,
  input  logic           rst_n,
  // control from PS / swap state machine
  input  logic           decouple_en,
  output logic           rm_rstn,
  output logic           swapping,
  // static side (AXI4-Stream)
  input  logic           s_tvalid,
  output logic           s_tready,
  input  logic [63:0]    s_tdata,
  input  logic           s_tlast,
  // reconfigurable module side (AXI4-Stream)
  output logic           m_tvalid,
  input  logic           m_tready,
  output logic [63:0]    m_tdata,
  output logic           m_tlast
);

  // Two-flop synchronize the control input (treated as quasi-static)
  logic [2:0] en_sync;
  always_ff @(posedge clk) begin
    if (!rst_n) en_sync <= 3'b000;
    else        en_sync <= {en_sync[1:0], decouple_en};
  end

  wire hold = en_sync[2];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rm_rstn  <= 1'b0;   // system reset: RM held in reset (BUG FIX: was 1,
      swapping <= 1'b0;   // which X-poisoned the RM at power-up)
    end else begin
      rm_rstn  <= !hold;
      swapping <= hold;
    end
  end

  // Pass-through cut: combinational while running, fully gated while held.
  // An in-flight beat handshakes before the gate takes effect (en_sync
  // latency), so no data is lost at the boundary.
  assign m_tvalid = !hold && s_tvalid;
  assign m_tdata  = s_tdata;
  assign m_tlast  = s_tlast;
  assign s_tready = !hold && m_tready;

endmodule : decouple
