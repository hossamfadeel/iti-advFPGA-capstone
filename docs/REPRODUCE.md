# REPRODUCE.md -- step-by-step reproduction of SPECTRUM SENTRY

Everything below runs **without an FPGA board**. The UVM environment is the
virtual ZCU102; HLS csim verifies the spectral datapath in C++.

## 0. Prerequisites

| Requirement | Used here | Notes |
|---|---|---|
| AMD tools 2025.2 | `C:\AMDDesignTools\2025.2` | Vivado (xsim) + Vitis (HLS via vitis-run). Override with `AMD_TOOLS=<path>` env var |
| Python 3 + numpy | any recent | golden vector generation, seed 260 |
| Git bash / MSYS | Windows shell used for scripts | scripts are bash |
| OS | Windows (this build); Linux works with path tweaks | xsim quirks are Windows-specific where noted |

Clean clone test (the DESIGN_FLOW.md rule):

```bash
git clone https://github.com/hossamfadeel/iti-advFPGA-capstone
cd iti-advFPGA-capstone
```

## 1. Golden vectors (deterministic, seed 260)

```bash
python sw/golden/gen_vectors.py
```

Expected tail:
```
frames_tx.mem      : 16 frames
frames_rx_expected : 420 beats
counters           : GOOD=15 CRC=1 DROP=2
iq_stream.mem      : 450 beats
detections         : 12 of 15 frames (THR=0x2000)
...
OK
```
Outputs land in `vectors/` (committed, so this step is optional for
reproduction but mandatory after changing the generator).

## 2. UVM regression (4 testbenches)

```bash
./ci/regress_uvm.sh            # all four
./ci/regress_uvm.sh tb_spec_ctrl   # one at a time while debugging
```

What it does: compiles the bundled UVM 1.2 with `-d UVM_NO_DPI` (pure SV),
compiles RTL+env+TBs, elaborates each TB with `--timescale 1ns/1ps`, runs
each with a 600 s timeout, kills zombie simulators, uses a unique sim dir
per run, and copies `vectors/` next to the run directory.

Expected output:
```
PASS: tb_spec_ctrl   (PASS: spec_ctrl_test (UVM_ERROR count is zero))
PASS: tb_frame_check (PASS: frame_check_test (UVM_ERROR count is zero))
PASS: tb_decouple    (PASS: decouple_test (UVM_ERROR count is zero))
PASS: tb_sentry_e2e  (PASS: e2e_test (UVM_ERROR count is zero))
UVM REGRESSION: PASS
```
Logs: `build/logs/<tb>_run.log` (reports, coverage summary, UVM report
counts at the end of each log).

## 3. HLS csim regression (4 kernels)

```bash
./ci/regress_hls.sh             # all four
./ci/regress_hls.sh fft_psd     # one kernel
```

Uses `vitis-run --tcl run_hls.tcl` (2025.x unified CLI replaces
`vitis_hls -f`). Expected:
```
PASS: fft_psd    (PASS: fft_psd csim (1024 psd bytes exact))
PASS: tile_pack  (PASS: tile_pack csim (513 beats exact))
PASS: replay_gov (PASS: replay_gov csim (16 in, 8 out at rate 1))
PASS: fir_chan   (PASS: fir_chan csim (1024 outputs exact))
HLS REGRESSION: PASS
```

For synthesis (schedule reports, Latency/II/DSP columns -- the DSE
exercise): uncomment `csynth_design` in each `hls/*/run_hls.tcl` and rerun;
reports land in `hls/<k>/<proj>/<sol>/syn/report/`.

## 4. One-command everything

```bash
make vectors && make regress
```

## 5. Synthesis path (needs the tools; board not required)

```bash
make synth    # non-project synth checkpoint + utilization/timing reports
make impl     # place/route; gates on WNS >= 0 before writing the bitstream
```
Block-design skeletons: `bd/node_a.tcl`, `bd/node_b.tcl`; constraints:
`constr/node_a.xdc`, `constr/node_b.xdc` (clocks, CDC false paths).

## 6. Hardware bring-up (when ZCU102 boards are available)

Follow the capstone plan (docs/Capstone_Project_Spectrum_Sentry.md):
Aurora 64B/66B GT wrapper (Lab05 flow) replaces the TB's CDC FIFO link;
DFX slot implementation per Lab01; DMA software per Lab03/04 (HP vs HPC
experiments); Vitis AI per Lab06. The UVM gates remain the signoff for
every RTL change.

## 7. Troubleshooting (real issues seen on this setup)

| Symptom | Cause / fix |
|---|---|
| "UVM_REGRESSION: FAIL (elaboration)" with timescale errors | pass `--timescale 1ns/1ps` to xelab (the script does) |
| Hang at t=0 with `-L uvm` precompiled | known; compile bundled UVM with `-d UVM_NO_DPI` instead (the script does) |
| `Device or resource busy` cleaning xsim.dir | zombie xsim process; the script force-kills xsim* before building |
| xsim "Expected a switch but found C" | Windows plusarg mangling; run without plusargs, ensure `vectors/` is in the CWD (script copies it) |
| LSP/clangd errors on hls/*.h | expected: clangd has no Vitis include paths; csim is the authority |
| HLS csim "file not found" for kernel header | TB needs `-cflags "-Isrc"` (already in run_hls.tcl) |
