//=============================================================
// riscv_scoreboard.sv
// Event-driven golden reference model (simple sequential RV32I
// interpreter). It steps exactly once per genuine DUT retirement
// (the monitor already filters out pipeline bubbles), so it
// naturally tracks branches/jumps without needing to predict
// pipeline timing - it only predicts architectural results.
//=============================================================
`ifndef RISCV_SCOREBOARD_SV
`define RISCV_SCOREBOARD_SV

class riscv_scoreboard extends uvm_subscriber #(riscv_retire_txn);
  `uvm_component_utils(riscv_scoreboard)

  uvm_analysis_imp_decl(_instr) // declares uvm_analysis_imp_instr
  uvm_analysis_imp_instr #(riscv_instr_item, riscv_scoreboard) instr_imp;

  riscv_instr_item golden_imem[int];     // program order, indexed by word
  int                next_load_idx = 0;
  bit [31:0]         golden_rf[32];
  bit [31:0]         golden_dmem[int];   // sparse, default 0
  bit [31:0]         golden_pc;

  int unsigned match_cnt   = 0;
  int unsigned mismatch_cnt = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    instr_imp = new("instr_imp", this);
  endfunction

  function void write_instr(riscv_instr_item item);
    golden_imem[next_load_idx] = item;
    next_load_idx++;
  endfunction

  function automatic logic [31:0] sext(logic [31:0] v, int bits);
    logic [31:0] m;
    if (v[bits-1]) begin
      m = ~((32'b1 << bits) - 1);
      return v | m;
    end
    return v;
  endfunction

  // Compute golden expectation for the instruction at golden_pc and
  // advance golden architectural state. Returns 0 if golden_pc points
  // past the recorded program (treated as injected NOP, always matches).
  function automatic void predict(output riscv_retire_txn exp_t, output bit have_exp);
    int idx;
    riscv_instr_item it;
    bit [31:0] rs1v, rs2v, res, target, addr;
    bit        taken;

    idx = golden_pc >> 2;
    exp_t = riscv_retire_txn::type_id::create("exp_t");
    have_exp = 1;

    if (!golden_imem.exists(idx)) begin
      // padding NOP region past the recorded program
      exp_t.pc = golden_pc; exp_t.rd_we = 0; exp_t.is_branch = 0; exp_t.is_store = 0; exp_t.illegal = 0;
      golden_pc = golden_pc + 32'd4;
      return;
    end

    it = golden_imem[idx];
    rs1v = (it.rs1 == 0) ? 32'd0 : golden_rf[it.rs1];
    rs2v = (it.rs2 == 0) ? 32'd0 : golden_rf[it.rs2];
    exp_t.pc = golden_pc;
    exp_t.rd = it.rd;
    exp_t.rd_we = 0; exp_t.is_branch = 0; exp_t.is_store = 0; exp_t.illegal = 0;
    taken = 0; target = golden_pc + 32'd4;

    unique case (it.kind)
      I_ADD:  begin res = rs1v + rs2v; exp_t.rd_we=1; end
      I_SUB:  begin res = rs1v - rs2v; exp_t.rd_we=1; end
      I_AND:  begin res = rs1v & rs2v; exp_t.rd_we=1; end
      I_OR:   begin res = rs1v | rs2v; exp_t.rd_we=1; end
      I_XOR:  begin res = rs1v ^ rs2v; exp_t.rd_we=1; end
      I_SLT:  begin res = ($signed(rs1v) < $signed(rs2v)) ? 32'd1 : 32'd0; exp_t.rd_we=1; end
      I_SLL:  begin res = rs1v << rs2v[4:0]; exp_t.rd_we=1; end
      I_SRL:  begin res = rs1v >> rs2v[4:0]; exp_t.rd_we=1; end
      I_SRA:  begin res = $signed(rs1v) >>> rs2v[4:0]; exp_t.rd_we=1; end
      I_ADDI: begin res = rs1v + sext(it.imm & 32'hFFF, 12); exp_t.rd_we=1; end
      I_ANDI: begin res = rs1v & sext(it.imm & 32'hFFF, 12); exp_t.rd_we=1; end
      I_ORI:  begin res = rs1v | sext(it.imm & 32'hFFF, 12); exp_t.rd_we=1; end
      I_XORI: begin res = rs1v ^ sext(it.imm & 32'hFFF, 12); exp_t.rd_we=1; end
      I_SLTI: begin res = ($signed(rs1v) < $signed(sext(it.imm & 32'hFFF, 12))) ? 32'd1 : 32'd0; exp_t.rd_we=1; end
      I_SLLI: begin res = rs1v << it.imm[4:0]; exp_t.rd_we=1; end
      I_SRLI: begin res = rs1v >> it.imm[4:0]; exp_t.rd_we=1; end
      I_SRAI: begin res = $signed(rs1v) >>> it.imm[4:0]; exp_t.rd_we=1; end
      I_LW: begin
        addr = rs1v + sext(it.imm & 32'hFFF, 12);
        res  = golden_dmem.exists(addr>>2) ? golden_dmem[addr>>2] : 32'd0;
        exp_t.rd_we = 1;
      end
      I_SW: begin
        addr = rs1v + sext(it.imm & 32'hFFF, 12);
        exp_t.is_store = 1; exp_t.mem_addr = addr; exp_t.mem_wdata = rs2v;
        golden_dmem[addr>>2] = rs2v;
        res = 'x;
      end
      I_BEQ, I_BNE, I_BLT, I_BGE: begin
        exp_t.is_branch = 1;
        unique case (it.kind)
          I_BEQ: taken = (rs1v == rs2v);
          I_BNE: taken = (rs1v != rs2v);
          I_BLT: taken = ($signed(rs1v) <  $signed(rs2v));
          I_BGE: taken = ($signed(rs1v) >= $signed(rs2v));
        endcase
        exp_t.branch_taken = taken;
        target = taken ? (golden_pc + sext(it.imm & 32'h1FFF, 13)) : (golden_pc + 32'd4);
        res = 'x;
      end
      I_JAL: begin
        res = golden_pc + 32'd4; exp_t.rd_we = 1;
        target = golden_pc + sext(it.imm & 32'h1FFFFF, 21);
      end
      I_JALR: begin
        res = golden_pc + 32'd4; exp_t.rd_we = 1;
        target = (rs1v + sext(it.imm & 32'hFFF, 12)) & ~32'd1;
      end
      I_LUI:   begin res = {it.imm[19:0], 12'b0}; exp_t.rd_we = 1; end
      I_AUIPC: begin res = golden_pc + {it.imm[19:0], 12'b0}; exp_t.rd_we = 1; end
      I_ILLEGAL: begin exp_t.illegal = 1; res = 'x; end
      default: res = 'x;
    endcase

    exp_t.rd_data = res;
    if (exp_t.rd_we && it.rd != 5'd0) golden_rf[it.rd] = res;
    golden_pc = target;
  endfunction

  function void write(riscv_retire_txn obs);
    riscv_retire_txn exp_t;
    bit have_exp;
    bit ok = 1;

    predict(exp_t, have_exp);

    if (exp_t.pc !== obs.pc) begin
      `uvm_error("SB_PC", $sformatf("PC mismatch: exp=%0h obs=%0h", exp_t.pc, obs.pc))
      ok = 0;
    end
    if (exp_t.rd_we != obs.rd_we) begin
      `uvm_error("SB_WE", $sformatf("@pc=%0h rd_we mismatch: exp=%0b obs=%0b", obs.pc, exp_t.rd_we, obs.rd_we))
      ok = 0;
    end else if (exp_t.rd_we && (exp_t.rd === obs.rd) && (exp_t.rd_data !== obs.rd_data)) begin
      `uvm_error("SB_DATA", $sformatf("@pc=%0h rd=%0d data mismatch: exp=%0h obs=%0h", obs.pc, obs.rd, exp_t.rd_data, obs.rd_data))
      ok = 0;
    end
    if (exp_t.is_branch != obs.is_branch) begin
      `uvm_error("SB_BR", $sformatf("@pc=%0h is_branch mismatch: exp=%0b obs=%0b", obs.pc, exp_t.is_branch, obs.is_branch))
      ok = 0;
    end else if (exp_t.is_branch && (exp_t.branch_taken != obs.branch_taken)) begin
      `uvm_error("SB_BRT", $sformatf("@pc=%0h branch_taken mismatch: exp=%0b obs=%0b", obs.pc, exp_t.branch_taken, obs.branch_taken))
      ok = 0;
    end
    if (exp_t.is_store != obs.is_store) begin
      `uvm_error("SB_ST", $sformatf("@pc=%0h is_store mismatch: exp=%0b obs=%0b", obs.pc, exp_t.is_store, obs.is_store))
      ok = 0;
    end else if (exp_t.is_store && ((exp_t.mem_addr !== obs.mem_addr) || (exp_t.mem_wdata !== obs.mem_wdata))) begin
      `uvm_error("SB_STD", $sformatf("@pc=%0h store mismatch: exp_addr=%0h obs_addr=%0h exp_data=%0h obs_data=%0h",
                 obs.pc, exp_t.mem_addr, obs.mem_addr, exp_t.mem_wdata, obs.mem_wdata))
      ok = 0;
    end
    if (exp_t.illegal != obs.illegal) begin
      `uvm_error("SB_ILL", $sformatf("@pc=%0h illegal mismatch: exp=%0b obs=%0b", obs.pc, exp_t.illegal, obs.illegal))
      ok = 0;
    end

    if (ok) match_cnt++; else mismatch_cnt++;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB_SUMMARY", $sformatf("matches=%0d mismatches=%0d", match_cnt, mismatch_cnt), UVM_LOW)
    if (mismatch_cnt == 0 && match_cnt > 0)
      `uvm_info("SB_SUMMARY", "*** TEST PASSED ***", UVM_NONE)
    else
      `uvm_error("SB_SUMMARY", "*** TEST FAILED ***")
  endfunction
endclass

`endif
