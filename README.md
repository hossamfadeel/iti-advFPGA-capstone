# ITI Advanced FPGA Capstone Project -- SPECTRUM SENTRY

**Information Technology Institute (ITI), Egypt** -- Advanced FPGA & Adaptive
SoC Engineering Workshop

A two-node real-time RF spectrum intelligence system on AMD Zynq UltraScale+
MPSoC (2x ZCU102): a fiber-coupled sensor head streams wideband digital I/Q at
line rate over an Aurora 64B/66B link to an edge node that runs a
**runtime-swappable detection engine** (partial reconfiguration / DFX) built
in **Vitis HLS**, classifies emitters with an **INT8 DNN on the DPU**
(Vitis AI), moves results through a **coherent HPC port** (CCI), and
publishes live detections to a host dashboard over **PCIe Gen3 x4 (XDMA)** --
built and regression-tested by a **scripted TCL + CI/CD flow** that gates
every merge on timing, simulation, and utilization.

Full specification: [docs/Capstone_Project_Spectrum_Sentry.md](docs/Capstone_Project_Spectrum_Sentry.md)
(the spec is authoritative; this repo is the implementation).

## System in one picture

```
 NODE A "Sensor Head"            NODE B "Edge Node"
 DDR IQ replay -> AXI DMA   ===Aurora 64B/66B @ 10.3125 Gb/s===>
 (ZCU102, SFP+ DAC)              RX framer -> [DFX SLOT: RM1/RM3/RM2*]
                                 -> AXI DMA S2MM -> HPC (coherent DDR)
                                 -> A53 Linux + DPU classifier
                                 -> PCIe x4 XDMA -> HOST dashboard
                                 (*RM2 = stretch)
```

## Repository layout (mirrors spec Section 5.8)

| Path | Owner | Contents |
|------|-------|----------|
| `hls/` | Team DSP | Vitis HLS kernels: `fft_psd`, `fir_chan` (stretch), `tile_pack`, `replay_gov`; each with `src/`, `tb/`, `run_hls.tcl` |
| `rtl/` | Team Platform | `spec_ctrl` (AXI4-Lite control/status IP), `decouple`, `frame_check`, `aurora_glue` |
| `sim/` | all teams | xsim testbenches; every TB must print PASS (CI gate) |
| `bd/` | Team Platform | non-project block design scripts: `node_a.tcl`, `node_b.tcl` |
| `constr/` | Team Platform + DFX | XDC files, DFX pblocks, false paths |
| `sw/` | Team AI/SW + Links | `a53_apps`, `host_dashboard`, `dpurt` (model + VART app) |
| `dfx/` | Team DFX | RM build configs, partial bitstream scripts, swap sequence |
| `ci/` | Team Platform | `build.tcl`, `gates/` (WNS, utilization), `regress.sh` |
| `data/` | (git-ignored) | IQ captures, RadioML subset -- instructor-provided, never committed |
| `docs/` | everyone | Capstone spec, ICD (frozen Day 2 17:00), reports |

## Quickstart (verified on AMD tools 2025.2, no board needed)

```bash
git clone https://github.com/hossamfadeel/iti-advFPGA-capstone
cd iti-advFPGA-capstone
make vectors       # regenerate golden vectors (python, seed 260)
make regress-uvm   # 4 UVM testbenches on xsim: every TB prints PASS
make regress-hls   # 4 HLS kernels csim via vitis-run: exact golden match
# or simply: make regress
```

Current status: ALL EIGHT GATES PASS (4 UVM TBs + 4 HLS csims, zero
tolerance) -- and they are BOARD-INDEPENDENT: the same regression is the
signoff for both ZCU102 and Kria KR260 (`make synth BOARD=kr260|zcu102`).
See docs/PROJECT_REPORT.md and docs/BOARDS.md.

## Documentation map

| Document | Purpose |
|----------|---------|
| docs/PROJECT_REPORT.md | the full report: what, why, when, where, how |
| docs/ARCHITECTURE.md | top-down spec: requirements -> architecture -> blocks |
| docs/DESIGN_FLOW.md | the V-model methodology, step by step (teaching) |
| docs/ICD.md | frozen interface control document |
| docs/VERIFICATION_PLAN.md | UVM architecture, test matrix, tool-issue log |
| docs/REPRODUCE.md | step-by-step reproduction + troubleshooting |
| docs/BOARDS.md | dual-board support: ZCU102 + Kria KR260 (delta table, 2x KR260 bring-up) |

Everything except bench milestones is board-independent: CI-first is the
scheduling philosophy of this project.

## The 2-week sprint at a glance

| Day | Gate |
|-----|------|
| 1 | Teams chartered; ICD drafted; kernels compile; CI skeleton green |
| 2 | **ICD FREEZE 17:00**; csim PASS; Aurora loopback clean; boards boot |
| 3 | DDR->Aurora->DDR >= 0.9 GB/s; spec_ctrl R/W from Linux |
| 4 | RM1 end-to-end in static fabric; host XDMA streaming; DSE v1 |
| 5 | First partial swap on bench; swap latency measured |
| 6 | RM1<->RM3 swap under traffic; link health clean |
| 7 | DPU classifying >= 100 tiles/s; HP vs HPC A/B measured |
| 8 | Full chain live -- all mandatory gates green |
| 9 | 30-min soak; timing clean; report finalized; stretch work |
| 10 | Demo day; sprint report; tag v1.0 from CI |

## CI gates (every PR)

1. `make csim` -- all HLS kernels vs golden vectors
2. `make regress` -- all xsim testbenches print PASS
3. Nightly / push-to-main synth: **WNS >= 0**, **util < 80%** every category,
   else the pipeline is red and the merge is blocked

## License / use

Internal ITI course material. For educational use by project participants.
