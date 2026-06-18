//=============================================================
// riscv_txn.sv
// UVM sequence item: one randomizable RV32I instruction, plus
// encode() to produce the raw 32-bit word loaded into imem, and
// a retire_txn used by the monitor to report observed retirements.
//=============================================================
`ifndef RISCV_TXN_SV
`define RISCV_TXN_SV

typedef enum {
  I_ADD, I_SUB, I_AND, I_OR, I_XOR, I_SLT, I_SLL, I_SRL, I_SRA,     // R-type
  I_ADDI, I_ANDI, I_ORI, I_XORI, I_SLTI, I_SLLI, I_SRLI, I_SRAI,    // I-type ALU
  I_LW, I_SW,                                                       // mem
  I_BEQ, I_BNE, I_BLT, I_BGE,                                       // branch
  I_JAL, I_JALR, I_LUI, I_AUIPC,                                    // jump/upper
  I_ILLEGAL
} instr_kind_e;

class riscv_instr_item extends uvm_sequence_item;
  rand instr_kind_e kind;
  rand bit [4:0]    rd;
  rand bit [4:0]    rs1;
  rand bit [4:0]    rs2;
  rand int          imm;       // raw signed immediate (range-checked per kind)

  // hint set by directed sequences to force a dependency on a prior rd
  bit force_dep_rs1 = 0;
  bit force_dep_rs2 = 0;

  `uvm_object_utils_begin(riscv_instr_item)
    `uvm_field_enum(instr_kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(rd,  UVM_ALL_ON)
    `uvm_field_int(rs1, UVM_ALL_ON)
    `uvm_field_int(rs2, UVM_ALL_ON)
    `uvm_field_int(imm, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "riscv_instr_item");
    super.new(name);
  endfunction

  constraint c_regs   { rd inside {[0:31]}; rs1 inside {[0:31]}; rs2 inside {[0:31]}; }
  constraint c_kind    { kind dist {
                            I_ADD:=4, I_SUB:=3, I_AND:=2, I_OR:=2, I_XOR:=2, I_SLT:=2, I_SLL:=1, I_SRL:=1, I_SRA:=1,
                            I_ADDI:=4, I_ANDI:=2, I_ORI:=2, I_XORI:=2, I_SLTI:=2, I_SLLI:=1, I_SRLI:=1, I_SRAI:=1,
                            I_LW:=3, I_SW:=3,
                            I_BEQ:=2, I_BNE:=2, I_BLT:=1, I_BGE:=1,
                            I_JAL:=1, I_JALR:=1, I_LUI:=1, I_AUIPC:=1 }; }
  constraint c_imm_i   { (kind inside {I_ADDI, I_ANDI, I_ORI, I_XORI, I_SLTI, I_LW}) -> imm inside {[-2048:2047]}; }
  constraint c_imm_sh  { (kind inside {I_SLLI, I_SRLI, I_SRAI}) -> imm inside {[0:31]}; }
  constraint c_imm_s   { (kind == I_SW) -> imm inside {[-64:64]}; } // kept small & word aligned by encode()
  constraint c_imm_b   { (kind inside {I_BEQ, I_BNE, I_BLT, I_BGE}) -> imm inside {[-16:16]}; } // small local branches
  constraint c_imm_j   { (kind == I_JAL)  -> imm inside {[-32:32]}; }
  constraint c_imm_u   { (kind inside {I_LUI, I_AUIPC}) -> imm inside {[0:1048575]}; }
  constraint c_imm_jalr{ (kind == I_JALR) -> imm inside {[-16:16]}; }
  constraint c_no_x0_rd { (kind inside {I_ADD,I_SUB,I_AND,I_OR,I_XOR,I_SLT,I_SLL,I_SRL,I_SRA,
                                          I_ADDI,I_ANDI,I_ORI,I_XORI,I_SLTI,I_SLLI,I_SRLI,I_SRAI,
                                          I_LW,I_JAL,I_JALR,I_LUI,I_AUIPC}) -> rd != 5'd0; }

  // Encode this item to a raw 32-bit RV32I instruction word.
  function logic [31:0] encode();
    logic [31:0] w;
    logic [11:0] simm12;
    logic [6:0]  s_hi; logic [4:0] s_lo;
    logic [20:0] jimm; logic [12:0] bimm;
    unique case (kind)
      I_ADD:  w = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
      I_SUB:  w = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011};
      I_AND:  w = {7'b0000000, rs2, rs1, 3'b111, rd, 7'b0110011};
      I_OR:   w = {7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011};
      I_XOR:  w = {7'b0000000, rs2, rs1, 3'b100, rd, 7'b0110011};
      I_SLT:  w = {7'b0000000, rs2, rs1, 3'b010, rd, 7'b0110011};
      I_SLL:  w = {7'b0000000, rs2, rs1, 3'b001, rd, 7'b0110011};
      I_SRL:  w = {7'b0000000, rs2, rs1, 3'b101, rd, 7'b0110011};
      I_SRA:  w = {7'b0100000, rs2, rs1, 3'b101, rd, 7'b0110011};
      I_ADDI: begin simm12 = imm[11:0]; w = {simm12, rs1, 3'b000, rd, 7'b0010011}; end
      I_ANDI: begin simm12 = imm[11:0]; w = {simm12, rs1, 3'b111, rd, 7'b0010011}; end
      I_ORI:  begin simm12 = imm[11:0]; w = {simm12, rs1, 3'b110, rd, 7'b0010011}; end
      I_XORI: begin simm12 = imm[11:0]; w = {simm12, rs1, 3'b100, rd, 7'b0010011}; end
      I_SLTI: begin simm12 = imm[11:0]; w = {simm12, rs1, 3'b010, rd, 7'b0010011}; end
      I_SLLI: w = {7'b0000000, imm[4:0], rs1, 3'b001, rd, 7'b0010011};
      I_SRLI: w = {7'b0000000, imm[4:0], rs1, 3'b101, rd, 7'b0010011};
      I_SRAI: w = {7'b0100000, imm[4:0], rs1, 3'b101, rd, 7'b0010011};
      I_LW:   begin simm12 = imm[11:0]; w = {simm12, rs1, 3'b010, rd, 7'b0000011}; end
      I_SW: begin
        simm12 = imm[11:0]; s_hi = simm12[11:5]; s_lo = simm12[4:0];
        w = {s_hi, rs2, rs1, 3'b010, s_lo, 7'b0100011};
      end
      I_BEQ, I_BNE, I_BLT, I_BGE: begin
        bimm = imm[12:0];
        w = {bimm[12], bimm[10:5], rs2, rs1,
             (kind==I_BEQ)?3'b000:(kind==I_BNE)?3'b001:(kind==I_BLT)?3'b100:3'b101,
             bimm[4:1], bimm[11], 7'b1100011};
      end
      I_JAL: begin
        jimm = imm[20:0];
        w = {jimm[20], jimm[10:1], jimm[11], jimm[19:12], rd, 7'b1101111};
      end
      I_JALR: begin simm12 = imm[11:0]; w = {simm12, rs1, 3'b000, rd, 7'b1100111}; end
      I_LUI:   w = {imm[19:0], rd, 7'b0110111};
      I_AUIPC: w = {imm[19:0], rd, 7'b0010111};
      I_ILLEGAL: w = 32'hFFFFFFFF; // reserved/illegal opcode pattern
      default: w = 32'h00000013;
    endcase
    return w;
  endfunction

  function bit is_branch();  return kind inside {I_BEQ,I_BNE,I_BLT,I_BGE}; endfunction
  function bit is_jump();    return kind inside {I_JAL,I_JALR}; endfunction
  function bit is_load();    return kind == I_LW; endfunction
  function bit is_store();   return kind == I_SW; endfunction
endclass

// Observed retirement, produced by the monitor from the DUT retire bus.
class riscv_retire_txn extends uvm_sequence_item;
  bit [31:0] pc;
  bit [4:0]  rd;
  bit        rd_we;
  bit [31:0] rd_data;
  bit        is_branch;
  bit        branch_taken;
  bit        is_store;
  bit [31:0] mem_addr;
  bit [31:0] mem_wdata;
  bit        illegal;

  `uvm_object_utils(riscv_retire_txn)
  function new(string name = "riscv_retire_txn");
    super.new(name);
  endfunction
endclass

`endif
