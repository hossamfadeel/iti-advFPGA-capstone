# SPECTRUM SENTRY -- Architecture Specification (Top-Down)

**ITI Advanced FPGA Capstone -- iti-advFPGA-capstone**
This document is the top of the design hierarchy. Everything downstream
(RTL, UVM, HLS, vectors, build scripts) is derived from it and must trace
back to a line in this document. Change control: edits here after ICD freeze
require a written change request (see docs/ICD.md).

Hierarchy of specification (read in order):

```
L0  Mission & requirements ............ this file, section 1
L1  System architecture & ICD ......... this file, sections 2-5  + docs/ICD.md
L2  Block specifications .............. this file, section 6 (one per block)
L3  Unit specifications ............... rtl/*.sv header comments (per module)
V   Verification architecture ......... this file, section 7 + docs/VERIFICATION_PLAN.md
F   Integration & flow ................ docs/DESIGN_FLOW.md (the V-model walk)
```

---

## 1. L0 -- Mission and Requirements

### 1.1 Mission statement

A two-node real-time RF spectrum intelligence system: a sensor-head FPGA
streams wideband digital I/Q over a fiber link at line rate to an edge-node
FPGA that runs a runtime-swappable detection engine (DFX), classifies
emitters with an on-chip DNN, and publishes detections to a host -- every
block engineered, verified, and integrated with reproducible, CI-gated flows.

### 1.2 Requirements (each maps to a course section and a verification gate)

| ID | Requirement | Course | Verified by |
|----|-------------|--------|-------------|
| R1 | Frame I/Q samples into 256-byte CRC-protected frames at >= 0.9 GB/s sustained | S3 | tb_frame_check, tb_sentry_e2e |
| R2 | Verify frame CRC, count good/corrupt/dropped frames in SW-visible registers | S3 | tb_frame_check (golden summary triple-check) |
| R3 | Swap the detection engine at runtime with zero data loss outside the quiesce window | S1 | tb_decouple (3 live swaps, no loss) |
| R4 | Detect frame energy above a PS-programmable threshold with exact integer math | S2 | tb_sentry_e2e (golden detections, zero tolerance) |
| R5 | Cross clock domains (link 156.25 MHz -> DSP 250 MHz) with no metastability | course CDC | cdc_async_fifo unit sim + e2e |
| R6 | All control/status through an AXI4-Lite register file per the ICD | S3 | spec_ctrl RAL test |
| R7 | Spectral processing (1024-pt FFT -> log-PSD) matches the golden integer model | S2 | fft_psd csim vs golden vectors |
| R8 | Tile spectrograms and channelize with exact integer arithmetic | S2 | tile_pack / fir_chan csim |
| R9 | Whole system builds and regression-tests from a clean clone with one command | S8 | ci/regress.sh + CI gates |
| R10 | UVM environment replaces the ZCU102 bench (virtual hardware) | V | all TBs print PASS |

### 1.3 Non-goals

Real RF front-end hardware, GT-level Aurora PHY simulation (the 64B/66B line
coding lives above our framing layer in hardware; here the "link" is the
framing contract), DPU (Vitis AI integration is a lab, not simulated here),
Versal AIE (knowledge-only per course decision).

---

## 2. L1 -- System Architecture

### 2.1 Node B edge node -- verified architecture (the integration target)

```
                        +-------------------------------------------------+
                        |  NODE B "edge node" (verification view)         |
                        |                                                 |
  raw samples           |  +----------+   +-----------+   +------------+  |
  (replay/IQ)  ==========>| frame_gen|==>| cdc_async |==>| frame_check|  |
  AXI4-S @ wr_clk       |  | (TX     |   | _fifo     |   | (CRC, seq,  |  |
                        |  |  framer)|   | gray xing |   |  counters)  |  |
                        |  +----------+   +-----------+   +------------+  |
                        |      seq/timestamp                 | good IQ    |
                        |                                    | payload    |
                        |                       +------------+            |
                        |                       v                        |
                        |               +-------------+                  |
                        |               |  decouple   |<== decouple_en   |
                        |               | (DFX gate)  |    rm_rstn       |
                        |               +-------------+                  |
                        |                       |                        |
                        |                       v                        |
                        |            +========================+          |
                        |            ||  DFX SLOT: RM1/RM3   ||<== THR   |
                        |            ||  (rm1_energy model)  ||    det_arm
                        |            +========================+          |
                        |                       |                        |
                        |                       v detections            |
                        |               +-------------+                  |
                        |               | spec_ctrl   |<================|=== AXI4-Lite
                        |               | (registers, |================>=== (RAL from
                        |               |  counters,  |  o_ctrl/o_thr      UVM "PS")
                        |               |  IRQ W1C)   |                    |
                        |               +-------------+                  |
                        +-------------------------------------------------+
```

In the deployed system, frame_gen lives on Node A (sensor head) and the
cdc_async_fifo represents the Aurora 64B/66B user-domain crossing. In
verification, both nodes collapse into one testbench (Section 7).

### 2.2 Data flow contract (the one paragraph every student must know)

Samples enter as complex INT16 pairs, 2 samples per 64-bit beat. frame_gen
wraps every 60 samples into a 256-byte frame: header (magic, sequence,
type, timestamp), payload, CRC32. The link crossing preserves beats and
tlast. frame_check verifies CRC, maintains good/corrupt/drop counters in
spec_ctrl, and forwards payload beats of good IQ frames. The DFX slot
consumes frames and emits detection records. Everything above the slot is
STATIC (never changes after freeze); everything inside the slot is one of N
reconfigurable modules sharing a frozen interface.

---

## 3. L1 -- Interface Control Document summary (details in docs/ICD.md)

### 3.1 Frame format (frozen)

256 bytes = 32 beats x 64-bit, little-endian:

| Bytes   | Field        | Notes                                   |
|---------|--------------|-----------------------------------------|
| 0       | magic        | 0xA5                                    |
| 1..2    | seq[15:0]    | wraps; gaps counted as drops            |
| 3       | type         | 0x01 IQ, 0x02 heartbeat, 0x10 RM_ACK    |
| 4..7    | timestamp    | TX free-running counter                 |
| 8..247  | 60 samples   | i16 then q16, little-endian             |
| 248..251| CRC32        | binascii-compatible, over B0..B247      |
| 252..255| pad          | zero                                    |

### 3.2 Detection record (RM1 -> DMA), 2 beats

beat0 = {40'h0, det_seq[15:0], 0xD7}; beat1 = energy[31:0] where
energy = (sum of i^2+q^2 over the frame) >> 16 (exact integer).

### 3.3 Register map (spec_ctrl @ GP0, ICD v1.0)

| Off  | Name       | Acc  | Reset     | Key semantics                     |
|------|------------|------|-----------|-----------------------------------|
| 0x00 | ID         | RO   | "SPEC"    | 0x53504543                        |
| 0x04 | VERSION    | RO   | 1.4.0     | 0x00010400                        |
| 0x08 | CTRL       | RW   | 0         | [0] det_arm [1] irq_en [3:2] build [7:4] rate |
| 0x0C | STATUS     | RO   | -         | [0] lock [1] lane [2] rm_active [8] swapping |
| 0x10 | FRAME_CNT  | RO   | 0         | good frames                       |
| 0x14 | CRC_ERR    | RO   | 0         | corrupt frames                    |
| 0x18 | DROP_CNT   | RO   | 0         | sequence gaps                     |
| 0x1C | DET_COUNT  | RO   | 0         | detections                        |
| 0x20 | THR        | RW   | 0         | detection threshold               |
| 0x24 | TILE_RATE  | RW   | 8         | tiles per 1000 PSD rows           |
| 0x28 | RM_SIG     | RO   | -         | RM self-ID magic                  |
| 0x2C | IRQ_FLAGS  | W1C  | 0         | [0] frame [1] crc [2] det [3] swap |
| 0x30 | SCRATCH    | RW   | 0         | XDMA sanity poke                  |

### 3.4 DFX slot boundary interface (frozen; all RMs must obey)

- AXI4-Stream in: 64-bit, 2 samples/beat, tlast ends a 30-beat frame
- AXI4-Stream out: detection/tile records, tlast on record end
- Clock pl_clk_dsp 250 MHz; reset from decouple.rm_rstn (async assert OK)
- Each RM must present a unique RM_SIG within N cycles of reset release

## 4. L1 -- Clocking and reset architecture

| Domain      | Freq     | Blocks                          | Crossing out          |
|-------------|----------|---------------------------------|-----------------------|
| wr_clk      | 156.25   | frame_gen, fifo write side      | gray-pointer FIFO     |
| clk (DSP)   | 250      | frame_check, decouple, RM, spec_ctrl | none (all DSP)   |
| ctrl        | 100 (HW) | AXI-Lite interconnect           | synchronized in spec_ctrl |

Resets: rst_n per domain; decouple generates RM-local rm_rstn; all
synchronizer first stages get false-path constraints (constr/*.xdc).

## 5. L1 -- HLS datapath (off-chip from the RTL chain, feeds DPU)

fft_psd (1024-pt INT FFT -> log2-PSD bytes -> threshold), tile_pack
(PSD rows -> 16:1 max-hold decimation -> 64x64 INT8 tiles), replay_gov
(rate governor on Node A), fir_chan (stretch: channelizer). All exact
integer arithmetic; Python golden models replicate operation-for-operation.

---

## 6. L2 -- Block specifications

One row per block: purpose, interface summary, verification gate, owner.

| Block (rtl/)      | Purpose                        | Gate                                      |
|-------------------|--------------------------------|-------------------------------------------|
| sentry_defs.sv    | single source of truth: constants, CRC32 | every TB imports it               |
| skid_buffer.sv    | AXI-S register slice, II=1      | used inside chain; protocol checked by monitors |
| cdc_async_fifo.sv | gray-pointer dual-clock FIFO w/ tlast sideband | unit sim: no loss/reorder across 156.25->250 |
| frame_gen.sv      | TX framer w/ incremental CRC    | e2e: frames parse + CRC verify at frame_check |
| frame_check.sv    | RX verify, seq tracking, forward-good | tb_frame_check: golden beats + 3-way counters |
| decouple.sv       | DFX isolation + rm_rstn         | tb_decouple: 3 swaps, zero loss/dup        |
| rm1_energy.sv     | behavioral RM1 detector         | e2e: golden detection records exact        |
| spec_ctrl.sv      | AXI-Lite reg file, counters, W1C IRQ | spec_ctrl_test: RAL RW/RO/W1C + events |

UVM blocks (uvm/): sentry_ifs.sv (axi_lite_if, axis_if, ctrl_if),
sentry_uvm_pkg.sv (agents, RAL + adapter + predictor, golden beat
scoreboard, protocol model scoreboard, coverage, env, 4 tests).

HLS blocks (hls/): see section 5; each kernel owns src/tb/run_hls.tcl and
compares against vectors/ golden files with ZERO tolerance (exact integer).

---

## 7. Verification architecture (UVM as the virtual ZCU102)

```
              +---------------- UVM test (one per TB top) ------------+
              |  beat_seq (golden .mem)      RAL regmodel             |
              |       |                        |  (adapter/predictor) |
              +-------|------------------------|----------------------+ 
                      v                        v
             axis_master_agent          axi_lite_agent          ctrl_if
             (stimulus + monitor)       (RAL driver + monitor)  (events,
                      |                        |                  swaps)
     +----------------v------------------------v----------------------+
     |                     DUT (one block / full chain)                |
     +----------------|------------------------|----------------------+
                      v                        v
             axis_slave_agent            beat_file_sb + frame_model_sb
             (random-ready sink          (golden .mem compare;  (independent
              + monitor)                  counter prediction)    model)
```

Principles:
1. Stimulus from deterministic golden vectors (Python-generated, seed 260)
   so RTL, UVM, HLS, and Python all agree on the same data.
2. Two independent checkers per datapath: golden-file comparison AND a
   protocol model built from the ICD (never the DUT's own code).
3. RAL drives/observes the register plane exactly like the A53 "PS" would.
4. Every TB prints a final "PASS:"/"FAIL:" line -- the CI gate greps it.
5. Coverage: frame lengths, backpressure profiles, reg access patterns,
   swap-under-traffic; sign-off needs 100% of defined bins.

Sign-off equivalences (what UVM proves instead of the bench):

| Bench milestone (spec)        | Simulation equivalent                    |
|-------------------------------|------------------------------------------|
| Day 2: Aurora loopback clean  | tb_frame_check: 16 frames, CRC/drop gold |
| Day 3: DDR->link->DDR >=0.9GB/s | tb_sentry_e2e: full-chain, counters OK  |
| Day 5-6: DFX swap under traffic | tb_decouple: 3 swaps, zero loss          |
| Day 7: DPU classifying         | fft_psd/tile_pack csim + golden vectors  |
| Day 4/8: spec_ctrl from Linux  | spec_ctrl_test RAL RW/RO/W1C             |
