// ============================================================================
// Package: sentry_defs
// Description: Shared constants, frame format, and CRC32 for SPECTRUM SENTRY.
//              Single source of truth for RTL, UVM, HLS, and golden vectors.
// ============================================================================
// Frame = 256 B = 32 beats x 64-bit, little-endian bytes:
//   B0      magic 0xA5
//   B1:B2   seq[15:0]        (LE)
//   B3      type: 0x01 IQ, 0x02 HEARTBEAT, 0x10 RM_ACK
//   B4:B7   timestamp[31:0]  (LE)
//   B8:B247 60 complex INT16 samples, packed I then Q (30 beats, 2 samps/beat)
//   B248:B251 CRC32 over B0..B247 (binascii.crc32-compatible)
//   B252:B255 zero pad
// ============================================================================
package sentry_defs;

  parameter int TDATA_W   = 64;
  parameter int FRAME_BEATS = 32;   // 64-bit beats per frame
  parameter int PAYLOAD_SAMPS = 60; // complex samples in payload
  parameter int SAMPLE_BEATS = FRAME_BEATS - 2; // 30

  parameter logic [7:0] MAGIC = 8'hA5;

  typedef enum logic [7:0] {
    FT_IQ    = 8'h01,
    FT_HB    = 8'h02,
    FT_RMACK = 8'h10
  } ftype_e;

  parameter logic [7:0] DET_MAGIC = 8'hD7; // detection record marker

  // ---- spec_ctrl register identifiers (offsets) ---------------------------
  typedef enum logic [5:0] {
    REG_ID        = 6'h00,
    REG_VERSION   = 6'h04,
    REG_CTRL      = 6'h08,
    REG_STATUS    = 6'h0C,
    REG_FRAME_CNT = 6'h10,
    REG_CRC_ERR   = 6'h14,
    REG_DROP_CNT  = 6'h18,
    REG_DET_COUNT = 6'h1C,
    REG_THR       = 6'h20,
    REG_TILE_RATE = 6'h24,
    REG_RM_SIG    = 6'h28,
    REG_IRQ_FLAGS = 6'h2C,
    REG_SCRATCH   = 6'h30,
    REG_RSVD0     = 6'h34,
    REG_RSVD1     = 6'h38,
    REG_RSVD2     = 6'h3C
  } regaddr_e;

  parameter logic [31:0] REG_ID_VAL      = 32'h53504543; // "SPEC"
  parameter logic [31:0] REG_VERSION_VAL = 32'h0001_0400; // v1.4.0
  parameter logic [31:0] RM1_SIG_VAL     = 32'h524D3100; // "RM1\0"

  // STATUS bits
  parameter int ST_STREAM_LOCK = 0;
  parameter int ST_LANE_UP     = 1;
  parameter int ST_RM_ACTIVE   = 2;
  parameter int ST_SWAPPING    = 8;

  // CTRL bits
  parameter int C_DET_ARM    = 0;
  parameter int C_IRQ_EN     = 1;
  parameter int C_BUILD_LO   = 2; // [3:2] 0=HP, 1=HPC
  parameter int C_RATE_LO    = 4; // [7:4] rate pow2

  // IRQ_FLAGS bits (RCW1)
  parameter int IRQ_FRAME     = 0;
  parameter int IRQ_CRC       = 1;
  parameter int IRQ_DET       = 2;
  parameter int IRQ_SWAP_DONE = 3;

  // ------------------------------------------------------------------------
  // CRC32, reflected, poly 0xEDB88320, init 0xFFFFFFFF, xorout 0xFFFFFFFF.
  // Bitwise update, one byte at a time. Matches binascii.crc32 (golden).
  // Note: 64 serial byte-updates per accepted beat is a long combinational
  // chain; pipelining it is a documented DSE exercise (see VERIFICATION_PLAN).
  // ------------------------------------------------------------------------
  function automatic logic [31:0] crc32_byte(logic [31:0] c, logic [7:0] b);
    logic [31:0] cc;
    cc = c ^ {24'h0, b};
    for (int i = 0; i < 8; i++) begin
      if (cc[0]) cc = (cc >> 1) ^ 32'hEDB8_8320;
      else       cc = cc >> 1;
    end
    return cc;
  endfunction

  // Update CRC over all 8 bytes of one 64-bit beat, byte 0 first.
  function automatic logic [31:0] crc32_beat(logic [31:0] c, logic [63:0] beat);
    logic [31:0] cc;
    cc = c;
    for (int b = 0; b < 8; b++) begin
      cc = crc32_byte(cc, beat[8*b +: 8]);
    end
    return cc;
  endfunction

  // Full-frame CRC (bytes B0..B247) given all 31 beats.
  function automatic logic [31:0] crc32_frame(logic [63:0] beats[31]);
    logic [31:0] c;
    c = 32'hFFFF_FFFF;
    for (int n = 0; n < 31; n++) c = crc32_beat(c, beats[n]);
    return c ^ 32'hFFFF_FFFF;
  endfunction

  // Extract seq/type/timestamp from header beat (beat 0).
  function automatic logic [7:0]  hdr_type(logic [63:0] h); return h[31:24]; endfunction
  function automatic logic [15:0] hdr_seq (logic [63:0] h); return h[23:8];  endfunction

endpackage : sentry_defs
