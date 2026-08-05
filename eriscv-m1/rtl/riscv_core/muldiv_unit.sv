// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Area-balanced iterative RV32M multiply/divide execution unit.
// MUL processes MUL_ITER_BITS multiplier bits per cycle.  The default radix-256
// configuration therefore has four compute cycles; MUL_RESULT_REGISTER adds a
// registered result handoff cycle. DIV/REM use radix-2 iteration with
// start-time small-operand shortcuts and an isolated leading-zero alignment
// cycle; the 32-bit full-width path remains the original iteration path.
module muldiv_unit #(
  parameter int unsigned MUL_ITER_BITS = 8,
  parameter bit          MUL_RESULT_REGISTER = 1'b1
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start_i,
  input  logic [2:0]  op_i,
  input  logic [31:0] operand_a_i,
  input  logic [31:0] operand_b_i,
  output logic        busy_o,
  output logic        done_o,
  output logic [31:0] result_o
);

  localparam logic [2:0] M_MUL    = 3'd0;
  localparam logic [2:0] M_MULH   = 3'd1;
  localparam logic [2:0] M_MULHSU = 3'd2;
  localparam logic [2:0] M_MULHU  = 3'd3;
  localparam int unsigned MUL_ITER_CYCLES = 32 / MUL_ITER_BITS;
  localparam logic [5:0] MUL_ITER_LAST = 6'(MUL_ITER_CYCLES - 1);
  localparam logic [2:0] S_IDLE       = 3'd0;
  localparam logic [2:0] S_MUL        = 3'd1;
  localparam logic [2:0] S_DIV        = 3'd2;
  localparam logic [2:0] S_SPECIAL    = 3'd3;
  localparam logic [2:0] S_MUL_RESULT = 3'd4;
  localparam logic [2:0] S_DIV_PREP   = 3'd5;

  generate
    if ((MUL_ITER_BITS != 1) && (MUL_ITER_BITS != 2) &&
        (MUL_ITER_BITS != 4) && (MUL_ITER_BITS != 8) &&
        (MUL_ITER_BITS != 16) && (MUL_ITER_BITS != 32)) begin : g_invalid_mul_iter_bits
      initial $fatal(1, "MUL_ITER_BITS must be 1, 2, 4, 8, 16, or 32");
    end
  endgenerate

  logic [2:0]  state_q;
  logic [2:0]  op_q;
  logic [5:0]  count_q;

  logic [63:0] mul_acc_q;
  logic [63:0] mul_multiplicand_q;
  logic [31:0] mul_multiplier_q;
  logic        mul_negative_q;
  logic [31:0] mul_result_pending_q;

  logic [32:0] div_rem_q;
  logic [31:0] div_dividend_q;
  logic [31:0] div_divisor_q;
  logic [31:0] div_quotient_q;
  logic        div_negative_quotient_q;
  logic        div_negative_remainder_q;
  logic        div_return_remainder_q;

  logic        mul_signed_a;
  logic        mul_signed_b;
  logic        div_signed;
  logic [31:0] start_abs_a;
  logic [31:0] start_abs_b;
  logic [63:0] mul_partial;
  logic [63:0] mul_acc_next;
  logic [63:0] mul_product_next;
  logic [32:0] div_shifted_rem;
  logic        div_ge;
  logic [32:0] div_rem_next;
  logic [31:0] div_dividend_next;
  logic [31:0] div_quotient_next;
  logic [31:0] div_quotient_signed;
  logic [31:0] div_remainder_signed;
  logic [5:0]  div_lzc;

  function automatic logic [5:0] leading_zero_count(input logic [31:0] value);
    integer bit_index;
    logic   seen_one;
    begin
      leading_zero_count = 6'd32;
      seen_one = 1'b0;
      for (bit_index = 31; bit_index >= 0; bit_index = bit_index - 1) begin
        if (!seen_one && value[bit_index]) begin
          leading_zero_count = 6'(31 - bit_index);
          seen_one = 1'b1;
        end
      end
    end
  endfunction

  assign mul_signed_a = (op_i != M_MULHU);
  assign mul_signed_b = (op_i == M_MUL) || (op_i == M_MULH);
  assign div_signed = !op_i[0];
  assign start_abs_a = ((op_i[2] ? div_signed : mul_signed_a) && operand_a_i[31]) ?
                       (~operand_a_i + 32'd1) : operand_a_i;
  assign start_abs_b = ((op_i[2] ? div_signed : mul_signed_b) && operand_b_i[31]) ?
                       (~operand_b_i + 32'd1) : operand_b_i;

  assign mul_partial = mul_multiplicand_q * mul_multiplier_q[MUL_ITER_BITS-1:0];
  assign mul_acc_next = mul_acc_q + mul_partial;
  assign mul_product_next = mul_negative_q ? (~mul_acc_next + 64'd1) : mul_acc_next;

  assign div_shifted_rem = {div_rem_q[31:0], div_dividend_q[31]};
  assign div_ge = div_shifted_rem >= {1'b0, div_divisor_q};
  assign div_rem_next = div_ge ? (div_shifted_rem - {1'b0, div_divisor_q}) : div_shifted_rem;
  assign div_dividend_next = {div_dividend_q[30:0], 1'b0};
  assign div_quotient_next = {div_quotient_q[30:0], div_ge};
  assign div_quotient_signed = div_negative_quotient_q ?
                               (~div_quotient_next + 32'd1) : div_quotient_next;
  assign div_remainder_signed = div_negative_remainder_q ?
                               (~div_rem_next[31:0] + 32'd1) : div_rem_next[31:0];
  assign div_lzc = leading_zero_count(div_dividend_q);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      op_q <= M_MUL;
      count_q <= '0;
      busy_o <= 1'b0;
      done_o <= 1'b0;
      result_o <= '0;
      mul_acc_q <= '0;
      mul_multiplicand_q <= '0;
      mul_multiplier_q <= '0;
      mul_negative_q <= 1'b0;
      mul_result_pending_q <= '0;
      div_rem_q <= '0;
      div_dividend_q <= '0;
      div_divisor_q <= '0;
      div_quotient_q <= '0;
      div_negative_quotient_q <= 1'b0;
      div_negative_remainder_q <= 1'b0;
      div_return_remainder_q <= 1'b0;
    end else begin
      done_o <= 1'b0;
      if (!busy_o) begin
        if (start_i) begin
          busy_o <= 1'b1;
          op_q <= op_i;
          count_q <= '0;
          if (op_i[2]) begin
            div_return_remainder_q <= op_i[1];
            div_negative_quotient_q <= div_signed && (operand_a_i[31] ^ operand_b_i[31]);
            div_negative_remainder_q <= div_signed && operand_a_i[31];
            if (operand_b_i == 32'd0) begin
              result_o <= op_i[1] ? operand_a_i : 32'hffff_ffff;
              state_q <= S_SPECIAL;
            end else if (div_signed && operand_a_i == 32'h8000_0000 &&
                         operand_b_i == 32'hffff_ffff) begin
              result_o <= op_i[1] ? 32'd0 : 32'h8000_0000;
              state_q <= S_SPECIAL;
            end else if (start_abs_a < start_abs_b) begin
              // |a| < |b|: quotient truncates to zero and remainder is a.
              // This also handles a == 0 without entering the divider.
              result_o <= op_i[1] ? operand_a_i : 32'd0;
              state_q <= S_SPECIAL;
            end else if (start_abs_a == start_abs_b) begin
              // Equal magnitudes produce +/-1 quotient or zero remainder.
              result_o <= op_i[1] ? 32'd0 :
                          ((div_signed && (operand_a_i[31] ^ operand_b_i[31])) ?
                           32'hffff_ffff : 32'd1);
              state_q <= S_SPECIAL;
            end else begin
              div_rem_q <= '0;
              div_dividend_q <= start_abs_a;
              div_divisor_q <= start_abs_b;
              div_quotient_q <= '0;
              // Full-width magnitudes retain the prior 32-iteration route.
              // For smaller values, PREP runs the LZC/barrel-shift path only
              // between divider registers, not on the EX launch path.
              state_q <= start_abs_a[31] ? S_DIV : S_DIV_PREP;
            end
          end else begin
            mul_acc_q <= '0;
            mul_multiplicand_q <= {32'd0, start_abs_a};
            mul_multiplier_q <= start_abs_b;
            mul_negative_q <= (mul_signed_a && operand_a_i[31]) ^
                              (mul_signed_b && operand_b_i[31]);
            state_q <= S_MUL;
          end
        end
      end else begin
        unique case (state_q)
          S_MUL: begin
            mul_acc_q <= mul_acc_next;
            mul_multiplicand_q <= mul_multiplicand_q << MUL_ITER_BITS;
            mul_multiplier_q <= mul_multiplier_q >> MUL_ITER_BITS;
            if (count_q == MUL_ITER_LAST) begin
              if (MUL_RESULT_REGISTER) begin
                mul_result_pending_q <= (op_q == M_MUL) ? mul_product_next[31:0] : mul_product_next[63:32];
                state_q <= S_MUL_RESULT;
              end else begin
                result_o <= (op_q == M_MUL) ? mul_product_next[31:0] : mul_product_next[63:32];
                busy_o <= 1'b0;
                done_o <= 1'b1;
                state_q <= S_IDLE;
              end
            end else begin
              count_q <= count_q + 6'd1;
            end
          end
          S_MUL_RESULT: begin
            result_o <= mul_result_pending_q;
            busy_o <= 1'b0;
            done_o <= 1'b1;
            state_q <= S_IDLE;
          end
          S_DIV: begin
            div_rem_q <= div_rem_next;
            div_dividend_q <= div_dividend_next;
            div_quotient_q <= div_quotient_next;
            if (count_q == 6'd31) begin
              result_o <= div_return_remainder_q ? div_remainder_signed : div_quotient_signed;
              busy_o <= 1'b0;
              done_o <= 1'b1;
              state_q <= S_IDLE;
            end else begin
              count_q <= count_q + 6'd1;
            end
          end
          S_DIV_PREP: begin
            // div_dividend_q is nonzero here: zero was captured by |a| < |b|.
            // Start at its first significant bit, then preserve the original
            // terminal count (31) so radix-2 quotient/remainder semantics stay
            // identical to the full 32-bit route.
            div_dividend_q <= div_dividend_q << div_lzc;
            count_q <= div_lzc;
            state_q <= S_DIV;
          end
          default: begin
            busy_o <= 1'b0;
            done_o <= 1'b1;
            state_q <= S_IDLE;
          end
        endcase
      end
    end
  end

endmodule
