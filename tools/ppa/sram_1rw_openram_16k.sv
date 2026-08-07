// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// PPA-only implementation of the portable M0 16 Kiword x 32-bit SRAM.
// Four OpenRAM 16 KiB hard macros preserve the externally visible one-cycle
// read latency.  This file is not part of behavioral simulation filelists.

(* blackbox *)
module eriscv_sram_16kbyte_1rw_32x4096_8 (
  input  logic        clk0,
  input  logic        csb0,
  input  logic        web0,
  input  logic [3:0]  wmask0,
  input  logic [11:0] addr0,
  input  logic [31:0] din0,
  output logic [31:0] dout0
);
endmodule

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

  localparam int BANK_ADDR_WIDTH = 12;
  localparam int BANK_COUNT = 1 << (ADDR_WIDTH - BANK_ADDR_WIDTH);
  localparam int BANK_SEL_WIDTH = ADDR_WIDTH - BANK_ADDR_WIDTH;

  logic [BANK_SEL_WIDTH-1:0] bank_sel_q;
  logic [DATA_WIDTH-1:0] bank_rdata [0:BANK_COUNT-1];
  genvar bank_index;

  always_ff @(posedge clk) begin
    if (en_i) begin
      bank_sel_q <= addr_i[ADDR_WIDTH-1:BANK_ADDR_WIDTH];
    end
  end

  for (bank_index = 0; bank_index < BANK_COUNT; bank_index = bank_index + 1) begin : gen_openram_bank
    eriscv_sram_16kbyte_1rw_32x4096_8 sram_bank_i (
      .clk0  (clk),
      .csb0  (!(en_i && (addr_i[ADDR_WIDTH-1:BANK_ADDR_WIDTH] == bank_index))),
      .web0  (!we_i),
      .wmask0(be_i),
      .addr0 (addr_i[BANK_ADDR_WIDTH-1:0]),
      .din0  (wdata_i),
      .dout0 (bank_rdata[bank_index])
    );
  end

  assign rdata_o = bank_rdata[bank_sel_q];

endmodule
