//=============================================================
// riscv_top.sv
// Pure DUT wrapper: binds riscv_core to the verification
// interface. Instruction/data memories live inside riscv_if
// (tb/riscv_if.sv) so the UVM driver can load programs directly
// through the virtual interface handle.
//=============================================================
`ifndef RISCV_TOP_SV
`define RISCV_TOP_SV

module riscv_top
#(
  parameter int XLEN = 32
)(
  riscv_if.dut vif
);

  riscv_core #(.XLEN(XLEN)) u_core (
    .clk            (vif.clk),
    .rst_n          (vif.rst_n),
    .imem_addr      (vif.imem_addr),
    .imem_rdata     (vif.imem_rdata),
    .dmem_addr      (vif.dmem_addr),
    .dmem_wdata     (vif.dmem_wdata),
    .dmem_rdata     (vif.dmem_rdata),
    .dmem_we        (vif.dmem_we),
    .dmem_re        (vif.dmem_re),
    .dmem_byte_en   (vif.dmem_byte_en),
    .retire_valid        (vif.retire_valid),
    .retire_pc           (vif.retire_pc),
    .retire_rd           (vif.retire_rd),
    .retire_rd_we        (vif.retire_rd_we),
    .retire_rd_data      (vif.retire_rd_data),
    .retire_is_branch    (vif.retire_is_branch),
    .retire_branch_taken (vif.retire_branch_taken),
    .retire_is_store     (vif.retire_is_store),
    .retire_mem_addr     (vif.retire_mem_addr),
    .retire_mem_wdata    (vif.retire_mem_wdata),
    .retire_illegal      (vif.retire_illegal),
    .dbg_stall      (vif.dbg_stall),
    .dbg_flush      (vif.dbg_flush),
    .dbg_mispredict (vif.dbg_mispredict)
  );

endmodule

`endif
