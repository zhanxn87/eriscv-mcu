// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Combinational ALU for the Phase 11 RV32I core.
// The default case implements ADD so shared arithmetic paths stay compact.
module alu
  import riscv_pkg::*;
(
  input  alu_op_e     i_alu_op,
  input  logic [31:0] i_operand_a,
  input  logic [31:0] i_operand_b,
  output logic [31:0] o_result
);

  always_comb begin
    unique case (i_alu_op)
      ALU_ADD : o_result = i_operand_a + i_operand_b;
      ALU_SUB : o_result = i_operand_a - i_operand_b;
      ALU_AND : o_result = i_operand_a & i_operand_b;
      ALU_OR  : o_result = i_operand_a | i_operand_b;
      ALU_XOR : o_result = i_operand_a ^ i_operand_b;
      ALU_SLT : o_result = ($signed(i_operand_a) < $signed(i_operand_b)) ? 32'd1 : 32'd0;
      ALU_SLTU: o_result = (i_operand_a < i_operand_b) ? 32'd1 : 32'd0;
      ALU_SLL : o_result = i_operand_a << i_operand_b[4:0];
      ALU_SRL : o_result = i_operand_a >> i_operand_b[4:0];
      ALU_SRA : o_result = $signed(i_operand_a) >>> i_operand_b[4:0];
      default : o_result = i_operand_a + i_operand_b;
    endcase
  end

endmodule