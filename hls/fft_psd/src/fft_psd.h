// ============================================================================
// fft_psd.h -- SPECTRUM SENTRY RM3 spectral kernel (HLS)
// 1024-pt radix-2 DIT complex FFT (INT16 in, INT32 internal, Q15 twiddles)
// -> log2-PSD bytes (8-bit pseudo-log) -> threshold detection.
// EXACT integer model: identical operation order to sw/golden/gen_vectors.py
// (bit-reverse permutation, stage order, >>15 arithmetic shifts), so csim
// compares against the golden vectors with ZERO tolerance.
// ============================================================================
#pragma once
#include <stdint.h>
#include "hls_stream.h"
#include <ap_int.h>

#define SENTRY_NFFT   1024
#define SENTRY_STAGES 10

// One input beat = 2 complex INT16 samples (matches the AXI-S dataplane)
struct sample_pair_t {
  int16_t i0, q0, i1, q1;
};

// Detection event: strongest bin above threshold in the current frame
struct det_evt_t {
  uint32_t bin;
  uint32_t mag2;
};

void fft_psd(hls::stream<sample_pair_t> &in_samps,
             hls::stream<ap_uint<8> >    &out_psd,
             int32_t                      thr,
             hls::stream<det_evt_t>      &out_det);
