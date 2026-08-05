// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Writeback stage adapter. It turns the MEM/WB bundle into the architectural
// retire pulse and register-file write interface.
module wb_stage (
  // MEM/WB pipeline packet
  input  var mem_wb_t mem_wb_i,

  // Architectural GPR writeback
  output logic [4:0]  rd_addr_o,
  output logic [31:0] rd_data_o,
  output logic        rd_we_o
);

  // x0 suppression applies only to the physical register-file write.
  assign rd_addr_o      = mem_wb_i.rd_addr;
  assign rd_data_o      = mem_wb_i.wb_data;
  assign rd_we_o        = mem_wb_i.valid & mem_wb_i.rd_we & (mem_wb_i.rd_addr != 5'd0);

endmodule
