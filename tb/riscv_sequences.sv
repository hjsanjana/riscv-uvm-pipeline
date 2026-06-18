//=============================================================
// riscv_sequences.sv
// Constrained-random instruction-stream sequences.
//=============================================================
`ifndef RISCV_SEQUENCES_SV
`define RISCV_SEQUENCES_SV

// Base: random program of N instructions. The last item is named
// "LAST_ITEM" so the driver knows when to stop loading and run.
class riscv_random_seq extends uvm_sequence #(riscv_instr_item);
  `uvm_object_utils(riscv_random_seq)

  rand int unsigned num_instr = 60;
  constraint c_len { num_instr inside {[20:120]}; }

  function new(string name = "riscv_random_seq");
    super.new(name);
  endfunction

  task body();
    riscv_instr_item it;
    for (int i = 0; i < num_instr; i++) begin
      it = riscv_instr_item::type_id::create($sformatf("it_%0d", i));
      start_item(it);
      if (!it.randomize()) `uvm_error("SEQ", "randomize failed")
      if (i == num_instr - 1) it.set_name("LAST_ITEM");
      finish_item(it);
    end
  endtask
endclass

// Stresses forwarding/hazard logic: every instruction depends on the
// rd of the previous one (RAW chain), interleaved with load-use hazards.
class riscv_hazard_seq extends uvm_sequence #(riscv_instr_item);
  `uvm_object_utils(riscv_hazard_seq)

  rand int unsigned num_instr = 40;
  constraint c_len { num_instr inside {[20:80]}; }

  function new(string name = "riscv_hazard_seq");
    super.new(name);
  endfunction

  task body();
    riscv_instr_item it;
    bit [4:0] prev_rd = 5'd1;
    for (int i = 0; i < num_instr; i++) begin
      it = riscv_instr_item::type_id::create($sformatf("hz_%0d", i));
      start_item(it);
      if (!it.randomize() with {
            rd  != 0;
            rs1 == prev_rd;
            kind inside {I_ADD, I_SUB, I_ADDI, I_AND, I_OR, I_LW, I_SW};
          }) `uvm_error("SEQ", "randomize failed")
      if (i == num_instr - 1) it.set_name("LAST_ITEM");
      finish_item(it);
      prev_rd = it.rd;
    end
  endtask
endclass

// Stresses branch redirection: alternating compare + branch pairs with
// random taken/not-taken outcomes (driven by surrounding ALU ops).
class riscv_branch_seq extends uvm_sequence #(riscv_instr_item);
  `uvm_object_utils(riscv_branch_seq)

  rand int unsigned num_pairs = 20;
  constraint c_len { num_pairs inside {[10:40]}; }

  function new(string name = "riscv_branch_seq");
    super.new(name);
  endfunction

  task body();
    riscv_instr_item it;
    int total = num_pairs * 2;
    int n = 0;
    for (int i = 0; i < num_pairs; i++) begin
      it = riscv_instr_item::type_id::create($sformatf("setup_%0d", i));
      start_item(it);
      if (!it.randomize() with { kind == I_ADDI; rd inside {[1:8]}; })
        `uvm_error("SEQ", "randomize failed")
      n++;
      if (n == total) it.set_name("LAST_ITEM");
      finish_item(it);

      it = riscv_instr_item::type_id::create($sformatf("br_%0d", i));
      start_item(it);
      if (!it.randomize() with {
            kind inside {I_BEQ, I_BNE, I_BLT, I_BGE};
            rs1 inside {[1:8]}; rs2 inside {[1:8]};
            imm inside {[-12:12]};
          }) `uvm_error("SEQ", "randomize failed")
      n++;
      if (n == total) it.set_name("LAST_ITEM");
      finish_item(it);
    end
  endtask
endclass

// Exercises exception/illegal-instruction handling.
class riscv_exception_seq extends uvm_sequence #(riscv_instr_item);
  `uvm_object_utils(riscv_exception_seq)

  rand int unsigned num_instr = 20;
  constraint c_len { num_instr inside {[10:30]}; }

  function new(string name = "riscv_exception_seq");
    super.new(name);
  endfunction

  task body();
    riscv_instr_item it;
    for (int i = 0; i < num_instr; i++) begin
      it = riscv_instr_item::type_id::create($sformatf("ex_%0d", i));
      start_item(it);
      if (i % 5 == 4) begin
        if (!it.randomize() with { kind == I_ILLEGAL; })
          `uvm_error("SEQ", "randomize failed")
      end else begin
        if (!it.randomize() with { kind inside {I_ADD, I_ADDI, I_SUB, I_LW, I_SW}; })
          `uvm_error("SEQ", "randomize failed")
      end
      if (i == num_instr - 1) it.set_name("LAST_ITEM");
      finish_item(it);
    end
  endtask
endclass

`endif
