//=============================================================
// riscv_env.sv - top-level UVM environment and tests
//=============================================================
`ifndef RISCV_ENV_SV
`define RISCV_ENV_SV

class riscv_env extends uvm_env;
  `uvm_component_utils(riscv_env)

  riscv_agent      agent;
  riscv_scoreboard sb;
  riscv_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = riscv_agent::type_id::create("agent", this);
    sb    = riscv_scoreboard::type_id::create("sb", this);
    cov   = riscv_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.drv.instr_ap.connect(sb.instr_imp);
    agent.mon.retire_ap.connect(sb.analysis_export);
    agent.mon.retire_ap.connect(cov.analysis_export);
  endfunction
endclass

// ----------------------- Base test -----------------------
class riscv_base_test extends uvm_test;
  `uvm_component_utils(riscv_base_test)

  riscv_env env;
  virtual riscv_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = riscv_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual riscv_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "virtual interface not set for riscv_base_test")
    uvm_config_db#(virtual riscv_if)::set(this, "env.agent.drv", "vif", vif);
    uvm_config_db#(virtual riscv_if)::set(this, "env.agent.mon", "vif", vif);
    uvm_config_db#(virtual riscv_if)::set(this, "env.cov",       "vif", vif);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction
endclass

class riscv_random_test extends riscv_base_test;
  `uvm_component_utils(riscv_random_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task run_phase(uvm_phase phase);
    riscv_random_seq seq = riscv_random_seq::type_id::create("seq");
    phase.raise_objection(this);
    if (!seq.randomize()) `uvm_error("TEST", "seq randomize failed")
    seq.start(env.agent.sqr);
    repeat (5) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class riscv_hazard_test extends riscv_base_test;
  `uvm_component_utils(riscv_hazard_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task run_phase(uvm_phase phase);
    riscv_hazard_seq seq = riscv_hazard_seq::type_id::create("seq");
    phase.raise_objection(this);
    if (!seq.randomize()) `uvm_error("TEST", "seq randomize failed")
    seq.start(env.agent.sqr);
    repeat (5) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class riscv_branch_test extends riscv_base_test;
  `uvm_component_utils(riscv_branch_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task run_phase(uvm_phase phase);
    riscv_branch_seq seq = riscv_branch_seq::type_id::create("seq");
    phase.raise_objection(this);
    if (!seq.randomize()) `uvm_error("TEST", "seq randomize failed")
    seq.start(env.agent.sqr);
    repeat (5) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class riscv_exception_test extends riscv_base_test;
  `uvm_component_utils(riscv_exception_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task run_phase(uvm_phase phase);
    riscv_exception_seq seq = riscv_exception_seq::type_id::create("seq");
    phase.raise_objection(this);
    if (!seq.randomize()) `uvm_error("TEST", "seq randomize failed")
    seq.start(env.agent.sqr);
    repeat (5) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

`endif
