// ============================================================================
// Module: frame_check
// Description: RX framer/checker. Accepts 256-byte ICD frames (32 beats,
//              tlast on beat 31), verifies CRC32(B0..B247) against the CRC
//              field in beat 31, tracks sequence gaps, and forwards the 30
//              payload sample beats of good IQ frames (tlast on the last).
//              Corrupt / non-IQ frames are counted via event pulses and
//              swallowed. One frame of buffering (verify before forward);
//              double-buffering is a documented optimization exercise.
// ============================================================================
// Clock Domain: clk
// Reset: rst_n (active-low, synchronous)
// ============================================================================
module frame_check (
  input  logic           clk,
  input  logic           rst_n,
  // framed input from the link (32 beats, tlast on beat 31)
  input  logic           s_tvalid,
  output logic           s_tready,
  input  logic [63:0]    s_tdata,
  input  logic           s_tlast,
  // sample payload output (30 beats per good IQ frame, tlast on last)
  output logic           m_tvalid,
  input  logic           m_tready,
  output logic [63:0]    m_tdata,
  output logic           m_tlast,
  // event pulses to spec_ctrl (single cycle)
  output logic           o_ev_frame,   // good frame accepted
  output logic           o_ev_crc,     // corrupt frame rejected
  output logic           o_ev_drop     // sequence gap detected
);

  import sentry_defs::*;

  localparam int LAST = SAMPLE_BEATS - 1;   // index of final payload beat

  typedef enum logic [1:0] {FC_LOAD, FC_FLUSH, FC_EMIT} state_e;
  state_e state;

  logic [63:0]  fbuf [SAMPLE_BEATS];    // payload beats 1..30 of the frame
  logic [31:0]  crc_run;               // CRC over beats 0..30 so far
  logic [5:0]   in_cnt;                // input beat index 0..31
  logic [7:0]   f_type;
  logic [15:0]  f_seq, exp_seq;
  logic         seq_valid;
  logic         good_l, is_iq_l;
  logic [5:0]   out_cnt;

  // Input acceptance only while loading, and never while in reset
  assign s_tready = rst_n && (state == FC_LOAD);

  wire in_fire = s_tvalid && s_tready;

  // Beat 31 completes the frame: crc_run (register) already covers beats
  // 0..30; the CRC field rides in beat 31 tdata[31:0]; tlast must be set.
  wire frame_done = in_fire && (in_cnt == 6'd31);
  wire good_now   = ((crc_run ^ 32'hFFFF_FFFF) == s_tdata[31:0]) && s_tlast;
  // Early/missing tlast is treated as corruption and resynchronizes
  wire early_last = in_fire && s_tlast && (in_cnt != 6'd31);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state     <= FC_LOAD;
      crc_run   <= 32'hFFFF_FFFF;
      in_cnt    <= 6'd0;
      f_type    <= 8'h0;
      f_seq     <= 16'h0;
      exp_seq   <= 16'h0;
      seq_valid <= 1'b0;
      good_l    <= 1'b0;
      is_iq_l   <= 1'b0;
      out_cnt   <= 6'd0;
      o_ev_frame<= 1'b0;
      o_ev_crc  <= 1'b0;
      o_ev_drop <= 1'b0;
      m_tvalid  <= 1'b0;
      m_tlast   <= 1'b0;
      m_tdata   <= 64'h0;
      for (int i = 0; i < SAMPLE_BEATS; i++) fbuf[i] <= '0;
    end else begin
      // Event pulses are single-cycle
      o_ev_frame <= 1'b0;
      o_ev_crc   <= 1'b0;
      o_ev_drop  <= 1'b0;

      case (state)
        FC_LOAD: begin
          if (in_fire) begin
            if (in_cnt == 6'd0) begin
              f_seq  <= hdr_seq(s_tdata);
              f_type <= hdr_type(s_tdata);
            end
            if (in_cnt <= 6'd30)
              crc_run <= crc32_beat(crc_run, s_tdata);
            if (in_cnt >= 6'd1 && in_cnt <= 6'd30)
              fbuf[in_cnt - 6'd1] <= s_tdata;

            if (frame_done) begin
              good_l  <= good_now;
              is_iq_l <= (f_type == FT_IQ);
              in_cnt  <= 6'd0;
              crc_run <= 32'hFFFF_FFFF;
              state   <= FC_FLUSH;
            end else if (early_last) begin
              // Malformed length: count as corrupt, resync
              o_ev_crc <= 1'b1;
              in_cnt   <= 6'd0;
              crc_run  <= 32'hFFFF_FFFF;
            end else begin
              in_cnt <= in_cnt + 6'd1;
            end
          end
        end

        FC_FLUSH: begin
          if (good_l) begin
            o_ev_frame <= 1'b1;
            if (seq_valid && (f_seq != exp_seq))
              o_ev_drop <= 1'b1;
            exp_seq   <= f_seq + 16'd1;
            seq_valid <= 1'b1;
          end else begin
            o_ev_crc <= 1'b1;
          end
          out_cnt <= 6'd0;
          state   <= (good_l && is_iq_l) ? FC_EMIT : FC_LOAD;
        end

        FC_EMIT: begin
          if (!m_tvalid) begin
            m_tvalid <= 1'b1;
            m_tdata  <= fbuf[out_cnt];
            m_tlast  <= (out_cnt == LAST);
          end else if (m_tready) begin
            if (out_cnt == LAST) begin
              m_tvalid <= 1'b0;
              m_tlast  <= 1'b0;
              state    <= FC_LOAD;
            end else begin
              out_cnt  <= out_cnt + 6'd1;
              m_tdata  <= fbuf[out_cnt + 6'd1];
              m_tlast  <= (out_cnt + 6'd1 == LAST);
            end
          end
        end

        default: state <= FC_LOAD;
      endcase
    end
  end

endmodule : frame_check
