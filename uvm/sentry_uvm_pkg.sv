// ============================================================================
// Package: sentry_uvm_pkg
// Description: UVM environment for SPECTRUM SENTRY (the "virtual ZCU102").
//
//   CHECKING architecture (the UVM value): passive AXI4-Lite monitor with
//   coverage + RAL predictor, AXI4-Stream monitors with frame/backpressure
//   coverage, golden-vector beat scoreboard, independent protocol-model
//   scoreboard, RW/RO/W1C register checking.
//
//   STIMULUS transport: direct clocking-block tasks for AXI-Lite
//   (axil_write/axil_read in the base test) and a mailbox-fed stream driver.
//   The standard uvm_sequencer rendezvous (get_next_item/finish_item)
//   deadlocks in the UVM-1.2 build bundled with xsim 2025.2 (see
//   docs/VERIFICATION_PLAN.md, "Known tool issues"); monitors, scoreboards
//   and the RAL predictor are unaffected. On Questa/VCS the sequencer-based
//   drivers can be restored without touching the checking architecture.
// ============================================================================
`timescale 1ns/1ps
package sentry_uvm_pkg;

  import uvm_pkg::*;
  import sentry_defs::*;
  `include "uvm_macros.svh"

  // =========================================================================
  // Transactions
  // =========================================================================
  class axi_lite_item extends uvm_sequence_item;
    rand bit         is_write;
    rand logic [5:0] addr;
    rand logic [31:0] data;
    logic [1:0]      resp;

    `uvm_object_utils_begin(axi_lite_item)
      `uvm_field_int(is_write, UVM_ALL_ON)
      `uvm_field_int(addr,    UVM_ALL_ON)
      `uvm_field_int(data,    UVM_ALL_ON)
      `uvm_field_int(resp,    UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi_lite_item");
      super.new(name);
    endfunction
  endclass

  class axis_item extends uvm_sequence_item;
    logic [63:0] data[];       // beats of one frame/record
    int          max_gap = 0;  // driver may insert up to N idle cycles/beat

    `uvm_object_utils_begin(axis_item)
      `uvm_field_array_int(data, UVM_ALL_ON)
      `uvm_field_int(max_gap, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axis_item");
      super.new(name);
    endfunction

    function void set_beats(const ref logic [63:0] q[$], input int gap = 0);
      data = new[q.size()];
      foreach (q[i]) data[i] = q[i];
      max_gap = gap;
    endfunction
  endclass

  // =========================================================================
  // AXI4-Lite monitor (passive): publishes completed bus transactions
  // =========================================================================
  class axi_lite_monitor extends uvm_monitor;
    `uvm_component_utils(axi_lite_monitor)
    virtual axi_lite_if vif;
    uvm_analysis_port #(axi_lite_item) ap;

    covergroup al_cg with function sample(bit is_wr, logic [5:0] a);
      cp_op: coverpoint is_wr;
      cp_addr: coverpoint a { bins ctrl = {REG_CTRL};
                              bins thr  = {REG_THR};
                              bins cnt  = {REG_FRAME_CNT, REG_CRC_ERR,
                                           REG_DROP_CNT, REG_DET_COUNT};
                              bins irq  = {REG_IRQ_FLAGS}; }
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      al_cg = new();
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "axi_lite_if missing in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      axi_lite_item it;
      forever begin
        @(vif.mon_cb);
        if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
          it = axi_lite_item::type_id::create("wr");
          it.is_write = 1;
          it.addr = vif.mon_cb.awaddr;
          it.data = vif.mon_cb.wdata;
          it.resp = vif.mon_cb.bresp;
          al_cg.sample(1, vif.mon_cb.awaddr);
          ap.write(it);
        end
        if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
          it = axi_lite_item::type_id::create("rd");
          it.is_write = 0;
          it.addr = vif.mon_cb.araddr;
          it.data = vif.mon_cb.rdata;
          it.resp = vif.mon_cb.rresp;
          al_cg.sample(0, vif.mon_cb.araddr);
          ap.write(it);
        end
      end
    endtask
  endclass

  // =========================================================================
  // AXI4-Lite passive agent (monitor + coverage; stimulus comes from the
  // base-test axil_write/axil_read tasks on the same virtual interface)
  // =========================================================================
  class axi_lite_agent extends uvm_agent;
    `uvm_component_utils(axi_lite_agent)
    axi_lite_monitor mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon = axi_lite_monitor::type_id::create("mon", this);
    endfunction
  endclass

  // =========================================================================
  // AXI4-Stream master driver (mailbox-fed; no sequencer rendezvous)
  // =========================================================================
  class axis_master_driver extends uvm_component;
    `uvm_component_utils(axis_master_driver)
    virtual axis_if vif;
    mailbox #(axis_item) mb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      mb = new("mb");
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "axis_if missing in config_db")
    endfunction

    task submit(axis_item it);
      mb.put(it);
    endtask

    task run_phase(uvm_phase phase);
      axis_item it;
      vif.drv_cb.tvalid <= 0;
      vif.drv_cb.tlast  <= 0;
      vif.drv_cb.tdata  <= '0;
      wait (vif.rst_n === 1'b1);   // stimulus discipline: no beats in reset
      forever begin
        mb.get(it);
        foreach (it.data[k]) begin
          int gap;
          gap = (it.max_gap > 0) ? $urandom_range(0, it.max_gap) : 0;
          if (gap > 0) repeat (gap) @(vif.drv_cb);
          @(vif.drv_cb);
          vif.drv_cb.tdata  <= it.data[k];
          vif.drv_cb.tlast  <= (k == it.data.size() - 1);
          vif.drv_cb.tvalid <= 1;
          do @(vif.drv_cb); while (!vif.drv_cb.tready);
          vif.drv_cb.tvalid <= 0;
        end
      end
    endtask
  endclass

  // =========================================================================
  // AXI4-Stream slave (random-ready sink): backpressure generator
  // =========================================================================
  class axis_slave_driver extends uvm_component;
    `uvm_component_utils(axis_slave_driver)
    virtual axis_if vif;
    int ready_pct = 70;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "axis_if missing in config_db")
      if (!uvm_config_db#(int)::get(this, "", "ready_pct", ready_pct))
        ready_pct = 70;
    endfunction

    task run_phase(uvm_phase phase);
      vif.tready <= 0;
      forever begin
        int unsigned hold;
        hold = $urandom_range(1, 8);
        vif.tready <= ($urandom_range(0, 99) < ready_pct);
        repeat (hold) @(vif.drv_cb);
      end
    endtask
  endclass

  // =========================================================================
  // AXI4-Stream monitor (assembles beats into frames at handshakes)
  // =========================================================================
  class axis_monitor extends uvm_monitor;
    `uvm_component_utils(axis_monitor)
    virtual axis_if vif;
    uvm_analysis_port #(axis_item) ap;
    logic [63:0] qb[$];
    protected bit bp_seen;   // backpressure observed within current frame

    covergroup stream_cg with function sample(int beats, bit bp);
      cp_len: coverpoint beats { bins det_rec = {2};
                                 bins payload = {30};
                                 bins frame   = {32}; }
      cp_bp:  coverpoint bp;
      x_len_bp: cross cp_len, cp_bp;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      stream_cg = new();
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "axis_if missing in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      axis_item it;
      forever begin
        @(vif.mon_cb);
        if (vif.mon_cb.tvalid) begin
          if (!vif.mon_cb.tready) bp_seen = 1;
          else begin
            qb.push_back(vif.mon_cb.tdata);
            if (vif.mon_cb.tlast) begin
              it = axis_item::type_id::create("frame");
              it.set_beats(qb);
              qb.delete();
              stream_cg.sample(it.data.size(), bp_seen);
              bp_seen = 0;
              ap.write(it);
            end
          end
        end
      end
    endtask
  endclass

  // =========================================================================
  // AXI4-Stream agents
  // =========================================================================
  class axis_master_agent extends uvm_agent;
    `uvm_component_utils(axis_master_agent)
    axis_master_driver drv;
    axis_monitor       mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon = axis_monitor::type_id::create("mon", this);
      if (get_is_active() == UVM_ACTIVE)
        drv = axis_master_driver::type_id::create("drv", this);
    endfunction

    task submit(axis_item it);
      drv.submit(it);
    endtask
  endclass

  class axis_slave_agent extends uvm_agent;
    `uvm_component_utils(axis_slave_agent)
    axis_slave_driver drv;
    axis_monitor      mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon = axis_monitor::type_id::create("mon", this);
      if (get_is_active() == UVM_ACTIVE)
        drv = axis_slave_driver::type_id::create("drv", this);
    endfunction
  endclass

  // =========================================================================
  // RAL: sentry register block (ICD v1.0 register map)
  // =========================================================================
  class sentry_reg extends uvm_reg;
    `uvm_object_utils(sentry_reg)
    uvm_reg_field value;

    function new(string name = "sentry_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    function void configure_reg(uvm_reg_block parent, int offset, string acc,
                                logic [31:0] reset);
      value = new("value");
      value.configure(this, 32, 0, acc, 0, reset, 1, 0, 1);
      configure(parent);
      parent.default_map.add_reg(this, offset, "RW");
    endfunction
  endclass

  class sentry_reg_block extends uvm_reg_block;
    `uvm_object_utils(sentry_reg_block)
    rand sentry_reg r_id, r_version, r_ctrl, r_status, r_frame_cnt,
                    r_crc_err, r_drop_cnt, r_det_count, r_thr, r_tile_rate,
                    r_rm_sig, r_irq_flags, r_scratch, r_rsvd0, r_rsvd1, r_rsvd2;

    function new(string name = "sentry_reg_block");
      super.new(name, UVM_NO_COVERAGE);
    endfunction

    function void build();
      r_id        = sentry_reg::type_id::create("r_id");
      r_version   = sentry_reg::type_id::create("r_version");
      r_ctrl      = sentry_reg::type_id::create("r_ctrl");
      r_status    = sentry_reg::type_id::create("r_status");
      r_frame_cnt = sentry_reg::type_id::create("r_frame_cnt");
      r_crc_err   = sentry_reg::type_id::create("r_crc_err");
      r_drop_cnt  = sentry_reg::type_id::create("r_drop_cnt");
      r_det_count = sentry_reg::type_id::create("r_det_count");
      r_thr       = sentry_reg::type_id::create("r_thr");
      r_tile_rate = sentry_reg::type_id::create("r_tile_rate");
      r_rm_sig    = sentry_reg::type_id::create("r_rm_sig");
      r_irq_flags = sentry_reg::type_id::create("r_irq_flags");
      r_scratch   = sentry_reg::type_id::create("r_scratch");
      r_rsvd0     = sentry_reg::type_id::create("r_rsvd0");
      r_rsvd1     = sentry_reg::type_id::create("r_rsvd1");
      r_rsvd2     = sentry_reg::type_id::create("r_rsvd2");

      default_map = create_map("map", 'h0, 4, UVM_LITTLE_ENDIAN, 1);

      r_id.configure_reg(       this, REG_ID,        "RO", REG_ID_VAL);
      r_version.configure_reg(  this, REG_VERSION,   "RO", REG_VERSION_VAL);
      r_ctrl.configure_reg(     this, REG_CTRL,      "RW", 32'h0);
      r_status.configure_reg(   this, REG_STATUS,    "RO", 32'h0);
      r_frame_cnt.configure_reg(this, REG_FRAME_CNT, "RO", 32'h0);
      r_crc_err.configure_reg(  this, REG_CRC_ERR,   "RO", 32'h0);
      r_drop_cnt.configure_reg( this, REG_DROP_CNT,  "RO", 32'h0);
      r_det_count.configure_reg(this, REG_DET_COUNT, "RO", 32'h0);
      r_thr.configure_reg(      this, REG_THR,       "RW", 32'h0);
      r_tile_rate.configure_reg(this, REG_TILE_RATE, "RW", 32'd8);
      r_rm_sig.configure_reg(   this, REG_RM_SIG,    "RO", 32'h0);
      r_irq_flags.configure_reg(this, REG_IRQ_FLAGS, "W1C", 32'h0);
      r_scratch.configure_reg(  this, REG_SCRATCH,   "RW", 32'h0);
      r_rsvd0.configure_reg(    this, REG_RSVD0,     "RO", 32'h0);
      r_rsvd1.configure_reg(    this, REG_RSVD1,     "RO", 32'h0);
      r_rsvd2.configure_reg(    this, REG_RSVD2,     "RO", 32'h0);
      lock_model();
    endfunction
  endclass

  class axi_lite_adapter extends uvm_reg_adapter;
    `uvm_object_utils(axi_lite_adapter)

    function new(string name = "axi_lite_adapter");
      super.new(name);
      supports_byte_enable = 0;
      provides_responses   = 0;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      axi_lite_item it = axi_lite_item::type_id::create("it");
      it.is_write = (rw.kind == UVM_WRITE);
      it.addr     = rw.addr[5:0];
      it.data     = rw.data;
      return it;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item,
                                  ref uvm_reg_bus_op rw);
      axi_lite_item it;
      if (!$cast(it, bus_item)) begin
        `uvm_fatal("BADCAST", "bus2reg cast failed")
        return;
      end
      rw.kind   = it.is_write ? UVM_WRITE : UVM_READ;
      rw.addr   = 32'(it.addr);
      rw.data   = it.data;
      rw.status = UVM_IS_OK;
    endfunction
  endclass

  // =========================================================================
  // Scoreboard: golden beat-file comparison (deterministic vectors)
  // =========================================================================
  class beat_file_sb extends uvm_component;
    `uvm_component_utils(beat_file_sb)
    uvm_analysis_imp #(axis_item, beat_file_sb) imp;
    string       path;
    logic [63:0] exp[$];
    int unsigned checked;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      imp = new("imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
      int fd;
      logic [63:0] v;
      super.build_phase(phase);
      fd = $fopen(path, "r");
      if (fd == 0) `uvm_fatal("NOFILE", $sformatf("cannot open %s", path))
      while ($fscanf(fd, "%h\n", v) == 1) exp.push_back(v);
      $fclose(fd);
      `uvm_info("BEATSB", $sformatf("loaded %0d expected beats from %s",
                exp.size(), path), UVM_LOW)
    endfunction

    function void write(axis_item t);
      foreach (t.data[k]) begin
        logic [63:0] e;
        if (exp.size() == 0) begin
          `uvm_error("BEATSB", "extra beats observed beyond expected file")
          return;
        end
        e = exp.pop_front();
        if (e !== t.data[k])
          `uvm_error("BEATSB", $sformatf(
            "beat %0d mismatch: exp %016h got %016h", checked, e, t.data[k]))
        checked++;
      end
    endfunction

    function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      if (exp.size() != 0)
        `uvm_error("BEATSB", $sformatf("%0d expected beats never observed",
                  exp.size()))
      else if (checked > 0)
        `uvm_info("BEATSB", $sformatf("PASS: %0d beats matched exactly",
                  checked), UVM_NONE)
    endfunction
  endclass

  // =========================================================================
  // Scoreboard: frame_check protocol model (independent counter prediction)
  // =========================================================================
  class frame_model_sb extends uvm_component;
    `uvm_component_utils(frame_model_sb)
    uvm_analysis_imp #(axis_item, frame_model_sb) imp;
    int unsigned good, crc_err, drop;
    protected int unsigned exp_seq;
    protected bit        seq_valid;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      imp = new("imp", this);
    endfunction

    function void write(axis_item t);
      logic [31:0] c;
      logic [15:0] seq;
      if (t.data.size() != FRAME_BEATS) begin
        `uvm_error("MODELSB", "observed frame is not 32 beats")
        return;
      end
      c = 32'hFFFF_FFFF;
      for (int n = 0; n < 31; n++) c = crc32_beat(c, t.data[n]);
      c = c ^ 32'hFFFF_FFFF;
      seq = hdr_seq(t.data[0]);
      if (c == t.data[31][31:0]) begin
        good++;
        if (seq_valid && seq != exp_seq) drop++;
        exp_seq   = (seq + 16'd1) & 16'hFFFF;
        seq_valid = 1;
      end else begin
        crc_err++;
      end
    endfunction

    function void report_counters(string tag = "");
      `uvm_info("MODELSB", $sformatf(
        "%s model counters: GOOD=%0d CRC=%0d DROP=%0d", tag, good, crc_err,
        drop), UVM_LOW)
    endfunction
  endclass

  // =========================================================================
  // Environment configuration
  // =========================================================================
  class sentry_env_cfg extends uvm_object;
    `uvm_object_utils(sentry_env_cfg)
    bit    has_axil       = 1;
    bit    has_stream_in  = 1;   // master agent (stimulus)
    bit    has_stream_out = 1;   // slave agent (sink) + monitor
    bit    model_on_in    = 0;   // connect model scoreboard to input monitor
    string out_expect_path = ""; // golden beats for the output stream
    int    sink_ready_pct = 70;
    string vec_dir = "vectors";

    function new(string name = "sentry_env_cfg");
      super.new(name);
    endfunction
  endclass

  class sentry_env extends uvm_env;
    `uvm_component_utils(sentry_env)
    sentry_env_cfg   cfg;
    virtual axi_lite_if avif;
    sentry_reg_block regmodel;
    axi_lite_adapter adapter;
    uvm_reg_predictor #(axi_lite_item) predictor;
    axi_lite_agent    axil_ag;
    axis_master_agent stream_in_ag;
    axis_slave_agent  stream_out_ag;
    beat_file_sb      out_sb;
    frame_model_sb    model_sb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (cfg == null)
        if (!uvm_config_db#(sentry_env_cfg)::get(this, "", "cfg", cfg))
          cfg = sentry_env_cfg::type_id::create("cfg");
      if (cfg.has_axil) begin
        regmodel  = sentry_reg_block::type_id::create("regmodel");
        regmodel.build();
        adapter   = axi_lite_adapter::type_id::create("adapter");
        predictor = uvm_reg_predictor#(axi_lite_item)::type_id::create(
                    "predictor", this);
        axil_ag   = axi_lite_agent::type_id::create("axil_ag", this);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "axil_ag",
                     "is_active", UVM_PASSIVE);
      end
      if (cfg.has_stream_in) begin
        stream_in_ag = axis_master_agent::type_id::create("stream_in_ag", this);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "stream_in_ag",
                     "is_active", UVM_ACTIVE);
      end
      if (cfg.has_stream_out) begin
        stream_out_ag = axis_slave_agent::type_id::create("stream_out_ag", this);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "stream_out_ag",
                     "is_active", UVM_ACTIVE);
        uvm_config_db#(int)::set(this, "stream_out_ag.drv",
                     "ready_pct", cfg.sink_ready_pct);
        if (cfg.out_expect_path != "") begin
          out_sb = beat_file_sb::type_id::create("out_sb", this);
          out_sb.path = cfg.out_expect_path;
        end
      end
      model_sb = frame_model_sb::type_id::create("model_sb", this);
      void'(uvm_config_db#(virtual axi_lite_if)::get(this, "", "axil_vif",
                                                     avif));
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      if (cfg.has_axil) begin
        predictor.map     = regmodel.default_map;
        predictor.adapter = adapter;
        axil_ag.mon.ap.connect(predictor.bus_in);
      end
      if (cfg.has_stream_out && out_sb != null)
        stream_out_ag.mon.ap.connect(out_sb.imp);
      if (cfg.model_on_in && cfg.has_stream_in)
        stream_in_ag.mon.ap.connect(model_sb.imp);
    endfunction

    // Stimulus API used by tests
    task submit(axis_item it);
      stream_in_ag.submit(it);
    endtask

    // Response-side ready defaults: held high for the whole run (the PS
    // always accepts responses in this design)
    task run_phase(uvm_phase phase);
      if (cfg.has_axil && avif != null) begin
        avif.bready <= 1'b1;
        avif.rready <= 1'b1;
      end
    endtask
  endclass

  // =========================================================================
  // Utility: file readers
  // =========================================================================
  class sentry_files;
    static function void read_beats(string path, ref logic [63:0] q[$]);
      int fd;
      logic [63:0] v;
      fd = $fopen(path, "r");
      if (fd == 0) `uvm_fatal("NOFILE", $sformatf("cannot open %s", path))
      while ($fscanf(fd, "%h\n", v) == 1) q.push_back(v);
      $fclose(fd);
    endfunction

    static function void read_summary(string path, output int good,
                                      output int crc_e, output int drop,
                                      output int fwd);
      int fd;
      fd = $fopen(path, "r");
      if (fd == 0) `uvm_fatal("NOFILE", $sformatf("cannot open %s", path))
      void'($fscanf(fd, "GOOD=%0d CRC=%0d DROP=%0d FWD_BEATS=%0d",
                    good, crc_e, drop, fwd));
      $fclose(fd);
    endfunction

    static function void read_e2e_summary(string path, output int thr,
                                          output int frames, output int det);
      int fd;
      fd = $fopen(path, "r");
      if (fd == 0) `uvm_fatal("NOFILE", $sformatf("cannot open %s", path))
      void'($fscanf(fd, "THR=%h FRAMES=%0d DET=%0d", thr, frames, det));
      $fclose(fd);
    endfunction
  endclass

  // =========================================================================
  // Base test: direct AXI-Lite transport (clocking blocks) + submit API
  // =========================================================================
  class sentry_base_test extends uvm_test;
    `uvm_component_utils(sentry_base_test)
    sentry_env          env;
    virtual axi_lite_if avif;
    string              vec_dir;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!$value$plusargs("VECTORS=%s", vec_dir)) vec_dir = "vectors";
      env = sentry_env::type_id::create("env", this);
      uvm_top.set_timeout(50ms, 1);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "axil_vif",
                                                    avif))
        if (env.cfg.has_axil)
          `uvm_fatal("NOVIF", "axil_vif missing in config_db")
    endfunction

    // ---- AXI4-Lite transport (the "PS" side) -------------------------------
    task axil_write(logic [5:0] addr, logic [31:0] data);
      @(avif.drv_cb);
      avif.drv_cb.awaddr  <= addr;
      avif.drv_cb.awvalid <= 1;
      avif.drv_cb.wdata   <= data;
      avif.drv_cb.wstrb   <= 4'hF;
      avif.drv_cb.wvalid  <= 1;
      do @(avif.drv_cb); while (!(avif.drv_cb.awready && avif.drv_cb.wready));
      avif.drv_cb.awvalid <= 0;
      avif.drv_cb.wvalid  <= 0;
      do @(avif.drv_cb); while (!avif.drv_cb.bvalid);
    endtask

    task axil_read(logic [5:0] addr, output logic [31:0] data);
      @(avif.drv_cb);
      avif.drv_cb.araddr  <= addr;
      avif.drv_cb.arvalid <= 1;
      // The DUT presents arready and rvalid in the same cycle and may
      // retire rvalid one cycle later (rready held high) -- so the loop
      // must qualify on BOTH before sampling rdata.
      do @(avif.drv_cb); while (!(avif.drv_cb.arready && avif.drv_cb.rvalid));
      avif.drv_cb.arvalid <= 0;
      data = avif.drv_cb.rdata;
    endtask

    function void report_phase(uvm_phase phase);
      uvm_report_server svr;
      int n_err;
      super.report_phase(phase);
      svr = uvm_report_server::get_server();
      n_err = svr.get_severity_count(UVM_ERROR);
      if (n_err == 0)
        $display("PASS: %s (UVM_ERROR count is zero)", get_type_name());
      else
        $display("FAIL: %s (%0d UVM_ERRORs)", get_type_name(), n_err);
    endfunction
  endclass

  // =========================================================================
  // Test 1: spec_ctrl register verification (RW/RO/W1C + event counters)
  // =========================================================================
  class spec_ctrl_test extends sentry_base_test;
    `uvm_component_utils(spec_ctrl_test)
    virtual ctrl_if civif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env.cfg                 = sentry_env_cfg::type_id::create("cfg");
      env.cfg.has_stream_in   = 0;
      env.cfg.has_stream_out  = 0;
      if (!uvm_config_db#(virtual ctrl_if)::get(this, "", "ctrl_if", civif))
        `uvm_fatal("NOVIF", "ctrl_if missing in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      logic [31:0] d;
      phase.raise_objection(this);
      // --- reset values ---
      axil_read(REG_ID, d);        check_eq("ID", d, REG_ID_VAL);
      axil_read(REG_VERSION, d);   check_eq("VERSION", d, REG_VERSION_VAL);
      axil_read(REG_CTRL, d);      check_eq("CTRL reset", d, 32'h0);
      axil_read(REG_TILE_RATE, d); check_eq("TILE_RATE reset", d, 32'd8);
      // --- RW behavior ---
      axil_write(REG_SCRATCH, 32'hDEAD_BEEF);
      axil_read(REG_SCRATCH, d);   check_eq("SCRATCH RW", d, 32'hDEAD_BEEF);
      axil_write(REG_CTRL, 32'h0000_0083);
      axil_read(REG_CTRL, d);      check_eq("CTRL RW", d, 32'h0000_0083);
      axil_write(REG_THR, 32'h0000_2000);
      axil_read(REG_THR, d);       check_eq("THR RW", d, 32'h0000_2000);
      // --- event pulses -> counters + irq flags ---
      pulse_events(3, 1, 2, 4);
      axil_read(REG_FRAME_CNT, d); check_eq("FRAME_CNT", d, 32'd3);
      axil_read(REG_CRC_ERR, d);   check_eq("CRC_ERR",   d, 32'd1);
      axil_read(REG_DROP_CNT, d);  check_eq("DROP_CNT",  d, 32'd2);
      axil_read(REG_DET_COUNT, d); check_eq("DET_COUNT", d, 32'd4);
      axil_read(REG_IRQ_FLAGS, d);
      check_eq("IRQ_FLAGS set", d & 32'hF, 32'b0111);
      // --- W1C clears only written bits ---
      axil_write(REG_IRQ_FLAGS, 32'h2);
      axil_read(REG_IRQ_FLAGS, d);
      check_eq("IRQ_FLAGS W1C", d & 32'hF, 32'b0101);
      // --- STATUS reflects pins ---
      civif.rm_sig      <= 32'h524D3100;
      civif.stream_lock <= 1;
      civif.lane_up     <= 1;
      civif.swapping    <= 0;
      repeat (3) @(civif.cb);
      axil_read(REG_STATUS, d);
      check_eq("STATUS", d, 32'h0000_0007);
      // --- RAL mirror sanity: predictor tracked the accesses ---
      if (env.regmodel.r_scratch.get_mirrored_value() != 32'hDEAD_BEEF)
        `uvm_error("RAL", "SCRATCH mirror did not follow the bus")
      else
        `uvm_info("RAL", "RAL mirror tracked SCRATCH via predictor", UVM_LOW)
      phase.drop_objection(this);
    endtask

    task pulse_events(int n_frame, int n_crc, int n_drop, int n_det);
      int f, c, dr, dt;
      f = 0; c = 0; dr = 0; dt = 0;
      while (f < n_frame || c < n_crc || dr < n_drop || dt < n_det) begin
        @(civif.cb);
        civif.ev_frame <= (f  < n_frame);
        civif.ev_crc   <= (c  < n_crc);
        civif.ev_drop  <= (dr < n_drop);
        civif.ev_det   <= (dt < n_det);
        if (f  < n_frame) f++;
        if (c  < n_crc)   c++;
        if (dr < n_drop)  dr++;
        if (dt < n_det)   dt++;
        @(civif.cb);
        civif.ev_frame <= 0;
        civif.ev_crc   <= 0;
        civif.ev_drop  <= 0;
        civif.ev_det   <= 0;
      end
      @(civif.cb);
    endtask

    function void check_eq(string what, logic [31:0] got, logic [31:0] exp);
      if (got !== exp)
        `uvm_error("TEST", $sformatf("%s: exp %08h got %08h", what, exp, got))
      else
        `uvm_info("TEST", $sformatf("%s OK (%08h)", what, got), UVM_LOW)
    endfunction
  endclass

  // =========================================================================
  // Test 2: frame_check -- golden frames in, golden payload beats out,
  //         counters: DUT vs model vs golden summary (triple check)
  // =========================================================================
  class frame_check_test extends sentry_base_test;
    `uvm_component_utils(frame_check_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env.cfg                 = sentry_env_cfg::type_id::create("cfg");
      env.cfg.out_expect_path = {vec_dir, "/frames_rx_expected.mem"};
      env.cfg.model_on_in     = 1;   // model scoreboard watches DUT input
    endfunction

    task run_phase(uvm_phase phase);
      axis_item      it;
      logic [63:0]   beats[$];
      logic [63:0]   q[$];
      logic [31:0]   d;
      int good, crc_e, drop, fwd;
      phase.raise_objection(this);
      sentry_files::read_beats({vec_dir, "/frames_tx.mem"}, beats);
      sentry_files::read_summary({vec_dir, "/frames_tx_summary.txt"},
                                 good, crc_e, drop, fwd);
      for (int f = 0; f < beats.size() / FRAME_BEATS; f++) begin
        q = '{};
        for (int k = 0; k < FRAME_BEATS; k++)
          q.push_back(beats[f*FRAME_BEATS + k]);
        it = axis_item::type_id::create($sformatf("fr%0d", f));
        it.set_beats(q, (f % 3));   // varied inter-beat gaps
        env.submit(it);
      end
      wait (env.out_sb.checked == fwd);   // all expected beats observed
      repeat (10) @(avif.drv_cb);         // settle
      // --- counter checks: DUT vs model vs golden ---
      axil_read(REG_FRAME_CNT, d);
      check3("FRAME_CNT", d, env.model_sb.good, good);
      axil_read(REG_CRC_ERR, d);
      check3("CRC_ERR", d, env.model_sb.crc_err, crc_e);
      axil_read(REG_DROP_CNT, d);
      check3("DROP_CNT", d, env.model_sb.drop, drop);
      env.model_sb.report_counters("frame_check");
      phase.drop_objection(this);
    endtask

    function void check3(string what, logic [31:0] dut, int unsigned model,
                         int golden);
      if (dut == model && model == golden)
        `uvm_info("TEST", $sformatf("%s OK: %0d (DUT==model==golden)",
                  what, dut), UVM_LOW)
      else
        `uvm_error("TEST", $sformatf(
          "%s MISMATCH: DUT=%0d model=%0d golden=%0d", what, dut, model,
          golden))
    endfunction
  endclass

  // =========================================================================
  // Test 3: decouple -- passthrough integrity across live swaps
  // =========================================================================
  class decouple_test extends sentry_base_test;
    `uvm_component_utils(decouple_test)
    virtual ctrl_if civif;
    int unsigned n_swaps;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env.cfg                 = sentry_env_cfg::type_id::create("cfg");
      env.cfg.has_axil        = 0;   // pure stream DUT, no control plane
      env.cfg.out_expect_path = {vec_dir, "/iq_stream.mem"}; // passthrough
      if (!uvm_config_db#(virtual ctrl_if)::get(this, "", "ctrl_if", civif))
        `uvm_fatal("NOVIF", "ctrl_if missing in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      axis_item     it;
      logic [63:0]  beats[$];
      logic [63:0]  q[$];
      phase.raise_objection(this);
      sentry_files::read_beats({vec_dir, "/iq_stream.mem"}, beats);
      // Submit all beats as 5-beat bursts with random gaps; the DUT is a
      // pure passthrough, so the sink must observe the identical sequence.
      for (int i = 0; i < beats.size(); i += 5) begin
        q = '{};
        for (int k = i; k < min2(i + 5, beats.size()); k++)
          q.push_back(beats[k]);
        it = axis_item::type_id::create($sformatf("burst%0d", i));
        it.set_beats(q, 2);
        env.submit(it);
      end
      // Toggle decouple_en mid-stream three times
      for (int t = 0; t < 3; t++) begin
        repeat (100 + t * 50) @(civif.cb);
        civif.decouple_en <= 1;
        n_swaps++;
        repeat (30) @(civif.cb);
        civif.decouple_en <= 0;
        repeat (30) @(civif.cb);
      end
      // Wait for drain: all beats through
      wait (env.out_sb.checked == beats.size());
      repeat (20) @(civif.cb);
      if (n_swaps != 3)
        `uvm_error("TEST", $sformatf("expected 3 swaps, saw %0d", n_swaps))
      else
        `uvm_info("TEST", "decouple swaps OK (3 swaps, no loss)", UVM_LOW)
      phase.drop_objection(this);
    endtask

    function int min2(int a, int b);
      return (a < b) ? a : b;
    endfunction
  endclass

  // =========================================================================
  // Test 4: end-to-end integration
  //   frame_gen -> cdc_async_fifo -> frame_check -> decouple -> rm1_energy
  //   with PS-side THR/det_arm configuration and golden detections
  // =========================================================================
  class e2e_test extends sentry_base_test;
    `uvm_component_utils(e2e_test)
    virtual ctrl_if civif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env.cfg                 = sentry_env_cfg::type_id::create("cfg");
      env.cfg.out_expect_path = {vec_dir, "/det_expected.mem"};
      if (!uvm_config_db#(virtual ctrl_if)::get(this, "", "ctrl_if", civif))
        `uvm_fatal("NOVIF", "ctrl_if missing in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      axis_item    it;
      logic [63:0] beats[$];
      logic [63:0] q[$];
      logic [31:0] d;
      int thr, nframes, ndet;
      phase.raise_objection(this);
      sentry_files::read_beats({vec_dir, "/iq_stream.mem"}, beats);
      sentry_files::read_e2e_summary({vec_dir, "/e2e_summary.txt"},
                                     thr, nframes, ndet);
      // Configure the node through the "PS" before traffic
      axil_write(REG_THR, thr);
      axil_write(REG_CTRL, 32'h1);   // det_arm = 1
      // Stream raw samples into frame_gen (30 beats per frame item)
      for (int f = 0; f < beats.size() / 30; f++) begin
        q = '{};
        for (int k = 0; k < 30; k++) q.push_back(beats[f*30 + k]);
        it = axis_item::type_id::create($sformatf("smp%0d", f));
        it.set_beats(q, (f % 2));
        env.submit(it);
      end
      // Wait for all expected detection beats at the sink
      wait (env.out_sb.checked == 2 * ndet);
      repeat (50) @(avif.drv_cb);  // settle; final frames drain
      // Counter checks
      axil_read(REG_FRAME_CNT, d);
      if (d == nframes)
        `uvm_info("TEST", $sformatf("FRAME_CNT OK (%0d)", d), UVM_LOW)
      else
        `uvm_error("TEST", $sformatf("FRAME_CNT exp %0d got %0d",
                  nframes, d))
      axil_read(REG_DET_COUNT, d);
      if (d == ndet)
        `uvm_info("TEST", $sformatf("DET_COUNT OK (%0d)", d), UVM_LOW)
      else
        `uvm_error("TEST", $sformatf("DET_COUNT exp %0d got %0d", ndet, d))
      axil_read(REG_CRC_ERR, d);
      if (d == 0)
        `uvm_info("TEST", "CRC_ERR OK (0)", UVM_LOW)
      else
        `uvm_error("TEST", $sformatf("CRC_ERR expected 0, got %0d", d))
      phase.drop_objection(this);
    endtask
  endclass

endpackage : sentry_uvm_pkg
