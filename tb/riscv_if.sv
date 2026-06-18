//=============================================================
// riscv_if.sv
// Bundles DUT ports, the retire/verification bus, and the
// instruction/data memory arrays + backdoor tasks the UVM
// driver/scoreboard use to load programs and peek memory.
//=============================================================
`ifndef RISCV_IF_SV
`define RISCV_IF_SV

interface riscv_if #(
  parameter int XLEN       = 32,
  parameter int IMEM_WORDS = 1024,
  parameter int DMEM_WORDS = 1024
) (input logic clk);

  logic            rst_n;

  logic [XLEN-1:0] imem_addr;
  logic [XLEN-1:0] imem_rdata;

  logic [XLEN-1:0] dmem_addr;
  logic [XLEN-1:0] dmem_wdata;
  logic [XLEN-1:0] dmem_rdata;
  logic            dmem_we;
  logic            dmem_re;
  logic [3:0]      dmem_byte_en;

  logic            retire_valid;
  logic [XLEN-1:0] retire_pc;
  logic [4:0]      retire_rd;
  logic            retire_rd_we;
  logic [XLEN-1:0] retire_rd_data;
  logic            retire_is_branch;
  logic            retire_branch_taken;
  logic            retire_is_store;
  logic [XLEN-1:0] retire_mem_addr;
  logic [XLEN-1:0] retire_mem_wdata;
  logic            retire_illegal;

  logic            dbg_stall;
  logic            dbg_flush;
  logic            dbg_mispredict;

  // ---------------- Backing memories (live in the interface so
  // the UVM driver/scoreboard can poke/peek via the vif handle) ----
  logic [XLEN-1:0] imem [0:IMEM_WORDS-1];
  logic [XLEN-1:0] dmem [0:DMEM_WORDS-1];

  assign imem_rdata = imem[imem_addr[$clog2(IMEM_WORDS)+1:2]];
  assign dmem_rdata = dmem[dmem_addr[$clog2(DMEM_WORDS)+1:2]];

  always_ff @(posedge clk) begin
    if (dmem_we) dmem[dmem_addr[$clog2(DMEM_WORDS)+1:2]] <= dmem_wdata;
  end

  task automatic imem_load(input int idx, input logic [XLEN-1:0] data);
    imem[idx] = data;
  endtask

  task automatic dmem_write(input int idx, input logic [XLEN-1:0] data);
    dmem[idx] = data;
  endtask

  task automatic dmem_peek(input int idx, output logic [XLEN-1:0] data);
    data = dmem[idx];
  endtask

  task automatic mem_clear();
    for (int i = 0; i < IMEM_WORDS; i++) imem[i] = 32'h00000013; // NOP (addi x0,x0,0)
    for (int i = 0; i < DMEM_WORDS; i++) dmem[i] = '0;
  endtask

  modport dut (
    input  imem_rdata, dmem_rdata,
    input  clk, rst_n,
    output imem_addr, dmem_addr, dmem_wdata, dmem_we, dmem_re, dmem_byte_en,
    output retire_valid, retire_pc, retire_rd, retire_rd_we, retire_rd_data,
           retire_is_branch, retire_branch_taken, retire_is_store,
           retire_mem_addr, retire_mem_wdata, retire_illegal,
           dbg_stall, dbg_flush, dbg_mispredict
  );

endinterface

`endif
