// ============================================================================
// tb_tile_pack.cpp -- exact compare vs vectors/tile_golden.mem (513 beats)
// ============================================================================
#include <cstdio>
#include <cstdlib>
#include "tile_pack.h"

static const char *vecdir() {
    const char *e = getenv("SENTRY_VECTORS");
    return e ? e : "vectors";
}

int main() {
    char path[512];
    FILE *f;

    snprintf(path, sizeof(path), "%s/tile_in.mem", vecdir());
    f = fopen(path, "r");
    if (!f) { printf("FAIL: cannot open %s\n", path); return 1; }
    char row[4096];    // 1024 pairs + CRLF + margin (2048 truncated!)
    hls::stream<ap_uint<8> > in;
    int nrows = 0;
    while (nrows < TILE_ROWS && fgets(row, sizeof(row), f)) {
        for (int b = 0; b < PSD_ROW_LEN; b++) {
            unsigned v;
            sscanf(row + 2 * b, "%2x", &v);
            in.write((ap_uint<8>)v);
        }
        nrows++;
    }
    fclose(f);
    if (nrows != TILE_ROWS) { printf("FAIL: short input\n"); return 1; }

    snprintf(path, sizeof(path), "%s/tile_golden.mem", vecdir());
    f = fopen(path, "r");
    if (!f) { printf("FAIL: cannot open %s\n", path); return 1; }
    unsigned long long exp[513];
    for (int k = 0; k < 513; k++)
        if (fscanf(f, "%llx", &exp[k]) != 1) { printf("FAIL: short golden\n"); return 1; }
    fclose(f);

    hls::stream<ap_uint<64> > out;
    tile_pack(in, 0, out);

    int errs = 0;
    for (int k = 0; k < 513; k++) {
        ap_uint<64> got = out.read();
        if ((unsigned long long)got.to_uint64() != exp[k]) {
            if (errs < 5)
                printf("  mismatch beat %d: exp %016llx got %016llx\n", k,
                       exp[k], got.to_uint64());
            errs++;
        }
    }
    if (errs == 0) { printf("PASS: tile_pack csim (513 beats exact)\n"); return 0; }
    printf("FAIL: tile_pack csim (%d mismatches)\n", errs);
    return 1;
}
