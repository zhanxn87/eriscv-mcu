// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Decode stage instruction parser.
// It expands one fetched instruction into the packed ID/EX control bundle.
module decoder
  import riscv_pkg::*;
(
  // Normalized instruction and PC
  input  logic [31:0] i_inst,
  input  logic [31:0] i_pc,

  // GPR source read data
  input  logic [31:0] i_rdata_a,
  input  logic [31:0] i_rdata_b,

  // FPR source read data
  input  logic [31:0] i_fdata_a,
  input  logic [31:0] i_fdata_b,
  input  logic [31:0] i_fdata_c,
  input  logic        i_valid,
  output id_ex_t      o_id_ex
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  assign opcode = i_inst[6:0];
  assign funct3 = i_inst[14:12];
  assign funct7 = i_inst[31:25];

  always_comb begin
    o_id_ex = '0;
    o_id_ex.pc            = i_pc;
    o_id_ex.instr         = i_inst;
    o_id_ex.rs1_data      = i_rdata_a;
    o_id_ex.rs2_data      = i_rdata_b;
    o_id_ex.fp_rs1_data   = i_fdata_a;
    o_id_ex.fp_rs2_data   = i_fdata_b;
    o_id_ex.fp_rs3_data   = i_fdata_c;
    o_id_ex.fp_rs1_addr   = i_inst[19:15];
    o_id_ex.fp_rs2_addr   = i_inst[24:20];
    o_id_ex.fp_rs3_addr   = i_inst[31:27];
    o_id_ex.rs1_addr      = i_inst[19:15];
    o_id_ex.rs2_addr      = i_inst[24:20];
    o_id_ex.rd_addr       = i_inst[11:7];
    o_id_ex.csr_addr      = i_inst[31:20];
    o_id_ex.op_a_sel      = OP_A_RS1;
    o_id_ex.op_b_sel      = OP_B_RS2;
    o_id_ex.alu_op        = ALU_ADD;
    o_id_ex.wb_sel        = WB_ALU;
    o_id_ex.illegal_instr = i_valid;

    unique case (opcode)
      7'b000_1111: begin
        // FENCE is an ordering NOP. FENCE.I additionally asks the core to
        // discard any prefetched instruction and refetch after the fence.
        if (funct3 == 3'b000 || funct3 == 3'b001) begin
          o_id_ex.valid         = i_valid;
          o_id_ex.illegal_instr = 1'b0;
          o_id_ex.fence_i       = (funct3 == 3'b001);
        end
      end
      7'b011_0111: begin // LUI
        o_id_ex.valid         = i_valid;
        o_id_ex.illegal_instr = 1'b0;
        o_id_ex.imm           = {i_inst[31:12], 12'h000};
        o_id_ex.op_a_sel      = OP_A_ZERO;
        o_id_ex.op_b_sel      = OP_B_IMM;
        o_id_ex.rd_we         = 1'b1;
      end
      7'b001_0111: begin // AUIPC
        o_id_ex.valid         = i_valid;
        o_id_ex.illegal_instr = 1'b0;
        o_id_ex.imm           = {i_inst[31:12], 12'h000};
        o_id_ex.op_a_sel      = OP_A_PC;
        o_id_ex.op_b_sel      = OP_B_IMM;
        o_id_ex.rd_we         = 1'b1;
      end
      7'b001_0011: begin // OP-IMM
        o_id_ex.imm      = {{20{i_inst[31]}}, i_inst[31:20]};
        o_id_ex.op_b_sel = OP_B_IMM;
        unique case (funct3)
          3'b000: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_ADD;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b010: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SLT;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b011: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SLTU;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b100: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_XOR;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b110: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_OR;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b111: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_AND;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b001: begin
            if (funct7 == 7'b000_0000) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_SLL;
              o_id_ex.rd_we         = 1'b1;
            end else if (funct7 == 7'b011_0000) begin
              unique case (i_inst[24:20])
                5'b00000: o_id_ex.alu_op = ALU_CLZ;
                5'b00001: o_id_ex.alu_op = ALU_CTZ;
                5'b00010: o_id_ex.alu_op = ALU_CPOP;
                5'b00100: o_id_ex.alu_op = ALU_SEXTB;
                5'b00101: o_id_ex.alu_op = ALU_SEXTH;
                default:   o_id_ex.alu_op = ALU_ADD;
              endcase
              if (i_inst[24:20] == 5'b00000 || i_inst[24:20] == 5'b00001 ||
                  i_inst[24:20] == 5'b00010 || i_inst[24:20] == 5'b00100 ||
                  i_inst[24:20] == 5'b00101) begin
                o_id_ex.valid         = i_valid;
                o_id_ex.illegal_instr = 1'b0;
                o_id_ex.rd_we         = 1'b1;
              end
            end else if (funct7 == 7'b001_0100) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_BSET;
              o_id_ex.rd_we         = 1'b1;
            end else if (funct7 == 7'b010_0100) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_BCLR;
              o_id_ex.rd_we         = 1'b1;
            end else if (funct7 == 7'b011_0100) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_BINV;
              o_id_ex.rd_we         = 1'b1;
            end
          end
          3'b101: begin
            if (funct7 == 7'b000_0000) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_SRL;
              o_id_ex.rd_we         = 1'b1;
            end else if (funct7 == 7'b010_0000) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_SRA;
              o_id_ex.rd_we         = 1'b1;
            end else if (funct7 == 7'b011_0000) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_ROR;
              o_id_ex.rd_we         = 1'b1;
            end else if (funct7 == 7'b001_0100 && i_inst[24:20] == 5'b00111) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_ORCB;
              o_id_ex.rd_we         = 1'b1;
            end else if (funct7 == 7'b011_0100 && i_inst[24:20] == 5'b11000) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_REV8;
              o_id_ex.rd_we         = 1'b1;
            end else if (funct7 == 7'b010_0100) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_BEXT;
              o_id_ex.rd_we         = 1'b1;
            end
          end
          default: begin
          end
        endcase
      end
      7'b011_0011: begin // OP
        unique case ({funct7, funct3})
          {7'b000_0000, 3'b000}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_ADD;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b010_0000, 3'b000}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SUB;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b001}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SLL;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b010}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SLT;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b011}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SLTU;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b100}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_XOR;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b101}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SRL;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b010_0000, 3'b101}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SRA;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b010_0000, 3'b100}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_XNOR;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b010_0000, 3'b110}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_ORN;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b010_0000, 3'b111}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_ANDN;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b110}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_OR;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b111}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_AND;
            o_id_ex.rd_we         = 1'b1;
          end
          // Zba shifted-add instructions use the standard OP encoding.
          {7'b001_0000, 3'b010}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SH1ADD;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b001_0000, 3'b100}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SH2ADD;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b001_0000, 3'b110}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SH3ADD;
            o_id_ex.rd_we         = 1'b1;
          end
          // Zbb register forms.
          {7'b000_0101, 3'b100}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_MIN;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0101, 3'b101}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_MINU;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0101, 3'b110}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_MAX;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0101, 3'b111}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_MAXU;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0100, 3'b100}: begin
            if (i_inst[24:20] == 5'd0) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_ZEXTH;
              o_id_ex.rd_we         = 1'b1;
            end
          end
          {7'b011_0000, 3'b001}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_ROL;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b011_0000, 3'b101}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_ROR;
            o_id_ex.rd_we         = 1'b1;
          end
          // Zbs register forms; immediate forms reuse the OP-IMM cases above.
          {7'b001_0100, 3'b001}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_BSET;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b010_0100, 3'b001}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_BCLR;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b011_0100, 3'b001}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_BINV;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b010_0100, 3'b101}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_BEXT;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0001, 3'b000}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_MUL;
          end
          {7'b000_0001, 3'b001}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_MULH;
          end
          {7'b000_0001, 3'b010}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_MULHSU;
          end
          {7'b000_0001, 3'b011}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_MULHU;
          end
          {7'b000_0001, 3'b100}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_DIV;
          end
          {7'b000_0001, 3'b101}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_DIVU;
          end
          {7'b000_0001, 3'b110}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_REM;
          end
          {7'b000_0001, 3'b111}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_REMU;
          end
          default: begin
          end
        endcase
      end
      7'b000_0011: begin // LOAD
        o_id_ex.imm      = {{20{i_inst[31]}}, i_inst[31:20]};
        o_id_ex.op_a_sel = OP_A_RS1;
        o_id_ex.op_b_sel = OP_B_IMM;
        o_id_ex.alu_op   = ALU_ADD;
        o_id_ex.mem_load = 1'b1;
        o_id_ex.mem_type = funct3;
        o_id_ex.rd_we    = 1'b1;
        o_id_ex.wb_sel   = WB_MEM;
        unique case (funct3)
          3'b000, 3'b001, 3'b010, 3'b100, 3'b101: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
          end
          default: begin
          end
        endcase
      end
      7'b010_0011: begin // STORE
        o_id_ex.imm       = {{20{i_inst[31]}}, i_inst[31:25], i_inst[11:7]};
        o_id_ex.op_a_sel  = OP_A_RS1;
        o_id_ex.op_b_sel  = OP_B_IMM;
        o_id_ex.alu_op    = ALU_ADD;
        o_id_ex.mem_store = 1'b1;
        o_id_ex.mem_type  = funct3;
        unique case (funct3)
          3'b000, 3'b001, 3'b010: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
          end
          default: begin
          end
        endcase
      end
      7'b000_0111: begin // FLW
        if (funct3 == 3'b010) begin
          o_id_ex.valid         = i_valid;
          o_id_ex.illegal_instr = 1'b0;
          o_id_ex.imm           = {{20{i_inst[31]}}, i_inst[31:20]};
          o_id_ex.op_a_sel      = OP_A_RS1;
          o_id_ex.op_b_sel      = OP_B_IMM;
          o_id_ex.alu_op        = ALU_ADD;
          o_id_ex.mem_load      = 1'b1;
          o_id_ex.mem_type      = 3'b010;
          o_id_ex.fp_write      = 1'b1;
          o_id_ex.fp_access     = 1'b1;
        end
      end
      7'b010_0111: begin // FSW
        if (funct3 == 3'b010) begin
          o_id_ex.valid         = i_valid;
          o_id_ex.illegal_instr = 1'b0;
          o_id_ex.imm           = {{20{i_inst[31]}}, i_inst[31:25], i_inst[11:7]};
          o_id_ex.op_a_sel      = OP_A_RS1;
          o_id_ex.op_b_sel      = OP_B_IMM;
          o_id_ex.alu_op        = ALU_ADD;
          o_id_ex.mem_store     = 1'b1;
          o_id_ex.mem_type      = 3'b010;
          o_id_ex.fp_rs2_data   = i_fdata_b;
          o_id_ex.fp_access     = 1'b1;
        end
      end
      7'b100_0011, 7'b100_0111, 7'b100_1011, 7'b100_1111: begin // FMADD.S family
        if (i_inst[26:25] == 2'b00) begin
          o_id_ex.valid                 = i_valid;
          o_id_ex.illegal_instr         = 1'b0;
          o_id_ex.fp_op                 = 1'b1;
          o_id_ex.fp_access             = 1'b1;
          o_id_ex.fp_write              = 1'b1;
          o_id_ex.fp_rounding_mode      = funct3;
          o_id_ex.fp_rounding_dynamic   = (funct3 == 3'b111);
          o_id_ex.fp_operation          = (opcode == 7'b100_0011 || opcode == 7'b100_0111) ? FP_OP_FMADD : FP_OP_FNMSUB;
          o_id_ex.fp_operation_modifier = (opcode == 7'b100_0111 || opcode == 7'b100_1111);
        end
      end
      7'b101_0011: begin // OP-FP
        o_id_ex.fp_rounding_mode    = funct3;
        o_id_ex.fp_rounding_dynamic = (funct3 == 3'b111);
        unique case (funct7)
          7'b0000000, 7'b0000100: begin // FADD.S / FSUB.S
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1;
            o_id_ex.fp_operation = FP_OP_ADD;
            o_id_ex.fp_operation_modifier = (funct7 == 7'b0000100);
          end
          7'b0001000: begin // FMUL.S
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_MUL;
          end
          7'b0001100: begin // FDIV.S
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_DIV;
          end
          7'b0101100: begin // FSQRT.S
            if (i_inst[24:20] == 5'd0) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_SQRT;
            end
          end
          7'b0010000: begin // FSGNJ*.S
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_SGNJ;
          end
          7'b0010100: begin // FMIN/FMAX.S
            if (funct3 <= 3'b001) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_MINMAX;
              o_id_ex.fp_operation_modifier = funct3[0];
            end
          end
          7'b1010000: begin // FEQ/FLT/FLE.S
            if (funct3 == 3'b010 || funct3 == 3'b001 || funct3 == 3'b000) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.rd_we = 1'b1; o_id_ex.fp_operation = FP_OP_CMP;
              o_id_ex.fp_operation_modifier = 1'b0;
            end
          end
          7'b1110000: begin // FMV.X.W / FCLASS.S
            if (i_inst[24:20] == 5'd0 && (funct3 == 3'b000 || funct3 == 3'b001)) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.rd_we = 1'b1;
              o_id_ex.fp_operation = (funct3 == 3'b000) ? FP_OP_SGNJ : FP_OP_CLASSIFY;
              o_id_ex.fp_operation_modifier = (funct3 == 3'b000);
              if (funct3 == 3'b000) o_id_ex.fp_rs2_data = i_fdata_a;
            end
          end
          7'b1100000, 7'b1100001: begin // FCVT.W[U].S
            if (i_inst[24:20] == 5'd0 || i_inst[24:20] == 5'd1) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.rd_we = 1'b1; o_id_ex.fp_operation = FP_OP_F2I;
              o_id_ex.fp_operation_modifier = (i_inst[24:20] == 5'd1);
            end
          end
          7'b1101000: begin // FCVT.S.W[U]
            if (i_inst[24:20] == 5'd0 || i_inst[24:20] == 5'd1) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_I2F;
              o_id_ex.fp_operation_modifier = (i_inst[24:20] == 5'd1);
              o_id_ex.fp_rs1_data = i_rdata_a;
            end
          end
          7'b1111000: begin // FMV.W.X
            if (i_inst[24:20] == 5'd0 && funct3 == 3'b000) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_SGNJ;
              o_id_ex.fp_operation_modifier = 1'b1; o_id_ex.fp_rs1_data = i_rdata_a;
              o_id_ex.fp_rs2_data = i_rdata_a;
            end
          end
          default: begin end
        endcase
      end
      7'b110_0011: begin // BRANCH
        o_id_ex.imm = {{19{i_inst[31]}}, i_inst[31], i_inst[7], i_inst[30:25], i_inst[11:8], 1'b0};
        unique case (funct3)
          3'b000: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_EQ;
          end
          3'b001: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_NE;
          end
          3'b100: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_LT;
          end
          3'b101: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_GE;
          end
          3'b110: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_LTU;
          end
          3'b111: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_GEU;
          end
          default: begin
          end
        endcase
      end
      7'b110_1111: begin // JAL
        o_id_ex.valid         = i_valid;
        o_id_ex.illegal_instr = 1'b0;
        o_id_ex.imm           = {{11{i_inst[31]}}, i_inst[31], i_inst[19:12], i_inst[20], i_inst[30:21], 1'b0};
        o_id_ex.op_a_sel      = OP_A_PC;
        o_id_ex.op_b_sel      = OP_B_FOUR;
        o_id_ex.jump_op       = JUMP_JAL;
        o_id_ex.rd_we         = 1'b1;
      end
      7'b110_0111: begin // JALR
        if (funct3 == 3'b000) begin
          o_id_ex.valid         = i_valid;
          o_id_ex.illegal_instr = 1'b0;
          o_id_ex.imm           = {{20{i_inst[31]}}, i_inst[31:20]};
          o_id_ex.op_a_sel      = OP_A_PC;
          o_id_ex.op_b_sel      = OP_B_FOUR;
          o_id_ex.jump_op       = JUMP_JALR;
          o_id_ex.rd_we         = 1'b1;
        end
      end
      7'b111_0011: begin // SYSTEM — CSR, ECALL/EBREAK, MRET, DRET
        // funct3 selects the sub-opcode:
        //   000 = privileged (ECALL/EBREAK/MRET/DRET based on imm[11:0])
        //   001 = CSRRW    (CSR Read-Write)
        //   010 = CSRRS    (CSR Read & Set bits)
        //   011 = CSRRC    (CSR Read & Clear bits)
        //   101 = CSRRWI   (CSR Read-Write Immediate)
        //   110 = CSRRSI   (CSR Read & Set bits Immediate)
        //   111 = CSRRCI   (CSR Read & Clear bits Immediate)
        o_id_ex.csr_addr = i_inst[31:20];
        unique case (funct3)
          3'b000: begin
            if (i_inst[31:20] == 12'h000) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_ECALL;
            end else if (i_inst[31:20] == 12'h001) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_EBREAK;
            end else if (i_inst[31:20] == 12'h302) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_MRET;
            end else if (i_inst[31:20] == 12'h105) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_WFI;
            end else if (i_inst[31:20] == 12'h7b2) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_DRET;
            end
          end
          3'b001: begin // CSRRW
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_op        = CSR_OP_WRITE;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          3'b010: begin // CSRRS
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_op        = CSR_OP_SET;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          3'b011: begin // CSRRC
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_op        = CSR_OP_CLEAR;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          3'b101: begin // CSRRWI
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_use_imm   = 1'b1;
            o_id_ex.csr_imm       = i_inst[19:15];
            o_id_ex.csr_op        = CSR_OP_WRITE;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          3'b110: begin // CSRRSI
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_use_imm   = 1'b1;
            o_id_ex.csr_imm       = i_inst[19:15];
            o_id_ex.csr_op        = CSR_OP_SET;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          3'b111: begin // CSRRCI
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_use_imm   = 1'b1;
            o_id_ex.csr_imm       = i_inst[19:15];
            o_id_ex.csr_op        = CSR_OP_CLEAR;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          default: begin
          end
        endcase
      end
      default: begin
      end
    endcase
  end

endmodule
