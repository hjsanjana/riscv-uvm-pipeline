//=============================================================
// riscv_agent.sv
// Sequencer, driver (loads a generated program into imem then
// releases reset and lets the core run), monitor (samples the
// retire bus), and the agent that wires them together.
//=============================================================
`ifndef RISCV_AGENT_SV
`define RISCV_AGENT_SV

typedef uvm_sequencer #(riscv_instr_item) riscv_sequencer;

class riscv_driver extends uvm_driver #(riscv_instr_item);
  `uvm_component_utils(riscv_driver)

  virtual riscv_if vif;
  uvm_analysis_port #(riscv_instr_item) instr_ap; // program-order broadcast for the scoreboard's golden model

  int unsigned drain_cycles = 64; // cycles to let the pipeline finish after the last instruction loads

  function new(string name, uvm_component parent);
    super.new(name, parent);
    instr_ap = new("instr_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual riscv_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "virtual interface not set for riscv_driver")
  endfunction

  task run_phase(uvm_phase phase);
    int idx;
    riscv_instr_item item;

    vif.rst_n = 1'b0;
    vif.mem_clear();
    repeat (3) @(posedge vif.clk);

    idx = 0;
    forever begin
      seq_item_port.get_next_item(item);
      vif.imem_load(idx, item.encode());
      instr_ap.write(item);
      idx++;
      seq_item_port.item_done();
      if (item.get_name() == "LAST_ITEM") break;
    end

    // trailing NOPs so the last real instruction fully drains the pipeline
    for (int i = 0; i < 8; i++) vif.imem_load(idx + i, 32'h00000013);

    @(posedge vif.clk);
    vif.rst_n = 1'b1;

    repeat (idx + drain_cycles) @(posedge vif.clk);
  endtask
endclass

class riscv_monitor extends uvm_monitor;
  `uvm_component_utils(riscv_monitor)

  virtual riscv_if vif;
  uvm_analysis_port #(riscv_retire_txn) retire_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    retire_ap = new("retire_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual riscv_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "virtual interface not set for riscv_monitor")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n && vif.retire_valid) begin
        riscv_retire_txn t = riscv_retire_txn::type_id::create("t");
        t.pc           = vif.retire_pc;
        t.rd           = vif.retire_rd;
        t.rd_we        = vif.retire_rd_we;
        t.rd_data      = vif.retire_rd_data;
        t.is_branch    = vif.retire_is_branch;
        t.branch_taken = vif.retire_branch_taken;
        t.is_store     = vif.retire_is_store;
        t.mem_addr     = vif.retire_mem_addr;
        t.mem_wdata    = vif.retire_mem_wdata;
        t.illegal      = vif.retire_illegal;
        retire_ap.write(t);
      end
    end
  endtask
endclass

class riscv_agent extends uvm_agent;
  `uvm_component_utils(riscv_agent)

  riscv_sequencer sqr;
  riscv_driver     drv;
  riscv_monitor    mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = riscv_sequencer::type_id::create("sqr", this);
    drv = riscv_driver::type_id::create("drv", this);
    mon = riscv_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass

`endif
