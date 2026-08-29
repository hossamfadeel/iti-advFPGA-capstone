// ============================================================================
// Module: skid_buffer
// Description: Classic full AXI4-Stream skid buffer (two-register, capacity 2).
//              Accepts one beat even while the consumer stalls, so neither
//              side combinationally depends on the other. Throughput II=1.
//              Invariant: b_valid -> a_valid.
// ============================================================================
// Clock Domain: clk
// Reset: rst_n (active-low, synchronous)
// ============================================================================
module skid_buffer #(
  parameter int TDW = 64
) (
  input  logic           clk,
  input  logic           rst_n,
  input  logic           s_tvalid,
  output logic           s_tready,
  input  logic [TDW-1:0] s_tdata,
  input  logic           s_tlast,
  output logic           m_tvalid,
  input  logic           m_tready,
  output logic [TDW-1:0] m_tdata,
  output logic           m_tlast
);

  logic           a_valid, a_last, b_valid, b_last;
  logic [TDW-1:0] a_data,  b_data;

  assign m_tvalid = a_valid;
  assign m_tdata  = a_data;
  assign m_tlast  = a_last;

  // Room for the incoming beat if the skid register is empty. Because
  // b_valid -> a_valid, !a_valid implies !b_valid, so this covers both slots.
  assign s_tready = !b_valid;

  wire accept = s_tready && s_tvalid;   // incoming beat lands this cycle
  wire drain  = a_valid && m_tready;    // primary consumed this cycle

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      a_valid <= 1'b0;
      b_valid <= 1'b0;
    end else begin
      // Skid slides into a drained primary (or primary simply empties)
      if (drain) begin
        a_valid <= b_valid;
        a_data  <= b_data;
        a_last  <= b_last;
        b_valid <= 1'b0;
      end
      // Capture the accepted incoming beat
      if (accept) begin
        if (!a_valid || drain) begin
          // Primary slot is free at end of cycle
          if (b_valid) begin
            // b slides to a; incoming takes the freed skid slot
            b_valid <= 1'b1;
            b_data  <= s_tdata;
            b_last  <= s_tlast;
          end else begin
            a_valid <= 1'b1;
            a_data  <= s_tdata;
            a_last  <= s_tlast;
          end
        end else begin
          // Primary occupied and stalled: incoming parks in the skid
          b_valid <= 1'b1;
          b_data  <= s_tdata;
          b_last  <= s_tlast;
        end
      end
    end
  end

endmodule : skid_buffer
