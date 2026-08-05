// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Combinational branch comparator used by EX-stage control flow decisions.
module branch_unit
  import riscv_pkg::*;
(
  input  branch_op_e  i_branch_op,
  input  logic [31:0] i_operand_a,
  input  logic [31:0] i_operand_b,
  output logic        o_taken
);

  always_comb begin
    unique case (i_branch_op)
      BR_EQ:   o_taken = (i_operand_a == i_operand_b);
      BR_NE:   o_taken = (i_operand_a != i_operand_b);
      BR_LT:   o_taken = ($signed(i_operand_a) < $signed(i_operand_b));
      BR_GE:   o_taken = ($signed(i_operand_a) >= $signed(i_operand_b));
      BR_LTU:  o_taken = (i_operand_a < i_operand_b);
      BR_GEU:  o_taken = (i_operand_a >= i_operand_b);
      default: o_taken = 1'b0;
    endcase
  end

endmodule
