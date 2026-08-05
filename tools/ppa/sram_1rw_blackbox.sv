// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// ASIC PPA abstraction for the product-local behavioral SRAM wrapper.
// A memory compiler must replace this macro for physical area and SRAM timing.
(* blackbox *)
module sram_1rw #(
  parameter int ADDR_WIDTH = 13,
  parameter int DATA_WIDTH = 32,
  parameter int BYTE_LANES = DATA_WIDTH / 8
) (
  input  logic                  clk,
  input  logic                  en_i,
  input  logic                  we_i,
  input  logic [BYTE_LANES-1:0] be_i,
  input  logic [ADDR_WIDTH-1:0] addr_i,
  input  logic [DATA_WIDTH-1:0] wdata_i,
  output logic [DATA_WIDTH-1:0] rdata_o
);
endmodule
