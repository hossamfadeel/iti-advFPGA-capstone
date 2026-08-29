# Capstone Project: SPECTRUM SENTRY

## A Two-Node Real-Time RF Spectrum Intelligence System on Zynq UltraScale+ MPSoC

**Companion capstone for:** "Beyond the Basics -- Advanced FPGA & Adaptive SoC
Engineering" (presentations/Advanced_FPGA_Presentation/)

**Format:** 20 students, 5 teams of 4, **2-week intensive sprint** (~6-8
focused hours/day per student, 6-day weeks), 2 FPGA boards + 1 host PC
**Platform:** 2x AMD ZCU102 (XCZU9EG) + SFP+ DAC cable + host PC

**Presented by: Hossam Hassan, PhD**

---

## 1. Elevator Pitch

> A fiber-coupled "sensor head" FPGA streams wideband digital I/Q at line rate
> over an Aurora 64B/66B link to an "edge node" FPGA. The edge node runs a
> **runtime-swappable detection engine** (partial reconfiguration) built in
> **Vitis HLS**, computes FFT-based spectrograms, classifies emitters with an
> **on-chip DNN (Vitis AI DPU)**, moves results to PS DDR through a **coherent
> HPC port**, and publishes live detections to a host dashboard over
> **PCIe/XDMA** -- all built and regression-tested by a **scripted TCL +
> CI/CD flow** that gates every commit on timing, simulation, and utilization.

This is not a lab exercise. It is a miniature of how modern edge systems are
actually built: a frozen platform, a schedule of reconfigurable payloads, a
measured data path, a host pipeline, and a reproducible build system. Every one
of the eight course sections is exercised in a deliverable a student can defend
in an interview.

### The system in one picture

```
   NODE A "Sensor Head"                  NODE B "Edge Node"
  +------------------+                +----------------------------------+
  | Zynq US+ MPSoC   |                | Zynq US+ MPSoC                   |
  |                  |  Aurora 64B/66B|                                  |
  | DDR4: IQ store   |  10.3125 Gb/s  |  +----------------------------+  |
  |  |               |  SFP+ DAC      |  | RX framer  (CRC, reorder)  |  |
  |  v               | =============> |  |      | AXI4-Stream         |  |
  | AXI DMA (MM2S)   |                |  |      v                      |  |
  |  |               |                |  |  [ DFX SLOT: RP "det" ]    |  |
  |  v               |                |  |   RM1: FFT-PSD scanner     |  |
  | Replay engine    |                |  |   RM2: FIR chan + energy   |  |
  | (rate ctrl)      |                |  |   RM3: spectrogram tiler   |  |
  |                  |                |  |      | AXI4-Stream         |  |
  | A53 Linux:       |                |  +----------------------------+  |
  |  file->DMA       |                |  |      v                      |  |
  |  playback cfg    |                |  | AXI DMA S2MM --> HPC (CCI)  |  |
  +------------------+                |  |      | coherent DDR4        |  |
                                      |  |      v                      |  |
                                      |  | A53 Linux app               |  |
                                      |  |  - detections, stats        |  |
                                      |  |  - DPU classify (Vitis AI)  |  |
                                      |  |  - RM swap via dfx-mgr      |  |
                                      |  |      |                      |  |
                                      |  |      v                      |  |
                                      |  | PCIe Gen3 x4 (XDMA) ------+ |  |
                                      +----------------------------------+  |
                                                                              |
                                            HOST PC: dashboard <============+
                                            (live spectrogram, detections,
                                             RM profile control, logs)
```

### Resume bullets this project earns (per-team variants in Section 11)

- Built a two-node real-time RF spectrum-monitoring system on AMD Zynq
  UltraScale+ MPSoC: 10 Gb/s Aurora 64B/66B fiber link, runtime-swappable
  Vitis HLS detection engines via partial reconfiguration, coherent DMA
  (HPC/CCI), and INT8 DNN emitter classification on the DPU.
- Owned the DFX subsystem of a 5-team, 20-engineer capstone: floorplanned
  reconfigurable partition, three reconfigurable modules, live module swap
  under line-rate traffic with zero link downtime.
- Replaced hand-tuned RTL exploration with Vitis HLS design-space exploration:
  drove a 1024-pt streaming FFT from II=7 to II=1, meeting 250 MS/s with
  documented DSP/BRAM tradeoffs from csynth reports.
- Stood up an FPGA CI pipeline (non-project TCL, GitHub Actions, self-hosted
  Vivado runner) gating every merge on WNS >= 0, xsim regression PASS, and
  utilization < 80%.

---

## 2. Course Coverage Matrix (the contract with the syllabus)

| # | Course Section | Where it is exercised | Deliverable |
|---|----------------|-----------------------|-------------|
| 1 | Partial Reconfiguration / DFX | Node B "det" slot: one RP, three RMs, decouplers, live swap under traffic via Linux fpga-mgr/dfx-mgr | 3 partial bitstreams + swap demo + reconfiguration latency measurement |
| 2 | Vitis HLS deep dive | FFT-PSD, FIR channelizer, energy detector, spectrogram tiler: csim/cosim, pragma DSE, IP packaging | 4 HLS IP cores + DSE report (II, latency, DSP/BRAM/LUT vs pragmas) |
| 3 | Advanced AXI: custom IP, DMA, streams | Custom AXI4-Lite status/control IP (16-register map), AXI DMA both directions, AXI4-Stream everywhere, skid buffers, backpressure, burst tuning | spec_ctrl IP + measured MM2S/S2MM throughput vs theory |
| 4 | Cache coherency + MPSoC | Same S2MM datapath run on HP (non-coherent, cache maintenance) and HPC (CCI, coherent): correctness and cost measured | HP vs HPC lab-style report with cycle counts and bug writeups |
| 5 | Host attach: GT transceivers + PCIe | Aurora 64B/66B FPGA-to-FPGA over SFP+ at 10.3125 Gb/s (GT/GTH, lane bring-up, user-clock domains, CDC into DSP clock); PCIe Gen3 x4 XDMA to host on ZCU102 | Link BER/throughput report + host streaming demo over XDMA |
| 6 | AI acceleration on FPGA | INT8 CNN emitter/modulation classifier trained on RadioML, quantized with vai_q, executed on DPU (Vitis AI), fed by PL-generated spectrogram tiles | Model + accuracy report + end-to-end tiles/s and latency |
| 7 | Versal ACAP: NoC + AI Engines | **Knowledge only** (deliberate scope decision): covered in lectures (Section 7) and interview prep; no build deliverable depends on it | None -- students can explain NoC vs soft interconnect and AIE vs PL-DSP in demo-day Q&A |
| 8 | Scripted flows: TCL + CI/CD | Whole project built non-project mode from a Makefile + build.tcl; GitHub Actions self-hosted runner; WNS/TNS gate, utilization gate, xsim regression on every PR | Repo + green CI badge + release artifacts (bitstreams + reports) |

Labs 1-6 and Lab 8 are the direct feeding ground: Lab01 (DFX flow), Lab02
(FIR HLS DSE), Lab03 (AXI DMA streaming), Lab04 (HP vs HPC), Lab05 (Aurora
64B/66B SFP+), Lab06 (DPU deployment), Lab08 (TCL/CI) each become the "first
working draft" of the corresponding capstone subsystem. Students who completed
the labs can reuse their own code. Lab07 (AIE toolflow) remains standalone
practice: Section 7 is knowledge-only in the capstone, so Lab07 feeds
interview readiness rather than a project deliverable.

---

## 3. Hardware Plan and Rationale

### 3.1 The platform: 2x ZCU102 (decided)

| Resource | What it gives the project |
|----------|---------------------------|
| XCZU9EG-2FFVB1156E (600K LC, 2520 DSP, per UG1182) | Room for DPU B4096 + DFX slot + Aurora without utilization panic |
| 4x SFP+ cages on GTH | Aurora 64B/66B node-to-node over passive DAC |
| PCIe Gen3 x4 edge fingers | Plug Node B into the host PC; XDMA exactly as Section 5 teaches (lspci 10ee, lspci -vv, /dev/dma_proxy) |
| PS DDR4 4GB (LPDDR4 PL side also present) | IQ replay store (Node A), spectrogram + detections (Node B) |
| PS UART/JTAG (micro-USB J83/J2) | Console, debug |
| Existing lab infrastructure | Same 2023.2 tool baseline, same PetaLinux bones as Labs 1-8 |

Scope note: Versal NoC/AI Engines (course Section 7) are **knowledge-only**
in this capstone -- lectures and interview prep, no hardware, no deliverable.
This is announced on day one so no team plans around it.

### 3.2 Board scheduling for 20 students

CI-first design principle: **all design work is board-independent** (csim,
cosim, xsim, synth, impl run on the CI runner). Boards are only needed for
integration and demo. Two rigs are enough:

- Rig 1: Node A + Node B + DAC cable (the "link rig")
- Rig 2: Node B plugged into host PC (the "host rig"); Node A role temporarily
  replayed by a pre-stored DDR file on the same board during bring-up

A simple booking sheet (or the repo's Wiki) schedules 2-hour bench slots.
Every milestone gate has a simulation-only path so no team is ever blocked on
hardware access.

---

## 4. System Specification

### 4.1 Scenario and data flow

1. Node A replays a recorded wideband I/Q capture (or a synthetic generator:
   sweep + QPSK + FM burst + noise) from DDR4 through AXI DMA at a controlled
   rate up to 250 MS/s (complex INT16 x2 = 4 B/sample = 1.0 GB/s payload).
2. The replay engine packs samples into framed Aurora payloads; Aurora 64B/66B
   carries them across the SFP+ DAC at 10.3125 Gb/s line rate.
3. Node B's RX framer checks CRC, strips headers, regenerates an AXI4-Stream
   of I/Q in the 250 MHz DSP domain (async FIFO handles the 156.25 MHz
   Aurora user-clock to 250 MHz DSP-clock crossing -- course CDC knowledge
   reused silently, as promised).
4. The stream feeds the DFX slot. The currently loaded RM does one of:
   - RM1 "Wideband scanner": 1024-pt FFT -> log-PSD -> peak/occupied-band
     detection over programmable thresholds.
   - RM2 "Channelized monitor": polyphase FIR channelizer + per-channel
     energy detector with programmable channel mask.
   - RM3 "AI feeder": 1024-pt FFT -> log-PSD -> bin decimation -> 64x64
     INT8 spectrogram tiles -> packets tiles to DDR for the DPU.
5. Detector outputs (detections, PSD snapshots, tiles) go S2MM into PS DDR.
   The default build uses the **HPC/CCI coherent path**; a build-time and
   runtime-switchable **HP + cache-maintenance** variant exists for the
   coherency study (Section 4.6).
6. A53 Linux application: consumes detections, invokes the DPU on tiles,
   maintains statistics, serves the host dashboard, and executes RM swaps
   through the DFX manager on operator command.
7. Host PC dashboard (Python over XDMA/PCIe):
   live waterfall, detection markers, classification labels, RM profile
   selector, link health (lane_up, CRC error counters).

### 4.2 Bandwidth budget (worked, the Section 3 way)

| Segment | Rate | Math |
|---------|------|------|
| Aurora line | 10.3125 Gb/s | GTH, 64B/66B |
| Aurora payload | ~10.0 Gb/s | 10.3125 x 64/66 |
| Framing overhead | ~2% | 8 B header + 4 B CRC on 256 B frames |
| I/Q stream | ~0.98 GB/s -> 245 MS/s | 4 B per complex sample |
| FFT input (RM1/RM3) | 245 MS/s | hop 1024, no overlap (2-engine overlap = DSE exercise) |
| PSD row rate | ~239k rows/s | 245M/1024; 1024 B/row after log-8b |
| PSD write to DDR | ~239 MB/s | sustained S2MM, trivial for HPC |
| Spectrogram tiles | 3.7k tiles/s peak | 64 rows/tile, 4 KB INT8/tile |
| DPU classification | duty-cycled 100-1000 inf/s | scheduler picks tiles; tiny CNN ~0.2 MB params |
| Host detections | < 1 MB/s | XDMA C2H streaming channel |

Peak DDR pressure on Node B: ~1.0 GB/s in (if IQ is also recorded) + 0.24
GB/s PSD + DPU traffic -- comfortably inside the ~4 GB/s HPx4/HPC envelope;
students must still show the worked numbers in the report (deliverable).

### 4.3 Clocking and reset plan

| Clock | Freq | Domain / notes |
|-------|------|----------------|
| pl_clk_dsp | 250 MHz | DSP datapath, DFX slot, spec_ctrl, DMA stream side |
| aur_user_clk | 156.25 MHz | Aurora 64B/66B user side (64-bit @ 156.25 = 10.0 Gb/s) |
| pl_clk_ctrl | 100 MHz | AXI-Lite control, interconnect |
| DPU clk | 300 MHz (per TRD) | DPU static region |

- Async FIFOs at every clock boundary; false-path constraints on all
  synchronizer first stages (the SDC/XDC hygiene from the course applies).
- Resets: per-domain reset synchronizers; DFX decouple/soft-reset sequence
  around every RM swap.

### 4.4 Address map (Node B, GP0 control plane)

| Address | Peripheral | Notes |
|---------|-----------|-------|
| 0x8000_0000 | spec_ctrl (custom AXI4-Lite IP) | 16 registers, Section 5.5 |
| 0x8001_0000 | AXI DMA (stream datapath) | driver-owned under Linux |
| 0x8002_0000 | AXI DMA (IQ record, optional) | HP build variant |
| 0x8003_0000 | Aurora control/status | lane status, error counters |
| DPU TRD map | DPU + its HP ports | inherited from starter platform |

### 4.5 Aurora framing (the ICD, v1.0 -- frozen Day 2, 17:00)

```
Frame (AXI4-Stream payload between framing layers):

  0        8        16                  32                    N
  +--------+--------+-------------------+---------------------+--------+
  | magic  | seq[15:0] type[15:8]      | timestamp[31:0]     |  ...   |
  +--------+--------+-------------------+---------------------+--------+
  | payload (IQ samples, detections query, RM ack, heartbeat ...)       |
  +----------------------------------------------------------------------+
  | CRC32 (over header+payload)                                          |
  +----------------------------------------------------------------------+

  IQ frame: payload = 60 x complex INT16 = 240 B -> frame = 256 B total.
  tkeep must be full frames; tlast terminates each frame; no partial words.
```

- seq numbers detect drops; CRC32 detects corruption; a heartbeat frame every
  1 ms keeps the link state machine honest during RM swaps.
- Same frame checker is instantiated in the xsim regression testbench (CI
  gate), so framing bugs never reach the bench.

### 4.6 The coherency experiment (Section 4 of the course, as a deliverable)

Runs on the **identical** detector datapath, two builds:

| Build | Port | Software contract | Measured quantities |
|-------|------|-------------------|---------------------|
| A | HPC0 (through CCI) | plain CMA buffer, no cache maintenance | correctness, S2MM throughput, CPU read latency after DMA done |
| B | HP0 | same CMA buffer, explicit dma_sync_single_for_cpu / Xil_DCacheInvalidateRange discipline | same + maintenance cost in cycles + the two classic bugs reproduced once each (stale device read, stale CPU read) then fixed |

Expected outcome (matches Lab04 theory): coherent path costs some DMA-side
latency/CCI arbitration but removes software maintenance and eliminates both
stale-data failure modes; report must show numbers, not assertions.

---

## 5. Subsystem Specifications (team ownership marked)

### 5.1 Node A sensor head [TEAM LINKS]

- DDR->MM2S replay with rate governor (programmable back-pressure by dropping
  to N/256 of full rate; heartbeat always sent).
- TX framing per ICD; loopback self-test mode (internal, no cable) for bench
  debug; PRBS mode for BER-style soak testing of the link.
- A53 Linux app or bare-metal (team choice, must justify in report): loads IQ
  file, programs DMA, monitors TX counters.

### 5.2 Aurora 64B/66B link [TEAM LINKS]

- GTH x1, 10.3125 Gb/s, SFP+ DAC between boards (Lab05 flow is the draft).
- Bring-up checklist documented as the Section 5 "ritual": lane_up, channel
  bonding N/A (x1), user clock lock, error counters zero over 10-minute soak.
- Deliverables: measured max clean payload rate, soak error count, and the
  user-clock -> DSP-clock CDC writeup with a scope-clean CDC review.

### 5.3 DFX slot: RP "det" and three RMs [TEAM DFX]

- One Reconfigurable Partition in the PL, pblock sized ~12-18% of fabric,
  chosen to include enough BRAM/DSP columns for the biggest RM (RM3).
- Fixed AXI4-Stream slave/master + AXI4-Lite status ports on the RP boundary;
  decoupler (AXI-Stream shutdown) + soft reset around the slot.
- RMs (minimum two for a valid DFX story; the third is stretch):
  - RM1 FFT-PSD scanner (from HLS core 5.4.1) -- mandatory
  - RM3 spectrogram tiler (from HLS core 5.4.3) -- mandatory
  - RM2 FIR channelizer + energy detector (from HLS core 5.4.2) -- stretch
- All three RMs share the exact same interface contract (frozen in the ICD) --
  this is the point of DFX: the static region never changes.
- Runtime load path: Linux fpga-manager (partial bitstream, PCAP) with a small
  safe-swap state machine in the A53 app: quiesce stream -> decouple -> reset
  -> load partial -> release -> verify signature register -> resume.
- Deliverables: 2 partials (RM1, RM3) + full golden config (RM2 as a third
  partial is stretch); measured swap latency (target < 200 ms end-to-end) and
  a swap-under-traffic demo with zero loss beyond the intentional quiesce
  window; pblock/QoR report.

### 5.4 HLS DSP kernels [TEAM DSP]

Four kernels, all Vitis HLS 2023.2, all with: C golden model + self-checking
testbench, csim/cosim clean, packaged IP-XACT, and a **DSE report** comparing
at least two pragma configurations each (three for stretch kernels).

| Kernel | Function | Baseline target | DSE axes |
|--------|----------|-----------------|----------|
| 5.4.1 fft_psd | streaming 1024-pt complex FFT -> mag^2 -> log2 (LUT) -> threshold detect | 245 MS/s in, II=1 frame pipeline @ 250 MHz | PIPELINE/UNROLL on stages, DATAFLOW split FFT/PSD, ARRAY_PARTITION on twiddle ROM, 1 vs 2 engines for 50% overlap |
| 5.4.2 fir_chan (stretch, feeds RM2) | 64-channel polyphase channelizer + per-channel energy + mask compare | 245 MS/s, resource-fit into RM2 | URFactor, channel-parallel UNROLL vs sequential, DSP binding report |
| 5.4.3 tile_pack | PSD rows -> 16:1 bin decimation -> 64x64 INT8 tile assembly -> TLAST-framed packet stream | 1 tile per 262 us worst case | stream depth, DATAFLOW, ping-pong buffers |
| 5.4.4 replay_gov (Node A) | rate governor + frame packer | II=1, 64-bit stream | minor; exists to teach interface pragmas (AXIS side-channels) |

Rules of the game (from Section 2 of the course): the C testbench is the
golden model; nobody debugs generated RTL; every claim of speed cites the
csynth Latency/Interval and resource columns; cosim must pass for the exact
configuration that gets frozen.

### 5.5 spec_ctrl: custom AXI4-Lite IP [TEAM PLATFORM]

Register map (the ICD table that makes 20 people interoperable):

| Offset | Name | Dir | Reset | Description |
|--------|------|-----|-------|-------------|
| 0x00 | ID | R | 0x53504543 | "SPEC" |
| 0x04 | VERSION | R | 0x0001_0400 | maj.min=1.4, patch 00 |
| 0x08 | CTRL | RW | 0x0 | [0] det_arm, [1] irq_en, [3:2] build (0=HP,1=HPC), [7:4] rate_pow2 |
| 0x0C | STATUS | R | - | [0] stream_lock, [1] aur_lane_up, [2] rm_active (ro from slot), [8] swapping |
| 0x10 | FRAME_CNT | R | 0 | good RX frames, 32-bit wrap |
| 0x14 | CRC_ERR | R | 0 | CRC failures (latched with sticky bit) |
| 0x18 | DROP_CNT | R | 0 | sequence-gap drops |
| 0x1C | DET_COUNT | R | 0 | detections this epoch |
| 0x20 | THR_HI/LO | RW | - | detection thresholds |
| 0x24 | TILE_RATE | RW | 8 | tiles per 1000 PSD rows forwarded to DDR |
| 0x28 | RM_SIG | R | - | RM self-identifying magic written by each RM |
| 0x2C | IRQ_FLAGS | RCW1 | 0 | frame, crc, detection, swap-done |
| 0x30 | SCRATCH | RW | 0 | PCIe/XDMA sanity poke register |
| 0x34..0x3C | rsvd | - | - | future |

- AXI4-Lite slave written in the course's verbatim-register style (Section 3
  slide "The register write block"), wrapped with a skid-buffered AXI-Lite
  fabric adapter; all reads latency-1, no wait states beyond reset.
- Unit-tested in xsim with an AXI-Lite BFM task suite; the same suite runs in
  CI (regression gate).

### 5.6 Host attach and dashboard [TEAM LINKS + TEAM AI/SW]

ZCU102 build: Node B edge connector into the host PC; XDMA (or dma_proxy)
driver; two channels: C2H detections/spectrogram stream, H2D control. Host
bring-up ritual exactly per Section 5: lspci -> 10ee, lspci -vv speed/width
(Speed 8GT/s, Width x4 expected), BAR map, driver load, channel check.
Dashboard: Python (PyQt or web) waterfall + detections + RM selector button.

### 5.7 DPU integration [TEAM AI/SW]

- Starter platform ships with DPU (B4096 on ZCU102) already
  in the static region -- integrating a DPU TRD from scratch in a two-week
  sprint is impossible; students integrate around it, and the model side is
  fully theirs.
- Model: small CNN (3-6 conv + 2 dense, < 1M params) trained in PyTorch on
  RadioML 2016.10A-derived spectrogram tiles (11-class digital/analog
  modulation + a "noise/unknown" class). Target: >= 80% accuracy at SNR >=
  +10 dB, INT8 with vai_q calibration (1000-tile calibration set).
- Flow: train (float) -> ONNX -> vai_q -> vai_c for the board's DPU arch ->
  VART C++ or Python app on A53; tiles consumed from coherent DDR ring.
- Deliverables: accuracy table (float vs INT8), throughput (tiles/s end to
  end), latency breakdown (PL tile gen -> DDR -> DPU in -> softmax -> UDP).

### 5.8 CI/CD infrastructure [TEAM PLATFORM, everyone contributes tests]

Repository shape (Lab08 flow, scaled to 20 contributors):

```
spectrum-sentry/
  hls/           fft_psd/ fir_chan/ tile_pack/ replay_gov/  (each: src,tb,run_hls.tcl)
  rtl/           spec_ctrl/ decouple/ frame_check/ aurora_glue/
  sim/           tb_spec_ctrl.sv tb_frame_check.sv tb_fir_chan.sv ...
  bd/            node_a.tcl node_b.tcl               (non-project, scripted)
  constr/        node_a.xdc node_b.xdc dfx/          (pblocks, false paths)
  sw/            a53_apps/ host_dashboard/ dpurt/    (model + VART app)
  ci/            build.tcl gates/ regress.sh runner-setup/
  Makefile       synth impl partial|a b all  sw  regress  gates
  .github/workflows/fpga.yml
```

Gates on every PR (GitHub Actions, self-hosted runner with Vivado 2023.2):

1. csim all HLS kernels (fast job, minutes)
2. xsim regression: every testbench prints PASS (framing CRC, AXI-Lite BFM,
   FIR golden-vector, decoupler behavior during fake swap)
3. synth checkpoint job (nightly + on PR to main): WNS >= 0 across all
   clocks, utilization < 80% every category, else red
4. Artifact archive per green main merge: reports + bitstreams, tagged

WNS parse gate (from Section 8, verbatim spirit):

```tcl
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
if {$wns < 0} { puts "FAIL: WNS $wns"; exit 1 } else { puts "PASS: WNS $wns" }
```

---

## 6. Organization: 5 Teams x 4, One Frozen ICD

| Team | Name | Owns | Also delivers to CI |
|------|------|------|---------------------|
| T1 | Platform & Integration | BDs (node_a.tcl, node_b.tcl), clocks, address map, build.tcl, runner, board scheduling, final assembly | build scripts, utilization reports, spec_ctrl xsim suite |
| T2 | DSP / HLS | kernels 5.4.1-5.4.4 + DSE reports | csim/cosim jobs + golden vectors |
| T3 | Links | Node A replay, Aurora, framing, XDMA host path, dashboard | framing testbench, soak logs |
| T4 | DFX | pblock, decouplers, RM builds, partial load flow, swap-under-traffic | RM signature checks, swap testbench |
| T5 | AI & SW stack | RadioML model, vai_q/vai_c, VART app, HP vs HPC experiments, dfx-mgr app, Linux image | model accuracy job, coherency test logs |

Governance (sprint cadence):

- **ICD freeze, Day 2, 17:00** (Section 4.5 frame format, 5.5 register map,
  RM interface). After freeze, changes require a written change request
  accepted in the cross-team sync -- exactly like real programs.
- Daily 15-min standup per team (mornings); daily 5-min cross-team sync right
  after (T1 chairs) -- in a sprint, integration problems must surface in
  hours, not weeks.
- Everything through PRs; main is always the demo branch ("clean-clone
  test": a fresh checkout + one make command rebuilds everything). Every
  push to main triggers the full synth job; nightly full builds are the
  heartbeat of the sprint.
- Bus factor 2 on every subsystem: no single student is the only one who can
  build, flash, or demo a piece.
- Individual accountability: commit history + PR reviews + a short personal
  retro section in the final report.

---

## 7. Schedule: 2-Week Sprint, Gate Every 2-3 Days

Three load-bearing assumptions; without any one of them the schedule does
not close:

1. The instructor starter platform (Appendix A) is complete and green before
   Day 1.
2. Pre-sprint homework (Days -5..0) is done BEFORE Day 1: tools installed,
   repo cloned, clean-clone build reproduced, lab solutions re-run, RadioML
   float model training launched (it trains in the background during the
   sprint).
3. Students actually spend ~6-8 focused hours/day, 6 days a week. This is a
   sprint, and the plan spends that budget deliberately.

| Day | Focus | Acceptance gate (demo-able, CI-visible) |
|-----|-------|------------------------------------------|
| 1 | Kickoff + interfaces | Teams chartered; ICD drafted; spec_ctrl register map coded; all HLS kernels compile; CI skeleton green on golden vectors |
| 2 | **ICD FREEZE 17:00 (hard)** | csim PASS fft_psd + tile_pack vs golden vectors; Aurora loopback BER-clean 10 min on bench; platform bitstreams boot both boards; framing + spec_ctrl testbenches in CI |
| 3 | Datapaths | DDR->Aurora->DDR loop sustains >= 0.9 GB/s measured; spec_ctrl R/W from Linux (devmem); DSE configs shortlisted |
| 4 | Static-fabric chain | RM1 (FFT-PSD) running in static fabric end-to-end into DDR; host XDMA link streams detections to dashboard skeleton; DSE report v1 (2 configs/kernel) |
| 5 | DFX cutover | RP pblock placed, decouplers in; first RM1 partial swaps on bench; swap latency measured; RM_SIG verified per swap |
| 6 | DFX under traffic | RM1<->RM3 swap-under-traffic survived (loss only inside the intentional quiesce window); heartbeat link health clean throughout |
| 7 | AI on (light day: report drafting starts) | DPU classifying tiles from DDR at >= 100 tiles/s; INT8 vs float accuracy table; HP vs HPC A/B measured in one scheduled bench session |
| 8 | System tie-in | Full chain live: replay -> Aurora -> RM swap from dashboard -> detections + CNN labels on host; **all mandatory gates now green** |
| 9 | Hardening + buffer | 30-min soak, zero CRC errors; timing clean on CI; report finalized; stretch work only from here (RM2, dashboard polish, 2-engine FFT overlap) |
| 10 | Demo day | 8-minute script (Section 9) executed live; sprint report submitted; tag v1.0 release from CI |

Stretch queue (strictly after Day-8 gates are green): RM2 polyphase
channelizer as a third partial; 50%-overlap FFT via a second engine;
dashboard polish; longer soak.

Fallback ladder (pre-agreed, invoked no later than the day listed): if DFX is
not swapping by Day 7, the Day-8/10 demo runs a soft-switched (mux) slot with
partials shown as a separate bench demo; if DPU integration slips, classification
runs on the A53 with DPU numbers quoted from Lab06; if the model is late, RM3
tiles stream to the host dashboard and the CNN runs host-side for the demo.
The PL datapath, the Aurora link, the coherency A/B, and the CI gates are
non-negotiable -- every fallback above still passes them.

---

## 8. Assessment Rubric (100 pts)

| Area | Pts | Evidence |
|------|-----|----------|
| Milestone gates (4 x 10: Days 2, 5, 8, 10) | 40 | CI logs + bench checklists, gated at the morning sync |
| Final system demo | 20 | Demo-day script (Section 9) executed live |
| Engineering report | 15 | Measurements (bandwidth, WNS, swap latency, INT8 accuracy, HP vs HPC), DSE study, honest failure analysis |
| Repo hygiene & CI | 15 | Clean-clone test, PR discipline, meaningful commits (per student) |
| Peer review | 10 | Cross-team contribution, reviews, ICD citizenship |

Interview defense: every student must be able to whiteboard the full block
diagram and defend any subsystem's key numbers (swap latency, WNS, GB/s,
tiles/s) -- sampled during demo day Q&A.

---

## 9. Demo Day Script (8 minutes)

1. (0:00) Boot both nodes from CI-tagged v1.0 artifacts; show CI pipeline
   green + WNS report on screen.
2. (1:00) Start replay: host dashboard shows live waterfall from RM1
   wideband scanner; point at detection markers and CRC/frame counters
   (zero errors).
3. (2:30) Operator clicks "AI feeder" on the dashboard: the RM3 tiler partial
   loads live; the waterfall switches from raw PSD rows to tile packets; swap
   latency printed by the app (< 200 ms target). Link never drops (heartbeat
   visible throughout).
4. (4:00) DPU classification labels appear over detections as tiles land in
   DDR; quote tiles/s and accuracy. (If the stretch RM2 channelizer is ready,
   it is swapped here as a bonus.)
5. (5:30) Show the coherency toggle: same traffic over HP build with
   explicit cache maintenance vs HPC build; on-screen cycles-per-detection
   comparison.
6. (6:30) Show the repo: one `make all` from clean clone; CI gates list;
   spectrogram of the whole class applauding (optional).
7. (7:00-8:00) Q&A; each team fields questions on its subsystem.

---

## 10. Resume Bullets by Role (students pick their true one)

- **Platform:** "Delivered the scripted non-project Vivado/AMD-Vitis 2023.2
  build (TCL + Makefile + GitHub Actions) for a 5-team FPGA program; every
  merge gated on WNS, utilization, and xsim regression."
- **DSP/HLS:** "Designed a 1024-pt streaming FFT-PSD and 64-channel polyphase
  channelizer in Vitis HLS sustaining 245 MS/s; documented pragma-level design
  space exploration halving DSP usage at equal throughput."
- **Links:** "Brought up Aurora 64B/66B over SFP+ at 10.3125 Gb/s between two
  Zynq UltraScale+ nodes (zero-error 10-minute soak) and a PCIe Gen3 x4
  XDMA host path with a Python streaming dashboard."
- **DFX:** "Implemented dynamic function exchange on a live system: floorplanned
  reconfigurable partition hosting three Vitis HLS engines, swapped at runtime
  over PCAP under line-rate traffic with a measured < 200 ms reconfiguration
  latency."
- **AI/SW:** "Trained, INT8-quantized (vai_q), and deployed a modulation
  classifier on the on-chip DPU via Vitis AI/VART, fed by a coherent
  (HPC/CCI) DMA spectrogram pipeline; benchmarked coherent vs non-coherent
  datapaths under Linux."

---

## 11. Risk Register

| Risk | Likelihood | Mitigation / fallback |
|------|-----------|----------------------|
| DFX toolflow schedule slip (classic) | High | RM interfaces identical to static-fabric versions; mux-based soft switch is the Day-7 fallback; Lab01 flow is the proven path |
| DPU TRD integration drag | Medium | DPU pre-integrated in starter platform; students own model + app only; model training launched pre-sprint |
| Aurora lane issues (DAC hygiene, refclk) | Medium | Loopback self-test mode first, then cable; Lab05 debug tree in solutions/; Day-2 gate isolates link risk early |
| Sprint compression fatigue | Medium | 6-day weeks with a light Day 7; bus factor 2 per subsystem; every gate has a sim-only path so nobody is blocked waiting for bench |
| 20-person merge conflicts | Medium | ICD freeze Day 2 + per-team directories + PR-only main + every-push full synth + nightly builds |
| Bench contention (acute in a sprint) | High | CI-first: nothing goes to the bench without green CI; two rigs + evening booking slots; sim paths for every gate |
| Timing closure at 250 MHz DSP | Medium | II=1 pipelines with dataflow margins; target < 80% util gate; retiming-friendly HLS configs documented |
| RadioML training environment | Low | Training launched as pre-sprint homework; CPU-feasible for a tiny CNN; dataset mirror on course NAS |

---

## 12. Bill of Materials

| Item | Qty | Notes |
|------|-----|-------|
| ZCU102 board | 2 | Node A (sensor head) + Node B (edge node) |
| SFP+ DAC cable (1-3 m, 10G) | 2 | node-to-node; 1 spare recommended |
| Host PC with PCIe x4+ slot | 1 | XDMA host; any tower with a free slot |
| microSD cards | 4 | boot images + spares |
| micro-USB cables (UART/JTAG) | 2 | console + debug |
| USB stick / NAS mirror | 1 | RadioML subset, IQ captures, tools |

---

## Appendix A: Instructor-Provided Starter Platform (the sprint feasibility contract)

In the 2-week format this appendix is load-bearing: it is the difference
between a sprint and a death march. Items 1-5 must be green before Day 1.

1. Base block designs (node_a, node_b) as non-project TCL scripts: PS config
   (DDR, GEM, UART), clocks (250/156.25/100), AXI interconnect skeleton,
   GP0 address map slots, HP0/HPC0 wired, AXI DMA instantiated, DPU (B4096)
   integrated per TRD with documented HP usage. Node A's replay datapath is
   working out of the box (Lab03 design pre-adapted).
2. Aurora 64B/66B example design pre-adapted to the ZCU102 SFP+ pinout
   (Lab05 flow), looping back cleanly before Day 1.
3. PetaLinux/Ubuntu image with: fpga-manager + dfx-mgr, XDMA or dma_proxy
   driver (ZCU102), AXI DMA driver, Vitis AI runtime (VART) + DPU xclbin,
   rootfs + devicetree sources in the repo.
4. Data + golden models: 3 x 60-second wideband IQ captures (synthetic
   generator script included), RadioML 2016.10A subset (~20k windows) with
   calibration split, and reference C golden vectors for every HLS kernel.
5. CI runner image: Ubuntu + Vivado/Vitis 2023.2 (education licenses),
   runner registered and green on the starter commit.
6. Pre-sprint homework pack (issued Days -5..0): tool install guide, repo
   access, clean-clone build exercise, lab solution walkthroughs, and the
   RadioML training notebook students launch before Day 1.

## Appendix B: What is deliberately OUT of scope

- RF front-ends / ADC hardware (the "RF" is digital I/Q files; a real AFE is
  a future extension, quoted in the report's future-work section).
- Multi-board TDOA geolocation (mentioned as future work; frame timestamps
  are in the ICD so it remains possible).
- Versal NoC / AI Engines: lecture knowledge only (course Section 7); no
  hardware, no simulator deliverable in the capstone.

---

**Presented by: Hossam Hassan, PhD**
