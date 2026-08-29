// ============================================================================
// tb_fft_psd.cpp -- csim testbench: exact compare vs golden integer vectors
// Reads: $SENTRY_VECTORS/fft_in.mem (1024 "i q" hex pairs)
//        $SENTRY_VECTORS/fft_golden_psd.mem (1024 psd bytes)
// PASS printed only on zero mismatches.
// ============================================================================
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "fft_psd.h"

static const char *vecdir() {
    const char *e = getenv("SENTRY_VECTORS");
    return e ? e : "vectors";
}

int main() {
    char path[512];
    FILE *f;

    snprintf(path, sizeof(path), "%s/fft_in.mem", vecdir());
    f = fopen(path, "r");
    if (!f) { printf("FAIL: cannot open %s\n", path); return 1; }
    sample_pair_t beat;
    int nsamp = 0;
    int16_t ri[SENTRY_NFFT], rq[SENTRY_NFFT];
    while (nsamp < SENTRY_NFFT) {
        unsigned short ui, uq;
        if (fscanf(f, "%hx %hx", &ui, &uq) != 2) break;
        ri[nsamp] = (int16_t)ui;  rq[nsamp] = (int16_t)uq;  // no aliasing UB
        nsamp++;
    }
    fclose(f);
    if (nsamp != SENTRY_NFFT) { printf("FAIL: short input (%d)\n", nsamp); return 1; }

    snprintf(path, sizeof(path), "%s/fft_golden_psd.mem", vecdir());
    f = fopen(path, "r");
    if (!f) { printf("FAIL: cannot open %s\n", path); return 1; }
    unsigned short exp[SENTRY_NFFT];
    for (int k = 0; k < SENTRY_NFFT; k++)
        if (fscanf(f, "%hx", &exp[k]) != 1) { printf("FAIL: short golden\n"); return 1; }
    fclose(f);

    hls::stream<sample_pair_t> in;
    hls::stream<ap_uint<8> >   psd;
    hls::stream<det_evt_t>     det;
    for (int b = 0; b < SENTRY_NFFT / 2; b++) {
        beat.i0 = ri[2*b];     beat.q0 = rq[2*b];
        beat.i1 = ri[2*b + 1]; beat.q1 = rq[2*b + 1];
        in.write(beat);
    }
    fft_psd(in, psd, 0x20000000, det);

    int errs = 0;
    for (int k = 0; k < SENTRY_NFFT; k++) {
        ap_uint<8> got = psd.read();
        if ((unsigned)got != (unsigned)exp[k]) {
            if (errs < 5)
                printf("  mismatch bin %d: exp %02x got %02x\n", k, exp[k], (unsigned)got);
            errs++;
        }
    }
    if (!det.empty()) {
        det_evt_t e = det.read();
        printf("  detection: bin=%u mag2=0x%x\n", e.bin, e.mag2);
    }
    if (errs == 0) { printf("PASS: fft_psd csim (%d psd bytes exact)\n", SENTRY_NFFT); return 0; }
    printf("FAIL: fft_psd csim (%d mismatches)\n", errs);
    return 1;
}
