// ============================================================================
// tb_fir_chan.cpp -- exact compare vs vectors/fir_golden.mem (1024 "i q")
// Coefficients from vectors/fir_coeffs.mem (the same taps the golden model
// used -- generated once, consumed everywhere: single source of truth).
// ============================================================================
#include <cstdio>
#include <cstdlib>
#include "fir_chan.h"

static const char *vecdir() {
    const char *e = getenv("SENTRY_VECTORS");
    return e ? e : "vectors";
}

int main() {
    char path[512];
    FILE *f;

    snprintf(path, sizeof(path), "%s/fir_coeffs.mem", vecdir());
    f = fopen(path, "r");
    if (!f) { printf("FAIL: cannot open %s\n", path); return 1; }
    int16_t coeff[FC_NTAP];
    for (int k = 0; k < FC_NTAP; k++)
        if (fscanf(f, "%hx", (unsigned short *)&coeff[k]) != 1) {
            printf("FAIL: short coeffs\n"); return 1;
        }
    fclose(f);

    snprintf(path, sizeof(path), "%s/fir_in.mem", vecdir());
    f = fopen(path, "r");
    if (!f) { printf("FAIL: cannot open %s\n", path); return 1; }
    hls::stream<fc_samp_t> in;
    for (int n = 0; n < FC_NSAMP; n++) {
        unsigned short ri, rq;
        if (fscanf(f, "%hx %hx", &ri, &rq) != 2) { printf("FAIL: short in\n"); return 1; }
        fc_samp_t v; v.i = (int16_t)ri; v.q = (int16_t)rq;
        in.write(v);
    }
    fclose(f);

    snprintf(path, sizeof(path), "%s/fir_golden.mem", vecdir());
    f = fopen(path, "r");
    if (!f) { printf("FAIL: cannot open %s\n", path); return 1; }

    hls::stream<fc_samp_t> out;
    fir_chan(in, coeff, out);

    int errs = 0;
    for (int n = 0; n < FC_NCHAN * (FC_NSAMP / FC_DEC); n++) {
        unsigned short ei, eq;
        if (fscanf(f, "%hx %hx", &ei, &eq) != 2) { printf("FAIL: short golden\n"); return 1; }
        fc_samp_t got = out.read();
        if ((uint16_t)got.i != ei || (uint16_t)got.q != eq) {
            if (errs < 5)
                printf("  mismatch %d: exp %04x %04x got %04x %04x\n", n,
                       ei, eq, (uint16_t)got.i, (uint16_t)got.q);
            errs++;
        }
    }
    fclose(f);
    if (errs == 0) {
        printf("PASS: fir_chan csim (%d outputs exact)\n",
               FC_NCHAN * (FC_NSAMP / FC_DEC));
        return 0;
    }
    printf("FAIL: fir_chan csim (%d mismatches)\n", errs);
    return 1;
}
