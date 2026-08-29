// ============================================================================
// Module: frame_gen
// Description: TX framer (Node A replay + TB stimulus). Packs a raw
//              AXI4-Stream of complex INT16 sample beats (2 samples/beat)
//              into 256-byte ICD v1.0 frames:
//                beat 0      header {timestamp[31:0], type, seq[15:0], magic}
//                beats 1..30 payload samples (consumed from s_*)
//                beat 31     {32'h0 pad, CRC32 over bytes B0..B247}
//              CRC is computed incrementally over each accepted emitted beat.
// ============================================================================
// Clock Domain: clk
// Reset: rst_n (active-low, synchronous)
// ============================================================================
module frame_gen #(
  parameter logic [7:0] P_TYPE = 8'h01   // FT_IQ default; 8'h02 for heartbeat
) (
  input  logic           clk,
  input  logic           rst_n,
  // raw sample input (30 beats per frame; producer holds data until ready)
  input  logic           s_tvalid,
  output logic           s_tready,
  input  logic [63:0]    s_tdata,
  // framed output (32 beats per frame, tlast on beat 31)
  output logic           m_tvalid,
  input  logic           m_tready,
  output logic [63:0]    m_tdata,
  output logic           m_tlast,
  // status
  output logic [15:0]    o_seq
);

  import sentry_defs::*;

  typedef enum logic [1:0] {FG_HDR, FG_PAY, FG_CRCB} state_e;
  state_e state;

  logic [31:0] crc_run, crc_final;
  logic [4:0]  pay_cnt;            // payload beats emitted: 0..29
  logic [15:0] seq;

  assign o_seq = seq;

  // Combined handshake: the producer fills the output register when it is
  // empty OR draining this cycle. Data is captured ONLY on a real s-side
  // handshake -- never speculatively (the speculative copy duplicated beats
  // and shifted frame boundaries; found by the e2e gate, see VERIFICATION_PLAN).
  wire pay_accept = (state == FG_PAY) && m_tvalid && m_tready;
  assign s_tready = (state == FG_PAY) && (!m_tvalid || pay_accept);
  wire pay_load   = (state == FG_PAY) && s_tvalid && s_tready;

  wire [63:0] hdr_beat = {32'h0, P_TYPE, seq, MAGIC};

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state     <= FG_HDR;
      crc_run   <= 32'hFFFF_FFFF;
      crc_final <= 32'h0;
      pay_cnt   <= 5'd0;
      seq       <= 16'h0;
      m_tvalid  <= 1'b0;
      m_tlast   <= 1'b0;
      m_tdata   <= 64'h0;
    end else begin
      // Default: deassert valid once the current beat is accepted
      if (m_tvalid && m_tready) m_tvalid <= 1'b0;

      case (state)
        FG_HDR: begin
          if (!m_tvalid) begin
            m_tvalid <= 1'b1;
            m_tdata  <= hdr_beat;
            m_tlast  <= 1'b0;
            crc_run  <= 32'hFFFF_FFFF;   // reset CRC chain for this frame
          end else if (m_tready) begin
            crc_run  <= crc32_beat(32'hFFFF_FFFF, hdr_beat);
            pay_cnt  <= 5'd0;
            state    <= FG_PAY;
          end
        end

        FG_PAY: begin
          // (1) load: a real producer handshake fills the (empty or
          //     draining) output register
          if (pay_load) begin
            m_tvalid <= 1'b1;
            m_tdata  <= s_tdata;
            m_tlast  <= 1'b0;
          end else if (pay_accept) begin
            m_tvalid <= 1'b0;   // drained, nothing new offered
          end
          // (2) emit: fold the departing beat into the CRC
          if (pay_accept) begin
            crc_run <= crc32_beat(crc_run, m_tdata);
            if (pay_cnt == 5'd29) begin
              crc_final <= crc32_beat(crc_run, m_tdata) ^ 32'hFFFF_FFFF;
              state     <= FG_CRCB;
            end else begin
              pay_cnt <= pay_cnt + 5'd1;
            end
          end
        end

        FG_CRCB: begin
          if (!m_tvalid) begin
            m_tvalid <= 1'b1;
            m_tdata  <= crc_final;      // {pad=0, crc[31:0]}
            m_tlast  <= 1'b1;
          end else if (m_tready) begin
            seq   <= seq + 16'd1;
            state <= FG_HDR;
          end
        end

        default: state <= FG_HDR;
      endcase
    end
  end

endmodule : frame_gen
