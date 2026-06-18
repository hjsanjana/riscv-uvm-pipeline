//=============================================================
// riscv_core.sv
// 5-stage scalar pipelined RV32I core (subset)
// IF -> ID -> EX -> MEM -> WB
// Features: full forwarding (EX/MEM and MEM/WB -> EX), load-use
// hazard stall, branch/jump resolved in EX with 2-cycle flush,
// retire bus for verification (golden-model scoreboard hookup).
//=============================================================
`ifndef RISCV_CORE_SV
`define RISCV_CORE_SV

package riscv_pkg_rtl;
  typedef enum logic [6:0] {
    OP_RTYPE  = 7'b0110011,
    OP_ITYPE  = 7'b0010011,
    OP_LOAD   = 7'b0000011,
    OP_STORE  = 7'b0100011,
    OP_BRANCH = 7'b1100011,
    OP_JAL    = 7'b1101111,
    OP_JALR   = 7'b1100111,
    OP_LUI    = 7'b0110111,
    OP_AUIPC  = 7'b0010111
  } opcode_e;
endpackage

module riscv_core
  import riscv_pkg_rtl::*;
#(
  parameter int XLEN = 32
)(
  input  logic            clk,
  input  logic            rst_n,

  // Instruction memory (Harvard, combinational read)
  output logic [XLEN-1:0] imem_addr,
  input  logic [XLEN-1:0] imem_rdata,

  // Data memory
  output logic [XLEN-1:0] dmem_addr,
  output logic [XLEN-1:0] dmem_wdata,
  input  logic [XLEN-1:0] dmem_rdata,
  output logic            dmem_we,
  output logic            dmem_re,
  output logic [3:0]      dmem_byte_en,

  // ---------------- Verification / retire bus ----------------
  output logic            retire_valid,
  output logic [XLEN-1:0] retire_pc,
  output logic [4:0]      retire_rd,
  output logic            retire_rd_we,
  output logic [XLEN-1:0] retire_rd_data,
  output logic            retire_is_branch,
  output logic            retire_branch_taken,
  output logic            retire_is_store,
  output logic [XLEN-1:0] retire_mem_addr,
  output logic [XLEN-1:0] retire_mem_wdata,
  output logic            retire_illegal,

  output logic            dbg_stall,
  output logic            dbg_flush,
  output logic            dbg_mispredict
);

  // ======================= IF stage =======================
  logic [XLEN-1:0] pc_f, pc_f_next;
  logic            stall_f, stall_d;
  logic            flush_d, flush_e;
  logic [XLEN-1:0] branch_target_e;
  logic            branch_taken_e;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) pc_f <= '0;
    else if (!stall_f) pc_f <= pc_f_next;
  end

  always_comb begin
    if (branch_taken_e) pc_f_next = branch_target_e;
    else                pc_f_next = pc_f + 32'd4;
  end

  assign imem_addr = pc_f;

  // IF/ID pipeline registers
  logic [XLEN-1:0] pc_d, instr_d;
  logic            valid_d;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_d    <= '0;
      instr_d <= 32'h00000013; // NOP (addi x0,x0,0)
      valid_d <= 1'b0;
    end else if (flush_d) begin
      pc_d    <= '0;
      instr_d <= 32'h00000013;
      valid_d <= 1'b0;
    end else if (!stall_d) begin
      pc_d    <= pc_f;
      instr_d <= imem_rdata;
      valid_d <= 1'b1;
    end
  end

  // ======================= ID stage =======================
  logic [6:0]  opcode_d;
  logic [4:0]  rd_d, rs1_d, rs2_d;
  logic [2:0]  funct3_d;
  logic [6:0]  funct7_d;
  logic [XLEN-1:0] imm_d;
  logic        reg_we_d, mem_we_d, mem_re_d, branch_d, jal_d, jalr_d, lui_d, auipc_d, illegal_d;
  logic [3:0]  alu_op_d;
  logic        alu_src_d; // 0=reg,1=imm

  assign opcode_d  = instr_d[6:0];
  assign rd_d      = instr_d[11:7];
  assign funct3_d  = instr_d[14:12];
  assign rs1_d     = instr_d[19:15];
  assign rs2_d     = instr_d[24:20];
  assign funct7_d  = instr_d[31:25];

  // Immediate generation
  logic [XLEN-1:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  assign imm_i = {{20{instr_d[31]}}, instr_d[31:20]};
  assign imm_s = {{20{instr_d[31]}}, instr_d[31:25], instr_d[11:7]};
  assign imm_b = {{19{instr_d[31]}}, instr_d[31], instr_d[7], instr_d[30:25], instr_d[11:8], 1'b0};
  assign imm_u = {instr_d[31:12], 12'b0};
  assign imm_j = {{11{instr_d[31]}}, instr_d[31], instr_d[19:12], instr_d[20], instr_d[30:21], 1'b0};

  always_comb begin
    reg_we_d  = 1'b0; mem_we_d = 1'b0; mem_re_d = 1'b0;
    branch_d  = 1'b0; jal_d = 1'b0; jalr_d = 1'b0; lui_d = 1'b0; auipc_d = 1'b0;
    illegal_d = 1'b0;
    alu_op_d  = 4'b0000;
    alu_src_d = 1'b0;
    imm_d     = imm_i;

    case (opcode_d)
      OP_RTYPE: begin
        reg_we_d = 1'b1; alu_src_d = 1'b0;
        unique case ({funct7_d[5], funct3_d})
          4'b0_000: alu_op_d = 4'b0000; // ADD
          4'b1_000: alu_op_d = 4'b1000; // SUB
          4'b0_111: alu_op_d = 4'b0111; // AND
          4'b0_110: alu_op_d = 4'b0110; // OR
          4'b0_100: alu_op_d = 4'b0100; // XOR
          4'b0_010: alu_op_d = 4'b0010; // SLT
          4'b0_001: alu_op_d = 4'b0001; // SLL
          4'b0_101: alu_op_d = 4'b0101; // SRL
          4'b1_101: alu_op_d = 4'b1101; // SRA
          default:  illegal_d = 1'b1;
        endcase
      end
      OP_ITYPE: begin
        reg_we_d = 1'b1; alu_src_d = 1'b1; imm_d = imm_i;
        unique case (funct3_d)
          3'b000: alu_op_d = 4'b0000; // ADDI
          3'b111: alu_op_d = 4'b0111; // ANDI
          3'b110: alu_op_d = 4'b0110; // ORI
          3'b100: alu_op_d = 4'b0100; // XORI
          3'b010: alu_op_d = 4'b0010; // SLTI
          3'b001: alu_op_d = 4'b0001; // SLLI
          3'b101: alu_op_d = funct7_d[5] ? 4'b1101 : 4'b0101; // SRAI/SRLI
          default: illegal_d = 1'b1;
        endcase
      end
      OP_LOAD: begin
        reg_we_d = 1'b1; mem_re_d = 1'b1; alu_src_d = 1'b1; imm_d = imm_i; alu_op_d = 4'b0000;
      end
      OP_STORE: begin
        mem_we_d = 1'b1; alu_src_d = 1'b1; imm_d = imm_s; alu_op_d = 4'b0000;
      end
      OP_BRANCH: begin
        branch_d = 1'b1; imm_d = imm_b; alu_src_d = 1'b0;
        unique case (funct3_d)
          3'b000: alu_op_d = 4'b1000; // BEQ -> SUB, check zero
          3'b001: alu_op_d = 4'b1000; // BNE -> SUB, check !zero
          3'b100: alu_op_d = 4'b0010; // BLT -> SLT
          3'b101: alu_op_d = 4'b0010; // BGE -> SLT
          default: illegal_d = 1'b1;
        endcase
      end
      OP_JAL: begin
        reg_we_d = 1'b1; jal_d = 1'b1; imm_d = imm_j;
      end
      OP_JALR: begin
        reg_we_d = 1'b1; jalr_d = 1'b1; alu_src_d = 1'b1; imm_d = imm_i;
      end
      OP_LUI: begin
        reg_we_d = 1'b1; lui_d = 1'b1; imm_d = imm_u;
      end
      OP_AUIPC: begin
        reg_we_d = 1'b1; auipc_d = 1'b1; imm_d = imm_u;
      end
      default: illegal_d = 1'b1;
    endcase
  end

  // Register file
  logic [XLEN-1:0] rf [0:31];
  logic [XLEN-1:0] rs1_data_d, rs2_data_d;
  logic [4:0]  wb_rd;
  logic        wb_we;
  logic [XLEN-1:0] wb_data;

  always_ff @(posedge clk) begin
    if (wb_we && wb_rd != 5'd0) rf[wb_rd] <= wb_data;
  end
  assign rs1_data_d = (rs1_d == 5'd0) ? '0 : rf[rs1_d];
  assign rs2_data_d = (rs2_d == 5'd0) ? '0 : rf[rs2_d];

  // Hazard detection: load-use
  logic [4:0] rd_e_haz;
  logic       mem_re_e_haz;
  assign stall_d = mem_re_e_haz && ((rd_e_haz == rs1_d) || (rd_e_haz == rs2_d)) && (rd_e_haz != 5'd0);
  assign stall_f = stall_d;
  assign flush_d = branch_taken_e;

  // ======================= ID/EX pipeline regs =======================
  logic [XLEN-1:0] pc_e, rs1_data_e, rs2_data_e, imm_e;
  logic [4:0]  rd_e, rs1_e, rs2_e;
  logic [3:0]  alu_op_e;
  logic        alu_src_e, reg_we_e, mem_we_e, mem_re_e, branch_e, jal_e, jalr_e, lui_e, auipc_e, illegal_e;
  logic [2:0]  funct3_e;
  logic        valid_e;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      {reg_we_e, mem_we_e, mem_re_e, branch_e, jal_e, jalr_e, lui_e, auipc_e, illegal_e} <= '0;
      pc_e <= '0; rd_e <= '0; rs1_e <= '0; rs2_e <= '0; valid_e <= 1'b0;
    end else if (flush_e || stall_d) begin
      {reg_we_e, mem_we_e, mem_re_e, branch_e, jal_e, jalr_e, lui_e, auipc_e, illegal_e} <= '0;
      rd_e <= '0; valid_e <= 1'b0;
    end else begin
      valid_e     <= valid_d;
      pc_e        <= pc_d;
      rs1_data_e  <= rs1_data_d;
      rs2_data_e  <= rs2_data_d;
      imm_e       <= imm_d;
      rd_e        <= rd_d;
      rs1_e       <= rs1_d;
      rs2_e       <= rs2_d;
      alu_op_e    <= alu_op_d;
      alu_src_e   <= alu_src_d;
      reg_we_e    <= reg_we_d;
      mem_we_e    <= mem_we_d;
      mem_re_e    <= mem_re_d;
      branch_e    <= branch_d;
      jal_e       <= jal_d;
      jalr_e      <= jalr_d;
      lui_e       <= lui_d;
      auipc_e     <= auipc_d;
      illegal_e   <= illegal_d;
      funct3_e    <= funct3_d;
    end
  end
  assign rd_e_haz     = rd_e;
  assign mem_re_e_haz = mem_re_e;

  // ======================= EX stage =======================
  logic [XLEN-1:0] fwd_a, fwd_b;
  logic [1:0] fwd_a_sel, fwd_b_sel;

  // Forwarding unit (from EX/MEM and MEM/WB)
  logic [4:0] rd_m, rd_w;
  logic       reg_we_m, reg_we_w;

  always_comb begin
    fwd_a_sel = 2'b00;
    if (reg_we_m && (rd_m != 5'd0) && (rd_m == rs1_e)) fwd_a_sel = 2'b01;
    else if (reg_we_w && (rd_w != 5'd0) && (rd_w == rs1_e)) fwd_a_sel = 2'b10;

    fwd_b_sel = 2'b00;
    if (reg_we_m && (rd_m != 5'd0) && (rd_m == rs2_e)) fwd_b_sel = 2'b01;
    else if (reg_we_w && (rd_w != 5'd0) && (rd_w == rs2_e)) fwd_b_sel = 2'b10;
  end

  logic [XLEN-1:0] alu_result_m_fwd, wb_data_fwd;
  always_comb begin
    unique case (fwd_a_sel)
      2'b01: fwd_a = alu_result_m_fwd;
      2'b10: fwd_a = wb_data_fwd;
      default: fwd_a = rs1_data_e;
    endcase
    unique case (fwd_b_sel)
      2'b01: fwd_b = alu_result_m_fwd;
      2'b10: fwd_b = wb_data_fwd;
      default: fwd_b = rs2_data_e;
    endcase
  end

  logic [XLEN-1:0] alu_in_b_e, alu_result_e;
  assign alu_in_b_e = alu_src_e ? imm_e : fwd_b;

  always_comb begin
    unique case (alu_op_e)
      4'b0000: alu_result_e = fwd_a + alu_in_b_e;
      4'b1000: alu_result_e = fwd_a - alu_in_b_e;
      4'b0111: alu_result_e = fwd_a & alu_in_b_e;
      4'b0110: alu_result_e = fwd_a | alu_in_b_e;
      4'b0100: alu_result_e = fwd_a ^ alu_in_b_e;
      4'b0010: alu_result_e = ($signed(fwd_a) < $signed(alu_in_b_e)) ? 32'd1 : 32'd0;
      4'b0001: alu_result_e = fwd_a << alu_in_b_e[4:0];
      4'b0101: alu_result_e = fwd_a >> alu_in_b_e[4:0];
      4'b1101: alu_result_e = $signed(fwd_a) >>> alu_in_b_e[4:0];
      default: alu_result_e = '0;
    endcase
  end

  logic branch_cond_e;
  always_comb begin
    unique case (funct3_e)
      3'b000:  branch_cond_e = (alu_result_e == 32'd0);              // BEQ
      3'b001:  branch_cond_e = (alu_result_e != 32'd0);              // BNE
      3'b100:  branch_cond_e = (alu_result_e == 32'd1);              // BLT
      3'b101:  branch_cond_e = (alu_result_e == 32'd0);              // BGE
      default: branch_cond_e = 1'b0;
    endcase
  end

  logic [XLEN-1:0] pc_plus4_e, alu_target_e, jalr_target_e;
  assign pc_plus4_e   = pc_e + 32'd4;
  assign alu_target_e = pc_e + imm_e;        // for branch/JAL
  assign jalr_target_e = (fwd_a + imm_e) & ~32'd1;

  assign branch_taken_e = (branch_e & branch_cond_e) | jal_e | jalr_e;
  assign branch_target_e = jalr_e ? jalr_target_e : alu_target_e;
  assign flush_e = branch_taken_e;

  logic [XLEN-1:0] ex_result_e; // value written back (alu result, or pc+4 for jal/jalr, or imm_u for lui, or pc+imm for auipc)
  always_comb begin
    if (jal_e || jalr_e)      ex_result_e = pc_plus4_e;
    else if (lui_e)           ex_result_e = imm_e;
    else if (auipc_e)         ex_result_e = pc_e + imm_e;
    else                      ex_result_e = alu_result_e;
  end

  assign dbg_stall      = stall_d;
  assign dbg_flush      = flush_d | flush_e;
  assign dbg_mispredict = branch_taken_e;

  // ======================= EX/MEM pipeline regs =======================
  logic [XLEN-1:0] pc_m, ex_result_m, store_data_m;
  logic [4:0]  rs2_m_unused;
  logic        mem_we_mreg, mem_re_mreg, illegal_m, branch_m, branch_taken_m, is_store_m;
  logic [2:0]  funct3_m;
  logic        valid_m;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_we_m <= 1'b0; mem_we_mreg <= 1'b0; mem_re_mreg <= 1'b0; rd_m <= '0;
      illegal_m <= 1'b0; branch_m <= 1'b0; branch_taken_m <= 1'b0; is_store_m <= 1'b0;
      valid_m <= 1'b0;
    end else begin
      valid_m      <= valid_e;
      pc_m         <= pc_e;
      ex_result_m  <= ex_result_e;
      store_data_m <= fwd_b;
      rd_m         <= rd_e;
      reg_we_m     <= reg_we_e;
      mem_we_mreg  <= mem_we_e;
      mem_re_mreg  <= mem_re_e;
      funct3_m     <= funct3_e;
      illegal_m    <= illegal_e;
      branch_m     <= branch_e;
      branch_taken_m <= branch_taken_e;
      is_store_m   <= mem_we_e;
    end
  end

  assign dmem_addr     = ex_result_m;
  assign dmem_wdata    = store_data_m;
  assign dmem_we       = mem_we_mreg;
  assign dmem_re       = mem_re_mreg;
  assign dmem_byte_en  = 4'b1111; // word-only subset
  assign alu_result_m_fwd = ex_result_m;

  // ======================= MEM/WB pipeline regs =======================
  logic [XLEN-1:0] pc_w, ex_result_w, mem_rdata_w, store_data_w;
  logic            mem_re_w, illegal_w, is_store_w, branch_w, branch_taken_w;
  logic [2:0]      funct3_w_unused;
  logic            valid_w;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_we_w <= 1'b0; rd_w <= '0; mem_re_w <= 1'b0;
      illegal_w <= 1'b0; is_store_w <= 1'b0; branch_w <= 1'b0; branch_taken_w <= 1'b0;
      valid_w <= 1'b0;
    end else begin
      valid_w      <= valid_m;
      pc_w         <= pc_m;
      ex_result_w  <= ex_result_m;
      mem_rdata_w  <= dmem_rdata;
      store_data_w <= store_data_m;
      rd_w         <= rd_m;
      reg_we_w     <= reg_we_m;
      mem_re_w     <= mem_re_mreg;
      illegal_w    <= illegal_m;
      is_store_w   <= is_store_m;
      branch_w     <= branch_m;
      branch_taken_w <= branch_taken_m;
    end
  end

  assign wb_data = mem_re_w ? mem_rdata_w : ex_result_w;
  assign wb_we   = reg_we_w;
  assign wb_rd   = rd_w;
  assign wb_data_fwd = wb_data;

  // ======================= Retire / verification bus =======================
  assign retire_valid        = valid_w; // 1 only for genuine fetched instructions, not pipeline bubbles
  assign retire_pc           = pc_w;
  assign retire_rd           = rd_w;
  assign retire_rd_we        = reg_we_w;
  assign retire_rd_data      = wb_data;
  assign retire_is_branch    = branch_w;
  assign retire_branch_taken = branch_taken_w;
  assign retire_is_store     = is_store_w;
  assign retire_mem_addr     = ex_result_w;
  assign retire_mem_wdata    = store_data_w;
  assign retire_illegal      = illegal_w;

endmodule

`endif
