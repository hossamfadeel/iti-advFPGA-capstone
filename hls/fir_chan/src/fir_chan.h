// ============================================================================
// fir_chan -- polyphase channelizer (stretch kernel, feeds RM2)
// NCHAN=8 channels, decimation 8, NTAP=64 shared polyphase taps (Q15).
// y[c][m] = sum_t h[c + NCHAN*t] * x[DEC*m + NCHAN*t + c] >> 15
// Exact model match: sw/golden/gen_vectors.py fir_chan_model (zero tolerance)
// Output order: channel-major (chan 0 all outputs, then chan 1, ...).
// ============================================================================
#pragma once
#include <stdint.h>
#include "hls_stream.h"
#include <ap_int.h>

#define FC_NCHAN  8
#define FC_DEC    8
#define FC_NTAP   64
#define FC_NSAMP  1024

struct fc_samp_t { int16_t i, q; };

void fir_chan(hls::stream<fc_samp_t> &in,
              const int16_t coeff[FC_NTAP],
              hls::stream<fc_samp_t> &out);
