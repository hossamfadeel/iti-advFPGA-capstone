// ============================================================================
// tb_replay_gov.cpp -- self-checking: 16 frames in at rate 1 => 8 frames out,
// contents identical to the even-indexed input frames, in order.
// ============================================================================
#include <cstdio>
#include <cstdlib>
#include "replay_gov.h"

int main() {
    hls::stream<samp_t> in, out;
    const int NFRAMES = 16;
    samp_t ref[NFRAMES][GOV_SAMPS_PER_FRAME];
    for (int f = 0; f < NFRAMES; f++)
        for (int s = 0; s < GOV_SAMPS_PER_FRAME; s++) {
            samp_t v; v.i = (int16_t)(f * 100 + s); v.q = (int16_t)(-(f * 100) - s);
            ref[f][s] = v; in.write(v);
        }
    replay_gov(in, out, 1);

    int errs = 0, out_frames = 0;
    while (!out.empty()) {
        for (int s = 0; s < GOV_SAMPS_PER_FRAME; s++) {
            samp_t v = out.read();
            int f2 = (out_frames < NFRAMES / 2) ? out_frames * 2 : 0;
            if (out_frames >= NFRAMES / 2 ||
                v.i != ref[f2][s].i || v.q != ref[f2][s].q) {
                if (errs < 5)
                    printf("  mismatch frame %d samp %d\n", out_frames, s);
                errs++;
            }
        }
        out_frames++;
    }
    if (out_frames != NFRAMES / 2) {
        printf("FAIL: expected %d frames, got %d\n", NFRAMES / 2, out_frames);
        return 1;
    }
    if (errs == 0) {
        printf("PASS: replay_gov csim (16 in, 8 out at rate 1)\n");
        return 0;
    }
    printf("FAIL: replay_gov csim (%d mismatches)\n", errs);
    return 1;
}
