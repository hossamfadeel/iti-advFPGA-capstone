// ============================================================================
// tile_pack -- PSD rows -> 64x64 INT8 spectrogram tiles (RM3 feeder stage)
// 16:1 max-hold bin decimation per row, row-major tile, ICD tile record:
//   beat 0    = {tile_idx[15:0], 0xE7}
//   beats 1.. = 512 data beats (8 bytes each, little-endian)
// Exact model match: sw/golden/gen_vectors.py tile_pack_model (zero tolerance)
// ============================================================================
#pragma once
#include <stdint.h>
#include "hls_stream.h"
#include <ap_int.h>

#define TILE_ROWS    64
#define TILE_COLS    64
#define PSD_ROW_LEN  1024
#define DEC_FACTOR   16

void tile_pack(hls::stream<ap_uint<8> > &in_psd,
               ap_uint<16>               tile_idx,
               hls::stream<ap_uint<64> > &out_tile);
