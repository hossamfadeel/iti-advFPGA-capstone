# VERIFICATION_PLAN.md -- SPECTRUM SENTRY

## 1. Verification architecture (the virtual ZCU102)

```
   beat_seq items (golden .mem)         axil_write/axil_read tasks
            |                                     | (clocking blocks)
   axis_master_agent                      "the PS" on axi_lite_if
   (mailbox-fed driver)                          |
            v                                    v
   +-------------------- DUT (per TB) ----------------------+
   |  tb_spec_ctrl : spec_ctrl                             |
   |  tb_frame_check: frame_check + spec_ctrl              |
   |  tb_decouple  : decouple                              |
   |  tb_sentry_e2e: frame_gen > cdc_fifo > frame_check    |
   |                 > decouple > rm1_energy + spec_ctrl   |
   +----------|---------------------------|----------------+
              v                           v
   axis_slave_agent (random tready)   axi_lite_monitor -> RAL predictor
              |                           |
              v                           v
   beat_file_sb (golden .mem)      frame_model_sb (ICD-derived counters)
```

Principles (see ARCHITECTURE.md section 7):
1. One Python generator (seed 260) is the single source of golden truth for
   RTL sims, UVM scoreboards, and HLS csim.
2. Two independent checkers per datapath: golden-file compare + protocol
   model written from the ICD.
3. RAL mirrors bus activity through the predictor (adapter + passive
   monitor); access is performed by PS-style tasks.
4. PASS = printed PASS line + zero UVM_ERROR/UVM_FATAL (CI greps this).

## 2. Test matrix

| TB | DUT(s) | Stimulus | Checks | Coverage |
|----|--------|----------|--------|----------|
| tb_spec_ctrl | spec_ctrl | reg accesses, event pulses, pin wiggles | ID/VERSION, reset values, RW (SCRATCH/CTRL/THR), event counters, IRQ_FLAGS W1C semantics, STATUS bits, RAL mirror | reg address bins (ctrl/thr/counters/irq), read/write ops |
| tb_frame_check | frame_check + spec_ctrl | 16 golden frames incl. 1 corrupt CRC, 1 heartbeat, 1 seq gap, random gaps | 420 forwarded beats exact; counters DUT==model==golden (15/1/2) | frame length x backpressure cross |
| tb_decouple | decouple | 450 golden beats + 3 mid-stream decouple toggles | zero loss/dup through swaps (450/450), swap count | payload/det lengths, bp cross |
| tb_sentry_e2e | full chain | 450 sample beats (15 frames), PS config of THR/det_arm | 24/24 detection beats exact, FRAME_CNT=15, DET_COUNT=12, CRC_ERR=0 | lengths, bp, det records |

HLS csim matrix: fft_psd (1024 PSD bytes), tile_pack (513 beats),
replay_gov (16->8 frames), fir_chan (1024 outputs) -- all zero tolerance.

## 3. Sign-off criteria

- All four UVM TBs print PASS with zero errors (ci/regress_uvm.sh).
- All four HLS csims print PASS (ci/regress_hls.sh).
- Coverage bins defined above hit (xsim functional coverage collected per
  run; report under build/logs).
- On Questa/VCS (if used): sequencer-based drivers may be restored; the
  checking architecture is unchanged.

## 4. Known tool issues (engineering log -- read before fighting xsim)

1. **xsim 2025.2 + bundled UVM 1.2: sequencer rendezvous deadlock.**
   `uvm_sequencer` `get_next_item`/`finish_item` never complete (driver
   blocked, sequence blocked in finish_item) regardless of active/passive or
   adapter wiring. Workaround in this repo: stimulus transport via mailbox
   (streams) and direct clocking-block tasks (AXI-Lite). Monitors,
   scoreboards, analysis ports, RAL + predictor all work correctly.
2. **UVM DPI linking.** The UVM package imports DPI-C functions; linking the
   compiled package fails for missing C symbols, and the precompiled `-L uvm`
   path hangs at time 0 (name-check phase). Workaround: compile the bundled
   package with `-d UVM_NO_DPI` (pure SystemVerilog). Note the benign
   "name checks require DPI" info message.
3. **`xelab --timescale` required** when mixing files with and without
   timescale directives (UVM package has none).
4. **Windows specifics:** xsim .bat wrappers mangle quoted plusargs with
   drive letters; pass no plusargs and run in a directory where `vectors/`
   resolves (the regress script copies vectors into the sim dir); zombie
   xsim processes hold library locks -- the regress script kills them and
   uses a unique sim dir per run.

## 5. Bugs found by verification (root-cause log)

| # | Bug | Found by | Root cause / fix |
|---|-----|----------|------------------|
| 1 | AXI-Lite reads hang | spec_ctrl TB bring-up | DUT retires rvalid one cycle after arready when rready is held; driver waited rvalid in a separate loop -> qualify arready && rvalid in one wait |
| 2 | Frames eaten during reset | tb_frame_check (missing first frame) | DUTs accepted stream beats while rst_n=0 (s_tready not gated) -> gate s_tready with rst_n in frame_check and rm1_energy; stimulus driver waits for reset |
| 3 | X-poisoned chain deadlock | tb_sentry_e2e heartbeat probe | decouple released rm_rstn during system reset -> RM1 registers never initialized -> X on tready poisoned handshakes upstream -> assert rm_rstn during system reset (real DFX decoupler behavior) |
| 4 | FRAME_CNT=17, detection energies off | tb_sentry_e2e golden counters | frame_gen copied producer data on a cycle with s_tready=0 (no handshake), then refilled the same stale beat -> duplicated payload beats, shifted frame boundaries -> load only on a real s-side handshake (combined-handshake pattern) |
| 5 | fft_psd 465 PSD mismatches | HLS csim golden compare | log2_8 truncated int64 magnitudes through uint32 (|X|^2 up to ~9e14) -> widen to uint64 |
| 6 | tile_pack 484 mismatches | HLS csim | per-group max-hold never reset between 16-bin groups (running max) -> restructure DEC loop per group |
| 7 | tile_pack row shifts (CRLF) | HLS csim mismatch pattern | TB fgets buffer 2048 < 1024 pairs + CRLF; lines truncated mid-pair -> widen buffer |
| 8 | parse aliasing UB | code review before csim | fscanf into (unsigned short*)&int16_t violates strict aliasing -> parse to unsigned short, then cast |

Items 3 and 4 are the flagship teaching cases: both were invisible to unit
tests and only express at integration -- the reason the e2e gate exists.
