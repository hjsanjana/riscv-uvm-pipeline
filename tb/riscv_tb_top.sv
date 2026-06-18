//=============================================================
// riscv_tb_top.sv - testbench top: clock/reset, DUT instance,
// virtual interface hookup, run_test().
//=============================================================
`timescale 1ns/1ps

module riscv_tb_top;
  import uvm_pkg::*;
  import riscv_uvm_pkg::*;
  `include "uvm_macros.svh"

  logic clk = 0;
  always #5 clk = ~clk; // 100MHz

  riscv_if vif (.clk(clk));

  riscv_top #(.XLEN(32)) dut (.vif(vif.dut));

  initial begin
    uvm_config_db#(virtual riscv_if)::set(null, "*", "vif", vif);
  end

  initial begin
    run_test();
  end

  // Safety timeout in case a test forgets to drop its objection.
  initial begin
    #1_000_000;
    `uvm_fatal("TB_TOP", "Global timeout - simulation did not finish")
  end

endmodule
