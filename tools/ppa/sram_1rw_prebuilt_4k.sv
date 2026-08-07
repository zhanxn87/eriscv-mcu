// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// PPA-only implementation of the portable M0 16 Kiword x 32-bit SRAM.
// Each logical memory uses sixteen published Sky130 4 KiB OpenRAM macros.
// The 1RW port implements the logical interface; behavioral simulation
// continues to use rtl/soc/mem/sram_1rw.sv.

(* blackbox *)
module sky130_sram_4kbyte_1rw1r_32x1024_8 (
  input  logic        clk0,
  input  logic        csb0,
  input  logic        web0,
  input  logic [3:0]  wmask0,
  input  logic [9:0]  addr0,
  input  logic [31:0] din0,
  output logic [31:0] dout0,
  input  logic        clk1,
  input  logic        csb1,
  input  logic [9:0]  addr1,
  output logic [31:0] dout1
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

  localparam int BANK_ADDR_WIDTH = 10;
  localparam int BANK_COUNT = 1 << (ADDR_WIDTH - BANK_ADDR_WIDTH);

  logic [ADDR_WIDTH-BANK_ADDR_WIDTH-1:0] bank_sel_q;
  logic [DATA_WIDTH-1:0] bank_rdata [0:BANK_COUNT-1];
  logic tie_hi;
  logic tie_lo;
  genvar bank_index;

  // Keep unused physical read-port inputs at defined levels through a real
  // Sky130 tie cell. Direct 1'b0/1'b1 blackbox connections become unroutable
  // POWER/GROUND nets in OpenROAD.
  (* keep *) sky130_fd_sc_hd__conb_1 unused_read_port_tie_i (
    .HI (tie_hi),
    .LO (tie_lo)
  );

  always_ff @(posedge clk) begin
    if (en_i) begin
      bank_sel_q <= addr_i[ADDR_WIDTH-1:BANK_ADDR_WIDTH];
    end
  end

  for (bank_index = 0; bank_index < BANK_COUNT; bank_index = bank_index + 1) begin : gen_sram_bank
    sky130_sram_4kbyte_1rw1r_32x1024_8 sram_bank_i (
      .clk0   (clk),
      .csb0   (!(en_i && (addr_i[ADDR_WIDTH-1:BANK_ADDR_WIDTH] == bank_index))),
      .web0   (!we_i),
      .wmask0 (be_i),
      .addr0  (addr_i[BANK_ADDR_WIDTH-1:0]),
      .din0   (wdata_i),
      .dout0  (bank_rdata[bank_index]),
      // The independent read port is unused by the 1RW interface.
      .clk1   (tie_lo),
      .csb1   (tie_hi),
      .addr1  ({BANK_ADDR_WIDTH{tie_lo}}),
      .dout1  ()
    );
  end

  assign rdata_o = bank_rdata[bank_sel_q];

endmodule
