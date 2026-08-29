// ============================================================================
// replay_gov -- Node A rate governor (HLS)
// Forwards 1 of every 2^k 60-sample frames (k = CTRL[7:4] rate_pow2),
// dropping the rest. Data passes through unmodified. Self-checked in csim.
// ============================================================================
#pragma once
#include <stdint.h>
#include "hls_stream.h"
#include <ap_int.h>

#define GOV_SAMPS_PER_FRAME 60

struct samp_t { int16_t i, q; };

void replay_gov(hls::stream<samp_t> &in, hls::stream<samp_t> &out,
                ap_uint<4> rate_pow2);
