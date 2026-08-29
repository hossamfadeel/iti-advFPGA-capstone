# Interface Control Document (ICD) -- SPECTRUM SENTRY

**Status: DRAFT -- freezes Day 2, 17:00 (hard deadline)**
Owner: Team Platform (T1). After freeze, changes require a written change
request accepted at the cross-team sync.

Full context: [Capstone_Project_Spectrum_Sentry.md](./Capstone_Project_Spectrum_Sentry.md)
sections 4.5 (framing) and 5.5 (register map). This file is the living copy
the teams edit; the spec is the authority on conflicts until freeze.

## 1. Aurora frame format (v1.0 draft)

```
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

- [ ] T3: confirm magic value + type codes table
- [ ] T3: heartbeat period (1 ms proposed)
- [ ] T4: define RM ack + swap handshake frames
- [ ] T3+T4: CRC32 polynomial/initial value (match frame_check RTL + TB)

## 2. spec_ctrl register map (v1.0 draft)

| Offset | Name | Dir | Reset | Description |
|--------|------|-----|-------|-------------|
| 0x00 | ID | R | 0x53504543 | "SPEC" |
| 0x04 | VERSION | R | 0x0001_0400 | maj.min=1.4, patch 00 |
| 0x08 | CTRL | RW | 0x0 | [0] det_arm, [1] irq_en, [3:2] build (0=HP,1=HPC), [7:4] rate_pow2 |
| 0x0C | STATUS | R | - | [0] stream_lock, [1] aur_lane_up, [2] rm_active, [8] swapping |
| 0x10 | FRAME_CNT | R | 0 | good RX frames, 32-bit wrap |
| 0x14 | CRC_ERR | R | 0 | CRC failures (sticky) |
| 0x18 | DROP_CNT | R | 0 | sequence-gap drops |
| 0x1C | DET_COUNT | R | 0 | detections this epoch |
| 0x20 | THR_HI/LO | RW | - | detection thresholds |
| 0x24 | TILE_RATE | RW | 8 | tiles per 1000 PSD rows forwarded to DDR |
| 0x28 | RM_SIG | R | - | RM self-identifying magic |
| 0x2C | IRQ_FLAGS | RCW1 | 0 | frame, crc, detection, swap-done |
| 0x30 | SCRATCH | RW | 0 | PCIe/XDMA sanity poke register |
| 0x34..0x3C | rsvd | - | - | future |

- [ ] T1: implement + xsim BFM suite
- [ ] T3: Linux devmem bring-up checklist
- [ ] T5: mmap binding in A53 app

## 3. RM boundary interface (DFX slot, v1.0 draft)

- AXI4-Stream slave: 64-bit, little-endian complex INT16 pairs, tvalid/tready
  backpressure honored, tlast per 1024-sample frame
- AXI4-Stream master: detection/tile records, same side-channel rules
- AXI4-Lite status: RM_SIG magic only (read-only)
- Clock/reset: pl_clk_dsp 250 MHz, soft reset from decoupler sequence

- [ ] T2: propose RM_SIG values for RM1/RM2/RM3
- [ ] T4: decouple/quiesce timing budget (target < 200 ms total swap)

## Change log

| Date | Section | Change | Requested by | Status |
|------|---------|--------|--------------|--------|
| | | (initial draft) | T1 | draft |
