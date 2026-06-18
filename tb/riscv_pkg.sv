//=============================================================
// riscv_pkg.sv - UVM package, pulls in all testbench classes in
// dependency order. Compile this AFTER riscv_if.sv and BEFORE
// tb_top.sv.
//=============================================================
`ifndef RISCV_PKG_SV
`define RISCV_PKG_SV

package riscv_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "riscv_txn.sv"
  `include "riscv_agent.sv"
  `include "riscv_scoreboard.sv"
  `include "riscv_coverage.sv"
  `include "riscv_sequences.sv"
  `include "riscv_env.sv"
endpackage

`endif
