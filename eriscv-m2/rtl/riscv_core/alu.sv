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

  logic [31:0] addend_b;
  logic [31:0] add_result;

  function automatic logic [5:0] count_leading_zeros(input logic [31:0] value);
    integer bit_index;
    logic found_one;
    begin
      count_leading_zeros = 6'd32;
      found_one = 1'b0;
      for (bit_index = 31; bit_index >= 0; bit_index = bit_index - 1) begin
        if (!found_one && value[bit_index]) begin
          count_leading_zeros = 6'(31 - bit_index);
          found_one = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic [5:0] count_trailing_zeros(input logic [31:0] value);
    integer bit_index;
    logic found_one;
    begin
      count_trailing_zeros = 6'd32;
      found_one = 1'b0;
      for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
        if (!found_one && value[bit_index]) begin
          count_trailing_zeros = 6'(bit_index);
          found_one = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic [5:0] count_population(input logic [31:0] value);
    integer bit_index;
    begin
      count_population = 6'd0;
      for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
        count_population = count_population + {5'd0, value[bit_index]};
      end
    end
  endfunction

  // Zba reuses the ordinary EX add path. The constant shifts are wiring only;
  // no separate adder or additional execution stage is introduced.
  always_comb begin
    addend_b = i_operand_b;
    unique case (i_alu_op)
      ALU_SH1ADD: addend_b = i_operand_b;
      ALU_SH2ADD: addend_b = i_operand_b;
      ALU_SH3ADD: addend_b = i_operand_b;
      default: begin
      end
    endcase
  end

  assign add_result = (i_alu_op == ALU_SH1ADD) ?
                      ({i_operand_a[30:0], 1'b0} + addend_b) :
                      (i_alu_op == ALU_SH2ADD) ?
                      ({i_operand_a[29:0], 2'b00} + addend_b) :
                      (i_alu_op == ALU_SH3ADD) ?
                      ({i_operand_a[28:0], 3'b000} + addend_b) :
                      (i_operand_a + addend_b);

  always_comb begin
    unique case (i_alu_op)
      ALU_ADD :  o_result = add_result;
      ALU_SUB : o_result = i_operand_a - i_operand_b;
      ALU_AND : o_result = i_operand_a & i_operand_b;
      ALU_OR  : o_result = i_operand_a | i_operand_b;
      ALU_XOR : o_result = i_operand_a ^ i_operand_b;
      ALU_SLT : o_result = ($signed(i_operand_a) < $signed(i_operand_b)) ? 32'd1 : 32'd0;
      ALU_SLTU: o_result = (i_operand_a < i_operand_b) ? 32'd1 : 32'd0;
      ALU_SLL : o_result = i_operand_a << i_operand_b[4:0];
      ALU_SRL : o_result = i_operand_a >> i_operand_b[4:0];
      ALU_SRA : o_result = $signed(i_operand_a) >>> i_operand_b[4:0];
      ALU_ANDN: o_result = i_operand_a & ~i_operand_b;
      ALU_ORN : o_result = i_operand_a | ~i_operand_b;
      ALU_XNOR: o_result = ~(i_operand_a ^ i_operand_b);
      ALU_CLZ : o_result = {26'd0, count_leading_zeros(i_operand_a)};
      ALU_CTZ : o_result = {26'd0, count_trailing_zeros(i_operand_a)};
      ALU_CPOP: o_result = {26'd0, count_population(i_operand_a)};
      ALU_MAX : o_result = ($signed(i_operand_a) > $signed(i_operand_b)) ? i_operand_a : i_operand_b;
      ALU_MAXU: o_result = (i_operand_a > i_operand_b) ? i_operand_a : i_operand_b;
      ALU_MIN : o_result = ($signed(i_operand_a) < $signed(i_operand_b)) ? i_operand_a : i_operand_b;
      ALU_MINU: o_result = (i_operand_a < i_operand_b) ? i_operand_a : i_operand_b;
      ALU_SEXTB: o_result = {{24{i_operand_a[7]}}, i_operand_a[7:0]};
      ALU_SEXTH: o_result = {{16{i_operand_a[15]}}, i_operand_a[15:0]};
      ALU_ZEXTH: o_result = {16'd0, i_operand_a[15:0]};
      ALU_ROL : o_result = (i_operand_b[4:0] == 5'd0) ? i_operand_a :
                          ((i_operand_a << i_operand_b[4:0]) |
                           (i_operand_a >> (6'd32 - {1'b0, i_operand_b[4:0]})));
      ALU_ROR : o_result = (i_operand_b[4:0] == 5'd0) ? i_operand_a :
                          ((i_operand_a >> i_operand_b[4:0]) |
                           (i_operand_a << (6'd32 - {1'b0, i_operand_b[4:0]})));
      ALU_ORCB: o_result = {{8{|i_operand_a[31:24]}}, {8{|i_operand_a[23:16]}},
                            {8{|i_operand_a[15:8]}}, {8{|i_operand_a[7:0]}}};
      ALU_REV8: o_result = {i_operand_a[7:0], i_operand_a[15:8],
                            i_operand_a[23:16], i_operand_a[31:24]};
      ALU_BSET: o_result = i_operand_a | (32'b1 << i_operand_b[4:0]);
      ALU_BCLR: o_result = i_operand_a & ~(32'b1 << i_operand_b[4:0]);
      ALU_BINV: o_result = i_operand_a ^ (32'b1 << i_operand_b[4:0]);
      ALU_BEXT: o_result = {31'd0, i_operand_a[i_operand_b[4:0]]};
      default :  o_result = add_result;
    endcase
  end

endmodule
