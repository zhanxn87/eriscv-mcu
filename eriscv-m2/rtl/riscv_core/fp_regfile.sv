// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Architectural RV32F register file. f0 is a normal writable register.
module fp_regfile (
  // Clock
  input  logic        clk,

  // Three FPR read ports
  input  logic [4:0]  raddr_a_i,
  output logic [31:0] rdata_a_o,
  input  logic [4:0]  raddr_b_i,
  output logic [31:0] rdata_b_o,
  input  logic [4:0]  raddr_c_i,
  output logic [31:0] rdata_c_o,

  // WB FPR write port
  input  logic        we_i,
  input  logic [4:0]  waddr_i,
  input  logic [31:0] wdata_i,

  // Debug abstract FPR access
  input  logic [4:0]  dbg_raddr_i,
  output logic [31:0] dbg_rdata_o,
  input  logic        dbg_we_i,
  input  logic [4:0]  dbg_waddr_i,
  input  logic [31:0] dbg_wdata_i
);

  logic [31:0] regs [0:31];

  assign rdata_a_o    = regs[raddr_a_i];
  assign rdata_b_o    = regs[raddr_b_i];
  assign rdata_c_o    = regs[raddr_c_i];
  assign dbg_rdata_o  = regs[dbg_raddr_i];

  always_ff @(posedge clk) begin
    if (we_i) begin
      regs[waddr_i] <= wdata_i;
    end
    if (dbg_we_i) begin
      regs[dbg_waddr_i] <= dbg_wdata_i;
    end
  end

endmodule
