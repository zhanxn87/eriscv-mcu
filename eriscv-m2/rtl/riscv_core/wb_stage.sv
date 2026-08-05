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
  output logic        rd_we_o,

  // FPR writeback and FCSR retirement
  output logic        fp_we_o,
  output logic [4:0]  fp_rd_addr_o,
  output logic [31:0] fp_rd_data_o,
  output logic [4:0]  fp_fflags_o,
  output logic        fp_dirty_o,

  // Committed trap, return, or Debug control event
  output logic        control_commit_o,
  output control_source_e control_source_o,
  output logic [31:0] control_trap_pc_o,
  output logic [31:0] control_trap_cause_o,
  output logic [31:0] control_trap_value_o,
  output logic [31:0] control_debug_dpc_o,
  output logic [2:0]  control_debug_cause_o
);

  // x0 suppression applies only to the physical register-file write.
  assign rd_addr_o      = mem_wb_i.rd_addr;
  assign rd_data_o      = mem_wb_i.wb_data;
  assign rd_we_o        = mem_wb_i.valid & mem_wb_i.rd_we & (mem_wb_i.rd_addr != 5'd0);
  assign fp_we_o        = mem_wb_i.valid & mem_wb_i.fp_write;
  assign fp_rd_addr_o   = mem_wb_i.fp_rd_addr;
  assign fp_rd_data_o   = mem_wb_i.wb_data;
  assign fp_fflags_o    = mem_wb_i.fp_fflags;
  assign fp_dirty_o     = mem_wb_i.valid & mem_wb_i.fp_dirty;
  assign control_commit_o       = mem_wb_i.valid & (mem_wb_i.control_source != CONTROL_NONE);
  assign control_source_o       = mem_wb_i.control_source;
  assign control_trap_pc_o      = mem_wb_i.control_trap_pc;
  assign control_trap_cause_o   = mem_wb_i.control_trap_cause;
  assign control_trap_value_o   = mem_wb_i.control_trap_value;
  assign control_debug_dpc_o    = mem_wb_i.control_debug_dpc;
  assign control_debug_cause_o  = mem_wb_i.control_debug_cause;

endmodule
