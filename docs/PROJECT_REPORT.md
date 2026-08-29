# SPECTRUM SENTRY -- Project Report

**ITI Advanced FPGA Capstone -- iti-advFPGA-capstone**
**Platform: AMD Zynq UltraScale+ MPSoC (2x ZCU102) -- verified on AMD tools 2025.2**
**Verification substitute for hardware: full UVM environment (the "virtual ZCU102")**

This report explains the project along the five questions a reviewer,
interviewer, or new team member asks: **WHAT** it is, **WHY** each decision
was made, **WHEN** things happen (flow and schedule), **WHERE** everything
lives (code, docs, tools), and **HOW** it was built, verified, and
reproduced. Companion documents: `ARCHITECTURE.md` (specification),
`DESIGN_FLOW.md` (methodology), `ICD.md` (interfaces), `REPRODUCE.md`
(step-by-step commands).

---

## 1. WHAT -- the system, in layers

### 1.1 What the project is

A two-node real-time RF spectrum intelligence system, designed top-down and
verified bottom-up with UVM before any hardware is touched:

- **Node A (sensor head)** replays wideband digital I/Q from DDR through a
  rate governor, frames it (256-byte CRC32-protected frames), and ships it
  over an Aurora-class serial link.
- **Node B (edge node)** verifies every frame (CRC + sequence tracking),
  counts good/corrupt/dropped frames in software-visible registers, feeds
  the payload through a **runtime-swappable detection slot** (DFX), and
  emits detection records to a coherent DMA path -- all controlled through
  an AXI4-Lite register file that models the real PS control plane.
- A **Vitis HLS datapath** (1024-pt integer FFT -> log2-PSD -> spectrogram
  tiles; polyphase channelizer; rate governor) is verified bit-exact against
  Python golden models and packaged for the same streaming infrastructure.

### 1.2 What was actually built and verified (inventory)

| Layer | Artifacts | Verification gate | Status |
|---|---|---|---|
| Definition | ARCHITECTURE.md, ICD.md, DESIGN_FLOW.md | review | done |
| Golden models | `sw/golden/gen_vectors.py` (seed 260): CRC32, frame energy, int-FFT, FIR, tile packing | cross-domain consistency | done |
| RTL (8 modules) | sentry_defs, skid_buffer, cdc_async_fifo (tlast sideband), spec_ctrl, frame_gen, frame_check, decouple, rm1_energy | 4 UVM tests | **all PASS** |
| UVM environment | passive AXI-Lite monitor + coverage, RAL (16 regs) + adapter + predictor, stream agents, 2 scoreboards, 4 tests | `ci/regress_uvm.sh` | **all PASS** |
| HLS datapath | fft_psd (1024-pt), tile_pack, replay_gov, fir_chan | `ci/regress_hls.sh` csim, zero tolerance | **all PASS** |
| Platform intent | constr/*.xdc (clocks, CDC false paths), bd/*.tcl (PS+DMA+interconnect skeletons) | Vivado gates (WNS, util) | for hardware stage |
| CI | regress scripts + WNS/utilization gates + GitHub Actions workflow | clean clone builds | done |

### 1.3 What the numbers say (measured in simulation, zero tolerance)

| Check | Result |
|---|---|
| frame_check: forwarded payload beats vs golden | 420/420 exact |
| Counters (good/corrupt/drop) DUT vs UVM model vs Python | 15/1/2 == 15/1/2 == 15/1/2 |
| DFX decoupler: live swaps under traffic | 3 swaps, 0 lost, 0 duplicated beats |
| spec_ctrl registers: RO/RW/W1C + event counters | 16/16 checks OK; RAL mirror tracks bus via predictor |
| End-to-end chain (frame_gen->CDC->frame_check->decouple->rm1) | 15/15 frames, 12/12 detections, 24/24 detection beats exact, CRC_ERR=0 |
| fft_psd csim | 1024/1024 PSD bytes exact vs Python int-FFT |
| tile_pack csim | 513/513 beats exact |
| fir_chan csim | 1024/1024 outputs exact |
| replay_gov csim | 16 frames in, correct 8 out at rate 1 |

---

## 2. WHY -- decisions and their reasons

| Decision | Why |
|---|---|
| Top-down definition, bottom-up integration (V-model) | Big systems fail at interfaces; freeze the ICD first, then never integrate unverified blocks (see DESIGN_FLOW.md) |
| 256-byte frames = 32 x 64-bit beats | Beat-aligned boundaries eliminate an entire class of corner cases before any code exists |
| CRC32 (binascii-compatible) | One CRC definition checkable by RTL, UVM, HLS, and Python -- the golden vector can never quietly disagree with the DUT |
| Exact integer arithmetic everywhere (no floats) | Zero-tolerance comparison possible: a mismatch is always a real bug, never "tolerance noise" |
| UVM as the virtual ZCU102 | Course constraint: hardware may not be available; the environment drives/checks the same interfaces (AXI-Lite via RAL-style access, AXI-S with random backpressure) the real PS/DMA would |
| Random-ready sink + random gaps in stimulus | Backpressure is where AXI bugs live; coverage crosses frame length x backpressure |
| Two independent checkers (golden file + protocol model) | A checker written from the ICD, not from the DUT, catches spec-vs-implementation divergence |
| Detection records carry energy = (sum(i^2+q^2))>>16 | Exact integer contract published in the ICD and replicated in Python -- the e2e gate compares it with zero tolerance |
| Mailbox/clocking-block stimulus instead of uvm_sequencer | The UVM build bundled with xsim 2025.2 deadlocks in the sequencer rendezvous (documented in VERIFICATION_PLAN); the checking architecture is unaffected |
| HLS kernels verified by csim against the SAME vectors as RTL | The spectrum datapath must agree with the framing datapath's world: one source of truth (gen_vectors.py) |

---

## 3. WHEN -- the flow, and what happened at each stage

| Stage (per DESIGN_FLOW.md) | What happened | Bugs found (by the gate that found them) |
|---|---|---|
| 1-5 Define | Requirements R1-R10 each mapped to a test; architecture, ICD, verification architecture, repo+CI skeleton | -- |
| 6 CI-first | regress scripts before content; every later step ran through them | -- |
| 7 Leaf utilities | CRC in shared package; skid buffer; CDC gray FIFO **with tlast sideband** | tlast would have died at integration if forgotten in the spec |
| 8 Unit blocks | spec_ctrl, frame_check, decouple verified alone | AXI-Lite rvalid race (DUT retires rvalid in 1 cycle with rready high; driver must qualify both in one wait); DUTs accepting beats during reset (frame_check, rm1) |
| 9 Subsystem | link chain wired in TB | -- |
| 10 System e2e | full chain + PS-style configuration via registers | **decouple released rm_rstn during system reset -> RM1 never reset -> X-poisoned handshake deadlock** (found by heartbeat probe); **frame_gen copied producer data without a handshake -> duplicated beats, FRAME_CNT=17 instead of 15** (survived unit tests; caught by e2e golden counters) |
| 11 HLS datapath | 4 kernels, csim-exact | log2_8 truncated int64 magnitudes through uint32 (found by golden mismatch pattern); tile max-hold not reset per group; TB line buffer truncated CRLF lines; strict-aliasing UB in testbench parse |
| 12 Regression | one command, all gates green; committed and tagged | -- |

The two e2e-found bugs are the course's best teaching moments: both were
*unit-invisible protocol bugs* that only manifest when subsystems meet --
the exact reason the integration gate exists.

---

## 4. WHERE -- everything lives

| Thing | Where |
|---|---|
| System spec / ICD / methodology | `docs/ARCHITECTURE.md`, `docs/ICD.md`, `docs/DESIGN_FLOW.md` |
| This report + verification plan + reproduction | `docs/PROJECT_REPORT.md`, `docs/VERIFICATION_PLAN.md`, `docs/REPRODUCE.md` |
| RTL (8 modules) | `rtl/*.sv` |
| UVM env + 4 TB tops | `uvm/sentry_ifs.sv`, `uvm/sentry_uvm_pkg.sv`, `uvm/tb_*.sv` |
| HLS kernels | `hls/{fft_psd,tile_pack,replay_gov,fir_chan}/` (src, tb, run_hls.tcl) |
| Golden vector generator (seed 260) | `sw/golden/gen_vectors.py`; outputs in `vectors/` |
| Regressions | `ci/regress_uvm.sh` (xsim+UVM), `ci/regress_hls.sh` (vitis-run csim) |
| Vivado non-project build + gates | `ci/build.tcl`, `ci/gates/`, `Makefile` |
| Constraints / block designs | `constr/*.xdc`, `bd/*.tcl` |
| CI workflow | `.github/workflows/fpga.yml` |
| Tools on this machine | `C:\AMDDesignTools\2025.2` (Vivado xsim + Vitis via `vitis-run`) |
| Repository | https://github.com/hossamfadeel/iti-advFPGA-capstone (private) |

---

## 5. HOW -- build, verify, reproduce

Prerequisites: AMD tools 2025.2 (Vivado incl. xsim, Vitis incl. HLS) at
`C:\AMDDesignTools\2025.2` (override with `AMD_TOOLS=`), Python 3 with numpy.

```bash
git clone https://github.com/hossamfadeel/iti-advFPGA-capstone
cd iti-advFPGA-capstone

python sw/golden/gen_vectors.py   # 1. regenerate golden vectors (seed 260)
./ci/regress_uvm.sh               # 2. UVM: 4 TBs -> each prints PASS
./ci/regress_hls.sh               # 3. HLS: 4 csims -> each prints PASS
# equivalently: make vectors && make regress
```

PASS criteria (enforced by the scripts): exit 0, a `PASS:` line from every
testbench, zero UVM_ERROR/UVM_FATAL. Full step-by-step, including csynth for
synthesis reports and the hardware bring-up path, is in `docs/REPRODUCE.md`.

---

## 6. Conclusions

1. The complete designed system -- framing, verification, DFX isolation,
   detection, control plane, and spectrum datapath -- is specified,
   implemented, and **verified with zero-tolerance golden checks at every
   level**, with no FPGA hardware required to reach sign-off quality.
2. Verification earned its keep: it found two real protocol bugs that unit
   tests structurally could not catch, plus four datapath/model defects --
   all documented with root causes (Section 3).
3. Every requirement R1-R10 in ARCHITECTURE.md maps to a passing gate today.
4. The remaining work is hardware-stage only (Aurora GT wrapper, DFX
   bitstreams on device, DMA software, host dashboard) and is scoped in the
   capstone plan (docs/Capstone_Project_Spectrum_Sentry.md).

**Prepared as the capstone deliverable for the ITI Advanced FPGA workshop.**
