// ============================================================================
// tile_pack.cpp -- PSD rows -> decimated 64x64 tile + ICD record framing
// ============================================================================
#include "tile_pack.h"

void tile_pack(hls::stream<ap_uint<8> > &in_psd,
               ap_uint<16>               tile_idx,
               hls::stream<ap_uint<64> > &out_tile) {
    ap_uint<8> tile[TILE_ROWS * TILE_COLS];

    // Read 64 PSD rows; 16:1 max-hold decimation per row
ROW: for (int r = 0; r < TILE_ROWS; r++) {
DEC: for (int g = 0; g < TILE_COLS; g++) {
            ap_uint<8> best = 0;
            for (int b = 0; b < DEC_FACTOR; b++) {
                ap_uint<8> v = in_psd.read();
                if (b == 0 || (uint32_t)v > (uint32_t)best) best = v;
            }
            tile[r * TILE_COLS + g] = best;   // per-group max (golden model)
        }
    }

    // Header beat: {tile_idx[15:0], magic 0xE7}
    ap_uint<64> hdr = ((ap_uint<64>)tile_idx << 8) | 0xE7;
    out_tile.write(hdr);

    // 512 data beats, 8 bytes each, little-endian, row-major
OUT: for (int k = 0; k < (TILE_ROWS * TILE_COLS) / 8; k++) {
        ap_uint<64> beat = 0;
        for (int i = 0; i < 8; i++)
            beat |= ((ap_uint<64>)tile[k * 8 + i]) << (8 * i);
        out_tile.write(beat);
    }
}
