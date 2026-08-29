// ============================================================================
// fir_chan.cpp -- 8-channel polyphase complex channelizer
// ============================================================================
#include "fir_chan.h"

void fir_chan(hls::stream<fc_samp_t> &in,
              const int16_t coeff[FC_NTAP],
              hls::stream<fc_samp_t> &out) {
    static fc_samp_t x[FC_NSAMP];

READ: for (int n = 0; n < FC_NSAMP; n++)
        x[n] = in.read();

CHAN: for (int c = 0; c < FC_NCHAN; c++) {
OUT:  for (int m = 0; m < FC_NSAMP / FC_DEC; m++) {
            int64_t ar = 0, ai = 0;
TAP:      for (int t = 0; t < FC_NTAP / FC_NCHAN; t++) {
                int pos = FC_DEC * m + FC_NCHAN * t + c;
                if (pos < FC_NSAMP) {
                    int32_t h = coeff[c + FC_NCHAN * t];
                    ar += (int64_t)h * x[pos].i;
                    ai += (int64_t)h * x[pos].q;
                }
            }
            fc_samp_t o;
            o.i = (int16_t)(ar >> 15);
            o.q = (int16_t)(ai >> 15);
            out.write(o);
        }
    }
}
