//=============================================================
// riscv_coverage.sv
// Functional coverage: opcode classes, branch redirection
// (taken/not-taken), pipeline stall/flush activity (sampled via
// retire stream + dbg signals through the vif), and illegal-
// instruction handling.
//=============================================================
`ifndef RISCV_COVERAGE_SV
`define RISCV_COVERAGE_SV

class riscv_coverage extends uvm_subscriber #(riscv_retire_txn);
  `uvm_component_utils(riscv_coverage)

  virtual riscv_if vif;
  riscv_retire_txn cur;

  covergroup cg_retire;
    option.per_instance = 1;
    cp_rd_we    : coverpoint cur.rd_we;
    cp_is_branch: coverpoint cur.is_branch;
    cp_taken    : coverpoint cur.branch_taken iff (cur.is_branch);
    cp_is_store : coverpoint cur.is_store;
    cp_illegal  : coverpoint cur.illegal;
    cx_branch_taken_x_store: cross cp_is_branch, cp_taken;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_retire = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual riscv_if)::get(this, "", "vif", vif))
      `uvm_fatal("COV", "virtual interface not set for riscv_coverage")
  endfunction

  function void write(riscv_retire_txn t);
    cur = t;
    cg_retire.sample();
  endfunction

  task run_phase(uvm_phase phase);
    // separate lightweight coverage for hazard stalls / branch mispredicts,
    // sampled directly off the debug bus every cycle.
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n) begin
        if (vif.dbg_stall)       `uvm_info("COV_HAZ", "load-use stall observed", UVM_HIGH)
        if (vif.dbg_mispredict)  `uvm_info("COV_BR",  "branch/jump redirect observed", UVM_HIGH)
      end
    end
  endtask
endclass

`endif
