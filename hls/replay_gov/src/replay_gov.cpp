// ============================================================================
// replay_gov.cpp -- frame-rate governor for the Node A replay engine
// ============================================================================
#include "replay_gov.h"

void replay_gov(hls::stream<samp_t> &in, hls::stream<samp_t> &out,
                ap_uint<4> rate_pow2) {
    uint32_t frame_idx = 0;
    uint32_t mask = (1u << (uint32_t)rate_pow2) - 1;

FRAME: while (!in.empty()) {
        bool forward = ((frame_idx & mask) == 0);
SAMP: for (int s = 0; s < GOV_SAMPS_PER_FRAME; s++) {
            samp_t v = in.read();
            if (forward) out.write(v);
        }
        frame_idx++;
    }
}
