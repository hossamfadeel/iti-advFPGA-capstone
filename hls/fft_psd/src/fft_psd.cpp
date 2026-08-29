// ============================================================================
// fft_psd.cpp -- 1024-pt INT FFT -> log2-PSD bytes + threshold detect
// Golden-matched integer arithmetic (see sw/golden/gen_vectors.py).
// ============================================================================
#include "fft_psd.h"
#include "twiddle_table.h"

// 8-bit pseudo-log: psd = min(255, floor(log2(v+1)) * 8)
// NOTE: v is 64-bit -- magnitudes reach ~9e14 (|X| up to ~3e7) and the
// golden model consumes the full value (the 32-bit cast truncated it).
static ap_uint<8> log2_8(uint64_t v) {
    uint64_t x = v + 1;
    uint32_t l = 0;
    while ((x >> (l + 1)) && l < 31) l++;
    uint32_t p = l * 8;
    return (p > 255) ? (ap_uint<8>)255 : (ap_uint<8>)p;
}

void fft_psd(hls::stream<sample_pair_t> &in_samps,
             hls::stream<ap_uint<8> >    &out_psd,
             int32_t                      thr,
             hls::stream<det_evt_t>      &out_det) {
    int32_t re[SENTRY_NFFT], im[SENTRY_NFFT];

    // ---- read one frame: 512 beats = 1024 samples -------------------------
READ: for (int b = 0; b < SENTRY_NFFT / 2; b++) {
        sample_pair_t p = in_samps.read();
        re[2*b]     = p.i0;  im[2*b]     = p.q0;
        re[2*b + 1] = p.i1;  im[2*b + 1] = p.q1;
    }

    // ---- bit-reverse permutation (10-bit reversal) -------------------------
    int32_t rt[SENTRY_NFFT], it[SENTRY_NFFT];
BITREV: for (int n = 0; n < SENTRY_NFFT; n++) {
        int r = 0;
        for (int k = 0; k < 10; k++)
            if (n & (1 << k)) r |= 1 << (9 - k);
        rt[n] = re[r];  it[n] = im[r];
    }

    // ---- radix-2 DIT stages -------------------------------------------------
STAGE: for (int s = 0; s < SENTRY_STAGES; s++) {
        int length = 2 << s;
        int half   = length >> 1;
        int stride = SENTRY_NFFT / length;
        for (int j = 0; j < SENTRY_NFFT; j += length) {
            for (int k = 0; k < half; k++) {
                int tw = k * stride;
                int a  = j + k;
                int b  = a + half;
                int32_t xr = rt[b], xi = it[b];
                int64_t tr = (((int64_t)TW_R[tw] * xr) - ((int64_t)TW_I[tw] * xi)) >> 15;
                int64_t ti = (((int64_t)TW_R[tw] * xi) + ((int64_t)TW_I[tw] * xr)) >> 15;
                rt[b] = rt[a] - (int32_t)tr;  it[b] = it[a] - (int32_t)ti;
                rt[a] = rt[a] + (int32_t)tr;  it[a] = it[a] + (int32_t)ti;
            }
        }
    }

    // ---- PSD + threshold detection -----------------------------------------
    uint32_t best = 0;  uint32_t best_bin = 0;
PSD: for (int k = 0; k < SENTRY_NFFT; k++) {
        int64_t m2 = ((int64_t)rt[k] * rt[k]) + ((int64_t)it[k] * it[k]);
        out_psd.write(log2_8((uint64_t)m2));
        if ((uint64_t)m2 > (uint64_t)best) { best = (uint32_t)m2; best_bin = k; }
    }
    if ((int64_t)best > (int64_t)thr) {
        det_evt_t e; e.bin = best_bin; e.mag2 = best;
        out_det.write(e);
    }
}
