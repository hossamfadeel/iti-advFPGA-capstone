// ============================================================================
// Module: rm1_energy
// Description: Behavioral RM1 "wideband energy detector" for the DFX slot.
//              Consumes sample frames (30 beats, 2 complex INT16 samples per
//              beat, tlast ends the frame), computes frame energy
//              E = sum(i^2 + q^2) >> 16 in exact integer math, and emits a
//              2-beat detection record per frame above THR:
//                beat0 = {40'h0, det_seq[15:0], 8'hD7}
//                beat1 = energy[31:0], tlast
//              The same integer model is replicated by the Python golden
//              generator (exact match, zero tolerance).
// ============================================================================
// Clock Domain: clk (pl_clk_dsp 250 MHz in the platform)
// Reset: rst_n (active-low, synchronous) -- driven by decouple.rm_rstn
// ============================================================================
module rm1_energy (
  input  logic           clk,
  input  logic           rst_n,
  // sample frame input (from frame_check via decouple)
  input  logic           s_tvalid,
  output logic           s_tready,
  input  logic [63:0]    s_tdata,
  input  logic           s_tlast,
  // detection record output (to S2MM DMA / coherent DDR)
  output logic           m_tvalid,
  input  logic           m_tready,
  output logic [63:0]    m_tdata,
  output logic           m_tlast,
  // control/status
  input  logic           i_det_arm,      // from spec_ctrl CTRL[0]
  input  logic [31:0]    i_thr,          // from spec_ctrl THR
  output logic           o_ev_det,       // pulse to spec_ctrl
  output logic [31:0]    o_rm_sig        // RM signature (STATUS[2] source)
);

  import sentry_defs::*;

  logic signed [63:0] acc;
  logic [15:0]        det_seq;
  logic [31:0]        energy_q;
  logic               emit_pending;
  logic               out_phase;      // 0: header beat, 1: energy beat

  assign o_rm_sig = RM1_SIG_VAL;
  assign s_tready = rst_n && !emit_pending; // no accepts in reset

  // Sample energy: sign-extend INT16 I/Q, return i^2 + q^2 (fits 32 bits)
  function automatic logic signed [31:0] samp2(input logic [15:0] i16,
                                               input logic [15:0] q16);
    logic signed [31:0] ii, qq;
    ii = {{16{i16[15]}}, i16};
    qq = {{16{q16[15]}}, q16};
    return ii*ii + qq*qq;
  endfunction

  wire in_fire = s_tvalid && s_tready;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      acc          <= 64'sd0;
      det_seq      <= 16'h0;
      energy_q     <= 32'h0;
      emit_pending <= 1'b0;
      out_phase    <= 1'b0;
      o_ev_det     <= 1'b0;
      m_tvalid     <= 1'b0;
      m_tlast      <= 1'b0;
      m_tdata      <= 64'h0;
    end else begin
      o_ev_det <= 1'b0;

      // Accumulate incoming samples
      if (in_fire) begin
        acc <= acc + 64'(samp2(s_tdata[15:0],  s_tdata[31:16]))
                   + 64'(samp2(s_tdata[47:32], s_tdata[63:48]));
        if (s_tlast) begin
          // Frame energy per contract: sum >> 16, lower 32 bits
          energy_q <= 32'((acc + 64'(samp2(s_tdata[15:0],  s_tdata[31:16]))
                               + 64'(samp2(s_tdata[47:32], s_tdata[63:48]))) >>> 16);
          if (i_det_arm &&
              (32'((acc + 64'(samp2(s_tdata[15:0],  s_tdata[31:16]))
                      + 64'(samp2(s_tdata[47:32], s_tdata[63:48]))) >>> 16) > i_thr)) begin
            emit_pending <= 1'b1;
            out_phase    <= 1'b0;
          end
        end
      end

      // Drain the pending detection record
      if (emit_pending && !m_tvalid) begin
        m_tvalid <= 1'b1;
        if (!out_phase) begin
          m_tdata  <= {40'h0, det_seq, DET_MAGIC};
          m_tlast  <= 1'b0;
        end else begin
          m_tdata  <= energy_q;
          m_tlast  <= 1'b1;
        end
      end else if (emit_pending && m_tvalid && m_tready) begin
        if (!out_phase) begin
          out_phase <= 1'b1;
          m_tvalid  <= 1'b0;   // one-cycle gap between record beats
        end else begin
          m_tvalid     <= 1'b0;
          emit_pending <= 1'b0;
          o_ev_det     <= 1'b1;
          det_seq      <= det_seq + 16'd1;
        end
      end

      // New frame accumulation starts fresh
      if (in_fire && s_tlast) acc <= 64'sd0;
    end
  end

endmodule : rm1_energy
