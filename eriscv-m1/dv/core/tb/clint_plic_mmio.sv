// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Core-only CLINT plus PLIC-style external-interrupt MMIO shim.
// It keeps local interrupt state outside riscv_core so ACT tests can exercise
// machine software, timer, and external interrupt plumbing without a full SoC.
// The ACT external-signal register is not a complete PLIC implementation.
module clint_plic_mmio #(
  parameter int READ_LATENCY = 1
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [3:0]  be_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] wdata_i,
  output logic        hit_o,
  output logic        resp_valid_o,
  output logic [31:0] rdata_o,
  output logic        err_o,
  output logic [63:0] mtime_o,
  output logic [31:0] irq_o
);

  localparam logic [31:0] MSIP_ADDR          = 32'h0200_0000;
  localparam logic [31:0] MTIMECMP_LO_ADDR   = 32'h0200_4000;
  localparam logic [31:0] MTIMECMP_HI_ADDR   = 32'h0200_4004;
  localparam logic [31:0] MTIME_LO_ADDR      = 32'h0200_bff8;
  localparam logic [31:0] MTIME_HI_ADDR      = 32'h0200_bffc;
  localparam logic [31:0] ACT_EXTSIG_ADDR    = 32'h0c00_0004;
  localparam logic [31:0] ACT_EXTSIG_SET_MSK = 32'h7fff_ffff;

  logic        msip_q;
  logic [63:0] mtime_q;
  logic [63:0] mtimecmp_q;
  logic [31:0] act_irq_pending_q;
  logic [31:0] read_data_q [0:READ_LATENCY-1];
  logic [READ_LATENCY-1:0] valid_pipe_q;
  logic [31:0] read_data_d;
  logic        msip_hit;
  logic        mtimecmp_lo_hit;
  logic        mtimecmp_hi_hit;
  logic        mtime_lo_hit;
  logic        mtime_hi_hit;
  logic        act_extsig_hit;
  logic        req_hit;
  logic [63:0] mtime_n;
  logic [63:0] mtimecmp_n;
  logic [31:0] act_irq_pending_n;
  logic        msip_n;
  integer index;

  function automatic logic [31:0] apply_byte_enables(
    input logic [31:0] current_value,
    input logic [31:0] write_value,
    input logic [3:0]  byte_enables
  );
    logic [31:0] merged;
    begin
      merged = current_value;
      if (byte_enables[0]) merged[7:0]   = write_value[7:0];
      if (byte_enables[1]) merged[15:8]  = write_value[15:8];
      if (byte_enables[2]) merged[23:16] = write_value[23:16];
      if (byte_enables[3]) merged[31:24] = write_value[31:24];
      apply_byte_enables = merged;
    end
  endfunction

  assign msip_hit       = (addr_i == MSIP_ADDR);
  assign mtimecmp_lo_hit = (addr_i == MTIMECMP_LO_ADDR);
  assign mtimecmp_hi_hit = (addr_i == MTIMECMP_HI_ADDR);
  assign mtime_lo_hit   = (addr_i == MTIME_LO_ADDR);
  assign mtime_hi_hit   = (addr_i == MTIME_HI_ADDR);
  assign act_extsig_hit = (addr_i == ACT_EXTSIG_ADDR);
  assign hit_o          = msip_hit | mtimecmp_lo_hit | mtimecmp_hi_hit |
                          mtime_lo_hit | mtime_hi_hit | act_extsig_hit;
  assign req_hit        = req_i & hit_o;
  assign err_o          = 1'b0;

  always_comb begin
    unique case (1'b1)
      msip_hit:        read_data_d = {31'h0000_0000, msip_q};
      mtimecmp_lo_hit: read_data_d = mtimecmp_q[31:0];
      mtimecmp_hi_hit: read_data_d = mtimecmp_q[63:32];
      mtime_lo_hit:    read_data_d = mtime_q[31:0];
      mtime_hi_hit:    read_data_d = mtime_q[63:32];
      act_extsig_hit:  read_data_d = act_irq_pending_q;
      default:         read_data_d = 32'h0000_0000;
    endcase
  end

  always_comb begin
    mtime_n = mtime_q + 64'd1;
    mtimecmp_n = mtimecmp_q;
    act_irq_pending_n = act_irq_pending_q;
    msip_n = msip_q;

    if (req_hit && we_i) begin
      if (msip_hit) begin
        msip_n = apply_byte_enables({31'h0000_0000, msip_q}, wdata_i, be_i) != 32'h0000_0000;
      end
      if (mtimecmp_lo_hit) begin
        mtimecmp_n[31:0] = apply_byte_enables(mtimecmp_q[31:0], wdata_i, be_i);
      end
      if (mtimecmp_hi_hit) begin
        mtimecmp_n[63:32] = apply_byte_enables(mtimecmp_q[63:32], wdata_i, be_i);
      end
      if (mtime_lo_hit) begin
        mtime_n[31:0] = apply_byte_enables(mtime_q[31:0], wdata_i, be_i);
      end
      if (mtime_hi_hit) begin
        mtime_n[63:32] = apply_byte_enables(mtime_q[63:32], wdata_i, be_i);
      end
      if (act_extsig_hit) begin
        if (wdata_i[31]) begin
          act_irq_pending_n = act_irq_pending_q | (wdata_i & ACT_EXTSIG_SET_MSK);
        end else begin
          act_irq_pending_n = act_irq_pending_q & ~(wdata_i & ACT_EXTSIG_SET_MSK);
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      msip_q <= 1'b0;
      mtime_q <= 64'h0000_0000_0000_0000;
      mtimecmp_q <= 64'hffff_ffff_ffff_ffff;
      act_irq_pending_q <= 32'h0000_0000;
      valid_pipe_q <= '0;
      for (index = 0; index < READ_LATENCY; index = index + 1) begin
        read_data_q[index] <= '0;
      end
    end else begin
      msip_q <= msip_n;
      mtime_q <= mtime_n;
      mtimecmp_q <= mtimecmp_n;
      act_irq_pending_q <= act_irq_pending_n;
      valid_pipe_q[0] <= req_hit;
      read_data_q[0] <= read_data_d;
      for (index = 1; index < READ_LATENCY; index = index + 1) begin
        valid_pipe_q[index] <= valid_pipe_q[index-1];
        read_data_q[index] <= read_data_q[index-1];
      end
    end
  end

  assign resp_valid_o = valid_pipe_q[READ_LATENCY-1];
  assign rdata_o = read_data_q[READ_LATENCY-1];
  assign mtime_o = mtime_q;

  always_comb begin
    irq_o = 32'h0000_0000;
    irq_o[3] = msip_q;
    irq_o[7] = (mtime_q >= mtimecmp_q);
    irq_o[11] = act_irq_pending_q[11];
  end

endmodule
