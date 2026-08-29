# BOARDS.md -- Dual-Board Support: ZCU102 and Kria KR260

SPECTRUM SENTRY runs on whichever board is available. The verification-first
architecture makes this cheap: **all eight regression gates (4 UVM TBs +
4 HLS csims) are board-independent** -- they verify logic against golden
vectors and never touch a part number. Only the *platform layer* changes.

```bash
make regress                 # identical for both boards -- the signoff
make synth BOARD=kr260       # or BOARD=zcu102 -- platform build
```

## 1. Board delta table

| Aspect | ZCU102 (reference) | KR260 (K26 SOM) | Impact |
|---|---|---|---|
| Device | XCZU9EG-2FFVB1156E (600K LC) | XCK26-SFVC784-2LV-c (256K LC, VCU) | part in build.tcl table; util budgets re-check |
| Verification flow | xsim + UVM | **identical** | none |
| HLS kernels | csim identical; csynth part differs | set_part from `$env(HLS_PART)` | none for csim |
| Logical XDC (clocks 250/100, Aurora 156.25, CDC false paths) | `constr/zcu102/` | `constr/kr260/` (same domains) | none |
| Physical pins | board master XDC | fill `constr/kr260/carrier_pins.xdc` from **XTP685** (+ XTP743 schematic) | one-time bring-up task |
| Node-to-node link | SFP+ GTH, Aurora 64B/66B | **identical** (4x SFP+ on GTH; refclk 156.25 MHz, MGTREFCLK0_224, pins ~Y5/Y6 -- verify vs XTP685) | none |
| Host attach (Section 5) | PCIe Gen3 x4 + XDMA | **10G UDP over SFP+** (XXV/CMAC + PHY10G) or 1G RJ45; XDMA becomes a documented paper study | BD delta block (below) |
| DFX runtime | Linux fpga-mgr (PCAP) | fpga-mgr **or dfx-mgrd** -- the production Kria app-swap mechanism; partials as .bin/.bit via /lib/firmware | load script only |
| DPU (future) | B4096 | B2304 (K26 Vitis AI image) | model re-compile only |
| Boot | SD BOOT.BIN (PetaLinux) | SD with Kria Ubuntu/PetaLinux image; `xmutil`/dfx-mgr for bitstreams | image recipe |

## 2. What already exists in the repo for KR260

- `constr/kr260/node_{a,b}.xdc` -- logical constraints (identical domains)
- `constr/kr260/carrier_pins.xdc` -- physical-pin TEMPLATE with the exact
  official sources to fill it from (XTP685 K26 SOM master XDC, XTP743 KR260
  schematic; board part `xilinx.com:kr260_som:part0:1.1` for Board Awareness)
- `ci/build.tcl` -- BOARD argument: part table, constraint selection, and
  Kria `.bin` generation (`write_cfgmem ... BIN`) for fpga-mgr/dfx-mgr
- `Makefile` -- `BOARD ?= kr260` flows through synth/impl
- `hls/*/run_hls.tcl` -- `set_part $env(HLS_PART)` with ZCU102 default
- This document + PROJECT_REPORT board matrix

## 3. KR260 host-attach delta (Node B BD)

On ZCU102, detections reach the host over PCIe/XDMA. On KR260 (no edge
connector), the same detection stream exits over an SFP+ port instead:

```tcl
# KR260 variant, in bd/node_b.tcl (hardware stage):
# 10G UDP host attach on SFP+ #1 (GT quad 224)
set eth10g [create_bd_cell -type ip -vlnv xilinx.com:ip:xxv_ethernet:4.1 xxv_10g]
set_property -dict [list CONFIG.LINE_RATE {10} CONFIG.GT_GROUP_SELECT X0Y4 \
  CONFIG.REFCLK_FREQ 156.25 CONFIG.RX_EQ_MODE LPM] $eth10g
# det stream: rm1_energy m_axis -> UDP framing (LiteETH-style shim or
# lwIP on A53 via GEM fallback) -> host dashboard (same Python UI)
```

Everything upstream of the host port (frame_check, decouple, RM slot,
spec_ctrl, coherent S2MM) is byte-identical between boards -- which is the
entire point of freezing the ICD before the platform work.

## 4. Bring-up checklist: 2x KR260 rig (node-to-node)

**Bench kit:** 2x KR260, 1-2 SFP+ DAC cables (10G, 1-3 m), microSD cards,
micro-USB for UART/JTAG, host PC on the same LAN (1G RJ45 is fine for the
dashboard at demo rates; 10G NIC optional).

1. **Boot images:** flash the AMD Kria Ubuntu (or PetaLinux) image for
   KR260 on both SD cards; boot; console over micro-USB.
2. **Fill physical pins:** download XTP685 (`xtp685-kria-k26-som-xdc.zip`)
   and the KR260 carrier files; populate
   `constr/kr260/carrier_pins.xdc` (SFP+ lane pairs, MGTREFCLK0_224 P/N,
   LEDs). Budget: one focused session -- this is the only genuinely new
   hardware task.
3. **First bitstream (loopback):** build Node B with
   `make all BOARD=kr260`, convert per dfx-mgr/fpga-mgr requirements, load
   on board 1; bring up the Aurora 64B/66B IP (Lab05 GT flow) in SFP+
   loopback (DAC loopback plug or cable to board 2 port-to-same-board);
   confirm lane_up + zero errors over a soak.
4. **Two-node link:** build Node A for board 1 and Node B for board 2; DAC
   cable between SFP+ #0 on each; confirm frame counters advance
   (`devmem 0x80000010`) and CRC_ERR stays 0.
5. **DFX swap on target:** generate RM1/RM3 partials for XCK26 (Lab01
   flow), load via `dfx-mgr` or `/sys/class/fpga_manager`; measure swap
   latency against the < 200 ms target; swap under live link traffic.
6. **Host dashboard:** point the Python dashboard at the board's UDP
   stream (10G SFP+ or 1G RJ45 fallback).
7. **Regression parity:** after ANY RTL change, `make regress` on the PC
   remains the signoff -- the boards only re-verify platform glue.

## 5. Why this is a feature, not a port

The course's central lesson shows up here: because the ICD was frozen
first, verification was written against interfaces (not pins), golden
vectors are arithmetic (not boards), and the platform layer was the only
board-specific code from day one. Adding a board = adding a row in a part
table + one pin file + a documented host-port delta. Students can point at
this document in an interview as a worked example of portability by
architecture.
