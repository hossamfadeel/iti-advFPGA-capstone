#!/usr/bin/env python3
"""SPECTRUM SENTRY golden vector generator.

Single source of truth for test vectors consumed by the UVM testbenches and
the Vitis HLS C testbenches. All models are EXACT integer replications of the
RTL/HLS arithmetic (same operation order, same arithmetic right shifts), so
expected values compare with zero tolerance.

Outputs (under vectors/):
  frames_tx.mem          16 frames x 32 beats (64-bit hex/line), for tb_frame_check
  frames_rx_expected.mem payload beats of forwarded good IQ frames
  frames_tx_summary.txt  expected counters: GOOD/CRC/DROP/FWD_BEATS
  iq_stream.mem          15 frames x 30 raw sample beats, for tb_sentry_e2e
  det_expected.mem       expected RM1 detection records (2 beats each)
  e2e_summary.txt        THR, DET count, FRAME count for tb_sentry_e2e
  fft_in.mem             1024 lines "i q" (4-hex INT16 each)
  fft_golden_psd.mem     1024 psd bytes (exact int model of fft_psd kernel)
  tile_in.mem            64 PSD rows x 1024 bytes (128 hex chars/line)
  tile_golden.mem        expected tile_pack output beats
  fir_in.mem             1024 lines "i q" for fir_chan
  fir_golden.mem         expected channelizer output lines "i q"
  ../hls/fft_psd/src/twiddle_table.h   INT16 twiddle table shared by C++/python

Deterministic: numpy seed 260.
"""
import numpy as np
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VDIR = ROOT / "vectors"
VDIR.mkdir(exist_ok=True)

# ---- constants (must match rtl/sentry_defs.sv) -----------------------------
MAGIC = 0xA5
FT_IQ, FT_HB, FT_RMACK = 0x01, 0x02, 0x10
DET_MAGIC = 0xD7
NFFT = 1024
THR_DEFAULT = 0x00002000

# ---- exact CRC32 (binascii-compatible), bytes little-endian ----------------
def crc32_bytes(data: bytes, crc: int = 0xFFFFFFFF) -> int:
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xEDB88320 if crc & 1 else crc >> 1
    return crc ^ 0xFFFFFFFF

def beat_bytes_to_val(bs: bytes) -> int:
    return sum(b << (8 * i) for i, b in enumerate(bs))

def build_frame(seq: int, ftype: int, samples: list, corrupt: bool = False) -> list:
    """Build one 256-byte frame; return list of 32 64-bit beat values."""
    payload = bytearray()
    for (i, q) in samples:
        payload += int(i).to_bytes(2, "little", signed=True)
        payload += int(q).to_bytes(2, "little", signed=True)
    hdr = bytes([MAGIC]) + seq.to_bytes(2, "little") + bytes([ftype]) + (0).to_bytes(4, "little")
    body = hdr + bytes(payload)
    assert len(body) == 248
    crc = crc32_bytes(body)
    tail = crc.to_bytes(4, "little") + bytes(4)
    frame = body + tail
    if corrupt:
        fb = bytearray(frame)
        fb[248] ^= 0x01  # flip one CRC bit
        frame = bytes(fb)
    return [beat_bytes_to_val(frame[8 * k:8 * k + 8]) for k in range(32)]

# ---- exact RM1 energy model -------------------------------------------------
def frame_energy(samples) -> int:
    acc = 0
    for (i, q) in samples:
        acc += i * i + q * q
    return (acc >> 16) & 0xFFFFFFFF

# ---- exact int FFT model (matches fft_psd.cpp) ------------------------------
def gen_twiddles():
    k = np.arange(NFFT // 2)
    wr = np.round(np.cos(2 * np.pi * k / NFFT) * 32767).astype(np.int64)
    wi = np.round(-np.sin(2 * np.pi * k / NFFT) * 32767).astype(np.int64)
    return wr, wi

def fft_int(re, im, wr, wi):
    N = NFFT
    # bit-reverse permutation
    bits = 10
    idx = np.array([int(format(x, "010b")[::-1], 2) for x in range(N)])
    re = [re[i] for i in idx]
    im = [im[i] for i in idx]
    for s in range(10):
        length = 2 << s
        half = length >> 1
        tw_stride = N // length
        for j in range(0, N, length):
            for k in range(half):
                tw = k * tw_stride
                a = j + k
                b = j + half + k
                xr, xi = re[b], im[b]
                tr = ((int(wr[tw]) * xr - int(wi[tw]) * xi) >> 15)
                ti = ((int(wr[tw]) * xi + int(wi[tw]) * xr) >> 15)
                re[b] = re[a] - tr
                im[b] = im[a] - ti
                re[a] += tr
                im[a] += ti
    return re, im

def log2_8(m2: int) -> int:
    v = m2 + 1
    l = 0
    while (v >> (l + 1)) and l < 31:
        l += 1
    return min(255, l * 8)

def psd_row(re, im):
    return [log2_8(int(re[k]) * int(re[k]) + int(im[k]) * int(im[k])) for k in range(NFFT)]

# ---- exact tile_pack model ---------------------------------------------------
def tile_pack_model(rows):
    """rows: list of 1024-byte lists. Emits one 64x64 tile:
    decimate 16:1 by max-hold, row-major, plus a header beat."""
    tile = []
    for r in rows[:64]:
        dec = []
        for g in range(64):
            dec.append(max(r[g * 16:(g + 1) * 16]))
        tile.extend(dec)
    assert len(tile) == 4096
    beats = []
    hdr = (0xE7 << 0) | (0 << 8)  # {tile_idx=0, magic 0xE7}
    beats.append(hdr)
    for k in range(512):
        b = tile[8 * k:8 * k + 8]
        beats.append(sum(x << (8 * i) for i, x in enumerate(b)))
    return beats

# ---- exact fir_chan model ----------------------------------------------------
NCHAN, DEC, NTAP = 8, 8, 64

def fir_coeffs():
    n = np.arange(NTAP)
    h = np.sinc(0.25 * (n - NTAP / 2 + 0.5)) * np.blackman(NTAP)
    h /= np.max(np.abs(h))
    hr = np.round(h * 32767).astype(int)
    return hr

def fir_chan_model(re_in, im_in, hr):
    """Polyphase: channel c uses taps c, c+8, ... Output rate = N/DEC per chan."""
    outs = []
    n_in = len(re_in)
    n_out = n_in // DEC
    for c in range(NCHAN):
        for m in range(n_out):
            acc_r = acc_i = 0
            for t in range(NTAP // DEC):
                h = int(hr[c + NCHAN * t])
                pos = DEC * m + t * NCHAN + c  # strided access
                if pos < n_in:
                    acc_r += h * int(re_in[pos])
                    acc_i += h * int(im_in[pos])
            outs.append((acc_r >> 15, acc_i >> 15))
    return outs

# =============================================================================
def main():
    rng = np.random.default_rng(260)

    # ---- 1) frames for tb_frame_check --------------------------------------
    n_frames = 16
    frames, plan = [], []
    # plan: index -> (seq, type, corrupt); seq 11 is skipped (gap demo)
    seqs = list(range(17))
    del seqs[11]
    assert len(seqs) == 16
    for f in range(n_frames):
        ftype = FT_HB if f == 9 else FT_IQ
        corrupt = (f == 7)
        if ftype == FT_HB:
            samples = [(0, 0)] * 60
        else:
            i = rng.integers(-30000, 30000, 60).astype(int)
            q = rng.integers(-30000, 30000, 60).astype(int)
            samples = list(zip(i, q))
        frames.append(build_frame(seqs[f], ftype, samples, corrupt))
        plan.append((seqs[f], ftype, corrupt))

    with open(VDIR / "frames_tx.mem", "w") as f:
        for fr in frames:
            for b in fr:
                f.write(f"{b:016x}\n")

    # expected forwarded beats + counters (mirror frame_check RTL exactly)
    good = crc_err = drop = 0
    fwd = []
    exp_seq, seq_valid = None, False
    for (seq, ftype, corrupt) in plan:
        if corrupt:
            crc_err += 1
            continue
        good += 1
        if seq_valid and seq != exp_seq:
            drop += 1
        exp_seq, seq_valid = (seq + 1) & 0xFFFF, True
    # recompute forwarded payload beats: good && IQ frames
    fwd = []
    for (seq, ftype, corrupt), fr in zip(plan, frames):
        if not corrupt and ftype == FT_IQ:
            fwd.extend(fr[1:31])
    with open(VDIR / "frames_rx_expected.mem", "w") as f:
        for b in fwd:
            f.write(f"{b:016x}\n")
    with open(VDIR / "frames_tx_summary.txt", "w") as f:
        f.write(f"GOOD={good} CRC={crc_err} DROP={drop} FWD_BEATS={len(fwd)}\n")

    # ---- 2) iq stream + detections for tb_sentry_e2e -----------------------
    n_e2e = 15
    quiet = {2, 5, 9}   # low-energy frames: no detection expected
    i = rng.integers(-30000, 30000, (n_e2e, 60)).astype(int)
    q = rng.integers(-30000, 30000, (n_e2e, 60)).astype(int)
    for fidx in quiet:
        i[fidx] = rng.integers(-500, 500, 60)
        q[fidx] = rng.integers(-500, 500, 60)
    beats = []
    dets = []
    thr = THR_DEFAULT
    for fidx in range(n_e2e):
        samples = list(zip(i[fidx], q[fidx]))
        for p in range(30):
            beats.append((int(samples[2*p][0]) & 0xFFFF)
                         | ((int(samples[2*p][1]) & 0xFFFF) << 16)
                         | ((int(samples[2*p+1][0]) & 0xFFFF) << 32)
                         | ((int(samples[2*p+1][1]) & 0xFFFF) << 48))
        e = frame_energy(samples)
        if e > thr:
            dets.append(e)
    with open(VDIR / "iq_stream.mem", "w") as f:
        for b in beats:
            f.write(f"{b:016x}\n")
    with open(VDIR / "det_expected.mem", "w") as f:
        for n, e in enumerate(dets):
            f.write(f"{(0xD7 | (n << 8)):016x}\n")
            f.write(f"{e:016x}\n")
    with open(VDIR / "e2e_summary.txt", "w") as f:
        f.write(f"THR=0x{thr:08x} FRAMES={n_e2e} DET={len(dets)}\n")

    # ---- 3) FFT vectors + twiddle header ------------------------------------
    wr, wi = gen_twiddles()
    with open(ROOT / "hls/fft_psd/src/twiddle_table.h", "w") as f:
        f.write("// AUTO-GENERATED by sw/golden/gen_vectors.py -- do not edit\n")
        f.write("#pragma once\n#include <cstdint>\n")
        f.write(f"static const int16_t TW_R[{NFFT//2}] = {{\n")
        f.write(",".join(str(int(x)) for x in wr) + "\n};\n")
        f.write(f"static const int16_t TW_I[{NFFT//2}] = {{\n")
        f.write(",".join(str(int(x)) for x in wi) + "\n};\n")

    fi = rng.integers(-30000, 30000, NFFT).astype(int)
    fq = rng.integers(-30000, 30000, NFFT).astype(int)
    re, im = fft_int([int(x) for x in fi], [int(x) for x in fq], wr, wi)
    psd = psd_row(re, im)
    with open(VDIR / "fft_in.mem", "w") as f:
        for k in range(NFFT):
            f.write(f"{int(fi[k]) & 0xFFFF:04x} {int(fq[k]) & 0xFFFF:04x}\n")
    with open(VDIR / "fft_golden_psd.mem", "w") as f:
        for p in psd:
            f.write(f"{p:02x}\n")

    # ---- 4) tile_pack vectors -------------------------------------------------
    rows = []
    for r in range(64):
        row = np.zeros(NFFT, dtype=int)
        bin_idx = (r * 7 + 3) % NFFT
        row[bin_idx] = 200
        row[(bin_idx + 1) % NFFT] = 120
        row[bin_idx + 400] = 60
        rows.append(list(row))
    with open(VDIR / "tile_in.mem", "w") as f:
        for row in rows:
            f.write("".join(f"{b:02x}" for b in row) + "\n")
    tile_beats = tile_pack_model(rows)
    with open(VDIR / "tile_golden.mem", "w") as f:
        for b in tile_beats:
            f.write(f"{b:016x}\n")

    # ---- 5) fir_chan vectors ---------------------------------------------------
    ci = rng.integers(-20000, 20000, 2048).astype(int)
    cq = rng.integers(-20000, 20000, 2048).astype(int)
    hr = fir_coeffs()
    outs = fir_chan_model([int(x) for x in ci[:1024]], [int(x) for x in cq[:1024]], hr)
    with open(VDIR / "fir_in.mem", "w") as f:
        for k in range(1024):
            f.write(f"{int(ci[k]) & 0xFFFF:04x} {int(cq[k]) & 0xFFFF:04x}\n")
    with open(VDIR / "fir_golden.mem", "w") as f:
        for (r_, i_) in outs:
            f.write(f"{r_ & 0xFFFF:04x} {i_ & 0xFFFF:04x}\n")

    # summary
    print("frames_tx.mem      :", n_frames, "frames")
    print("frames_rx_expected :", len(fwd), "beats")
    print("counters           : GOOD=%d CRC=%d DROP=%d" % (good, crc_err, drop))
    print("iq_stream.mem      :", len(beats), "beats")
    print("detections         :", len(dets), "of", n_e2e, "frames (THR=0x%x)" % thr)
    print("fft vectors        :", NFFT, "samples /", NFFT, "psd bytes")
    print("tile vectors       : 1 tile,", len(tile_beats), "beats")
    print("fir vectors        : 1024 in ->", len(outs), "out")
    print("OK")

if __name__ == "__main__":
    main()
