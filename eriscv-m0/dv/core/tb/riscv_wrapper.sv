// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Core-level verification wrapper — NOT the delivery SoC.
// Wraps riscv_core with instr_mem, data_mem, and clint_plic_mmio for standalone
// core verification.  Use riscv_min_soc for the product integration.
import riscv_pkg::*;

module riscv_wrapper #(
  parameter int IMEM_READ_LATENCY      = 1,
  parameter int DMEM_READ_LATENCY      = 1,
  parameter int IMEM_WORD_ADDR_WIDTH   = 13,
  parameter int DMEM_WORD_ADDR_WIDTH   = 13
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        fetch_enable_i,
  input  logic [31:0] boot_addr_i,
  input  logic        debug_halt_req_i,
  input  logic        debug_resume_req_i,
  output logic        debug_halted_o,
  output logic        debug_running_o,
  output logic [31:0] debug_pc_o,
  output logic [2:0]  debug_cause_o,
  input  logic [31:0] irq_i
);

  logic        imem_req;
  logic        imem_ready;
  logic [31:0] imem_addr;
  logic        imem_rvalid;
  logic [31:0] imem_rdata;
  logic        data_req;
  logic [31:0] data_addr;
  logic [31:0] data_wdata;
  logic        data_we;
  logic [3:0]  data_be;
  logic        data_resp_valid;
  logic [31:0] data_rdata;
  logic        data_err;
  logic        imem_data_req;
  logic        imem_data_resp_valid;
  logic [31:0] imem_data_rdata;
  logic        imem_data_err;
  logic        sram_data_resp_valid;
  logic [31:0] sram_data_rdata;
  logic        sram_data_err;
  localparam logic [31:0] CORE_IMEM_LIMIT_ADDR = 32'h0004_0000;
  logic        data_imem_hit;
  logic        data_imem_pending_q;
  logic        mmio_hit;
  logic        mmio_resp_valid;
  logic [31:0] mmio_rdata;
  logic        mmio_err;
  logic [63:0] mmio_mtime;
  logic [31:0] mmio_irq;
  logic [31:0] combined_irq;

  assign combined_irq = irq_i | mmio_irq;
  // Mirror the product map: 0x0000_0000..0x0003_ffff is executable IMEM.
  assign data_imem_hit = data_req && (data_addr < CORE_IMEM_LIMIT_ADDR);
  assign imem_data_req = data_imem_hit;
  // Keep the selected target through its registered response cycle.
  assign data_resp_valid = data_imem_pending_q ? imem_data_resp_valid :
                           (mmio_hit ? mmio_resp_valid : sram_data_resp_valid);
  assign data_rdata = data_imem_pending_q ? imem_data_rdata :
                      (mmio_hit ? mmio_rdata : sram_data_rdata);
  assign data_err = data_imem_pending_q ? imem_data_err :
                    (mmio_hit ? mmio_err : sram_data_err);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_imem_pending_q <= 1'b0;
    end else if (data_imem_hit) begin
      data_imem_pending_q <= 1'b1;
    end else if (data_imem_pending_q && imem_data_resp_valid) begin
      data_imem_pending_q <= 1'b0;
    end
  end

  riscv_core riscv_core_i (
    .clk              (clk),
    .rst_n            (rst_n),
    .fetch_enable_i   (fetch_enable_i),
    .boot_addr_i      (boot_addr_i),
    .debug_halt_req_i (debug_halt_req_i),
    .debug_resume_req_i(debug_resume_req_i),
    .debug_halted_o   (debug_halted_o),
    .debug_running_o  (debug_running_o),
    .debug_pc_o       (debug_pc_o),
    .debug_cause_o    (debug_cause_o),
    .debug_reg_req_valid_i(1'b0),
    .debug_reg_write_i     (1'b0),
    .debug_reg_addr_i      (16'h0),
    .debug_reg_wdata_i     (32'h0),
    .debug_reg_rdata_o     (),
    .debug_reg_error_o     (),
    .imem_req_o       (imem_req),
    .imem_ready_i     (imem_ready),
    .imem_addr_o      (imem_addr),
    .imem_rvalid_i    (imem_rvalid),
    .imem_rdata_i     (imem_rdata),
    .data_req_o       (data_req),
    .data_addr_o      (data_addr),
    .data_wdata_o     (data_wdata),
    .data_we_o        (data_we),
    .data_be_o        (data_be),
    .data_resp_valid_i(data_resp_valid),
    .data_rdata_i     (data_rdata),
    .data_err_i       (data_err),
    .lmem_req_o       (),
    .lmem_addr_o      (),
    .lmem_accept_i    (1'b0),
    .lmem_resp_valid_i(1'b0),
    .lmem_rdata_i     (32'h0000_0000),
    .lmem_err_i       (1'b0),
    .mtime_i          (mmio_mtime),
    .irq_i            (combined_irq),
    .wfi_wake_i       (1'b0),
    .wfi_sleep_o      ()
  );

  instr_mem #(
    .ADDR_WIDTH(IMEM_WORD_ADDR_WIDTH),
    .READ_LATENCY(IMEM_READ_LATENCY)
  ) instr_mem_i (
    .clk      (clk),
    .rst_n    (rst_n),
    .rd_req_i (imem_req),
    .ready_o  (imem_ready),
    // Memory ADDR_WIDTH is a word-index width; drop byte-lane bits [1:0].
    .addr_i   (imem_addr[IMEM_WORD_ADDR_WIDTH+1:2]),
    .rvalid_o (imem_rvalid),
    .instr_o  (imem_rdata),
    .boot_we_i         (1'b0),
    .boot_addr_i       ('0),
    .boot_wdata_i      ('0),
    .boot_be_i         (4'h0),
    .data_req_i       (imem_data_req),
    .data_we_i        (data_we),
    .data_be_i        (data_be),
    .data_addr_i      (data_addr[IMEM_WORD_ADDR_WIDTH+1:2]),
    .data_wdata_i     (data_wdata),
    .data_resp_valid_o(imem_data_resp_valid),
    .data_rdata_o     (imem_data_rdata),
    .data_err_o       (imem_data_err)
  );

  clint_plic_mmio #(
    .READ_LATENCY(DMEM_READ_LATENCY)
  ) clint_plic_mmio_i (
    .clk         (clk),
    .rst_n       (rst_n),
    .req_i       (data_req),
    .we_i        (data_we),
    .be_i        (data_be),
    .addr_i      (data_addr),
    .wdata_i     (data_wdata),
    .hit_o       (mmio_hit),
    .resp_valid_o(mmio_resp_valid),
    .rdata_o     (mmio_rdata),
    .err_o       (mmio_err),
    .mtime_o     (mmio_mtime),
    .irq_o       (mmio_irq)
  );

  data_mem #(
    .ADDR_WIDTH(DMEM_WORD_ADDR_WIDTH),
    .READ_LATENCY(DMEM_READ_LATENCY)
  ) data_mem_i (
    .clk      (clk),
    .rst_n    (rst_n),
    .req_i    (data_req && !mmio_hit && !data_imem_hit),
    .we_i     (data_we && !mmio_hit),
    .be_i     (data_be),
    // Memory ADDR_WIDTH is a word-index width; drop byte-lane bits [1:0].
    .addr_i   (data_addr[DMEM_WORD_ADDR_WIDTH+1:2]),
    .wdata_i  (data_wdata),
    .resp_valid_o(sram_data_resp_valid),
    .resp_write_o(),
    .rdata_o     (sram_data_rdata),
    .err_o       (sram_data_err)
  );

endmodule
