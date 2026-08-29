# DESIGN_FLOW.md -- How to Design a Big, Complex FPGA System

## The method this project actually follows (and you should copy)

This document teaches the professional way to build a system too large to
hold in your head: define top-down, build and verify bottom-up, and never
skip a gate. It is the map of everything in this repository.

```
          TOP-DOWN (define)                        GATE
          ================                        =====
Step 1    Mission + requirements (L0)         requirements reviewable,
                                               each one testable
Step 2    System architecture (L1)            block diagram + data-flow
                                               paragraph every engineer
                                               can recite
Step 3    Interface Control Document (ICD)    ICD FREEZE (change control
                                               from here)
Step 4    Block specifications (L2)           every block has ports,
                                               clocking, and a named
                                               verification gate
Step 5    Verification architecture           checker != DUT logic;
                                               golden vectors agreed
                                               across ALL domains
Step 6    Project skeleton + CI-first repo    clean clone builds

          BOTTOM-UP (implement + integrate)       GATE
          =================================       =====
Step 7    Leaf utilities (CRC, skid, CDC FIFO)   unit sims PASS
Step 8    Unit blocks, one at a time             per-block UVM PASS
Step 9    Subsystem integration (link chain)     subsystem TB PASS
Step 10   Full-system integration (e2e + RAL)    e2e TB PASS
Step 11   Software datapath (HLS kernels)        csim == golden, exact
Step 12   Regression + release                   one command, all green
```

Why this order: every integration bug you have ever had was cheaper to
prevent one step earlier. The ICD freeze (Step 3) is where 20 people stop
colliding. The golden vectors (Step 5) are why a UVM scoreboard, a C
testbench, and a Python script can never quietly disagree.

---

## Step 1 -- Mission and requirements (L0)

Write one paragraph saying what the system does, then a table of numbered
requirements (R1..RN). RULE: every requirement must name its verification
gate -- if you cannot say what proves it, it is not a requirement, it is a
wish.

- See: docs/ARCHITECTURE.md section 1 (R1..R10 all map to tests).

## Step 2 -- System architecture (L1)

Draw the block diagram (ASCII is fine and diff-able). Then write the
"data-flow contract": one paragraph describing what a byte experiences
traveling through the system. If the team cannot recite it, the
architecture is not done.

- See: ARCHITECTURE.md section 2 (diagram + the one-paragraph contract).

## Step 3 -- The ICD freeze

Define every crossing surface BEFORE any RTL: frame format, detection
record, register map, DFX slot interface, clock domains. Tag the document,
date it, and enforce change requests after the freeze.

- See: docs/ICD.md (the living copy) + ARCHITECTURE.md section 3 (summary).
- Teaching moment: in this repo, the frame format chose 256 B = 32 beats so
  every boundary is beat-aligned; that one decision removed an entire class
  of corner cases before any code existed.

## Step 4 -- Block specifications (L2)

For each block: purpose, ports, clock/reset, what drives it, what checks
it. Keep it to one table row (ARCHITECTURE.md section 6) + the module
header comment (L3). Big specs rot; small specs at the point of use do not.

## Step 5 -- Verification architecture (the step everyone skips)

Decide BEFORE coding:

1. Where do golden answers come from? Here: ONE Python generator
   (sw/golden/gen_vectors.py, seed 260) emits vectors consumed by RTL sims,
   UVM scoreboards, and HLS C testbenches. Single source of truth.
2. How is the DUT checked? Golden-file comparison AND an independent
   protocol model written from the ICD (never from the DUT source).
3. What is "done"? A test that prints PASS with zero UVM_ERRORs, plus
   coverage bins filled.
4. What replaces the board? The UVM environment is the virtual ZCU102:
   the RAL plays the A53 PS, random-ready sinks play DMA backpressure,
   the golden files play recorded traffic.

- See: ARCHITECTURE.md section 7, docs/VERIFICATION_PLAN.md.

## Step 6 -- CI-first repository skeleton

Create the repo (structure mirrors ownership), the Makefile stubs, the
regression script, and the CI workflow BEFORE there is anything to build.
Then the first commit is already green. In this repo:

```
make vectors   # regenerate golden vectors (python)
make csim-host # HLS kernels verified with a host C++ compiler (no tools)
make regress   # ALL UVM tests; every TB must print PASS (xsim + UVM 1.2)
make synth     # non-project Vivado synthesis + WNS gate (needs Vivado)
```

## Step 7 -- Bottom-up begins: leaf utilities

Build the small things everything else needs, and simulate them first:

- sentry_defs.sv: constants + CRC32 function (shared by DUT and checkers!)
- skid_buffer.sv: the register slice (course slide, now real)
- cdc_async_fifo.sv: gray-pointer FIFO WITH tlast sideband (the tlast is
  exactly what a real Aurora user interface gives you -- forget it in the
  spec and integration dies)

Gate: xvlog clean; protocol checked implicitly in every later test;
CDC FIFO proven in the e2e run (no loss/reorder across 156.25 -> 250 MHz).

## Step 8 -- Unit blocks, one at a time

For each block: write RTL against the ICD, write its UVM test, run it,
fix, repeat. NEVER start the next block until the current one prints PASS.
The order that minimizes rework: spec_ctrl (the control plane), then
frame_gen + frame_check (the link), then decouple, then rm1_energy.

Per-block gates (each is one command in this repo):

| Block        | Command (after `make regress` selection) | What PASS means |
|--------------|-------------------------------------------|-----------------|
| spec_ctrl    | run spec_ctrl_test                        | RAL RO/RW/W1C + event counters + STATUS |
| frame_check  | run frame_check_test                      | golden beats out; DUT==model==golden counters |
| decouple     | run decouple_test                         | 3 live swaps, zero loss/dup |
| rm1_energy   | (covered by e2e)                          | exact golden detections |

## Step 9 -- Subsystem integration (the link chain)

Chain frame_gen -> cdc_async_fifo -> frame_check. This is the first place
two clocks and a framing contract meet. Expect exactly the bugs the course
predicted: tlast swallowed by CDC, CRC computed over the wrong beats,
s_tready handshake stalls. Because Step 8 passed, any new bug IS an
integration bug -- that is the entire point of unit gates.

## Step 10 -- Full-system integration (e2e)

Add decouple + rm1_energy + spec_ctrl and drive everything as the real
system: golden raw samples into frame_gen, RAL writes THR and det_arm
"from the PS", detections compared at the sink, counters compared against
the golden summary. Gate: e2e_test PASS with zero tolerance on detection
records (exact integer energy model).

## Step 11 -- Software datapath (HLS)

With the RTL chain green, the HLS kernels (fft_psd, tile_pack, replay_gov,
fir_chan) are verified separately in C: csim against the SAME golden
vectors, zero tolerance, because the arithmetic is exact integer. Then
pragma-based DSE (pipeline/unroll/dataflow/partition) with the schedule
report as evidence -- the course Section 2 workflow, applied for real.

## Step 12 -- Regression and release

One command runs everything (ci/regress.sh). CI (GitHub Actions,
self-hosted Vivado runner) gates merges on: every TB prints PASS, WNS >= 0,
utilization < 80%. Tag v1.0 from a green pipeline.

---

## Applying this flow to your own projects (checklist)

1. Can I state the mission in one paragraph?
2. Is every requirement paired with the test that proves it?
3. Is there an ICD, and is it frozen?
4. Does one generator produce golden vectors for every domain?
5. Is my checker independent of my DUT code?
6. Did every block pass alone before it met its neighbor?
7. Does a clean clone build and pass with one command?
8. Can I release from a green CI pipeline without touching a GUI?

If yes to all eight: you are doing what professional teams do. Welcome.

---

## Where each artifact lives

| Step | Artifact | Path |
|------|----------|------|
| 1-5  | Architecture + ICD summary | docs/ARCHITECTURE.md, docs/ICD.md |
| 5    | Golden vector generator   | sw/golden/gen_vectors.py |
| 5-10 | UVM env + tests           | uvm/sentry_ifs.sv, uvm/sentry_uvm_pkg.sv, uvm/tb_*.sv |
| 7-10 | RTL blocks                | rtl/*.sv |
| 11   | HLS kernels + TBs + TCLs  | hls/*/ |
| 12   | Regression + gates        | ci/regress.sh, ci/build.tcl, .github/workflows/fpga.yml |
