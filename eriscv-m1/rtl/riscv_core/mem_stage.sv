// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Memory stage for load/store formatting and MEM/WB packet assembly.
// Loads are aligned and sign/zero extended here so WB only performs register writeback.
module mem_stage #(
  parameter bit ENABLE_PMP_P = 1'b1
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // EX/MEM -> MEM/WB pipeline boundary
  input  var ex_mem_t ex_mem_i,
  input  var mem_wb_t mem_wb_fwd_i,
  input  logic        ex_mem_en_i,

  // Normal D-bus transaction (MEM <-> SoC)
  input  logic        data_req_ready_i,
  input  logic        data_resp_valid_i,
  input  logic [31:0] data_rdata_i,
  input  logic        data_err_i,
  output logic        data_req_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  output logic        data_we_o,
  output logic [3:0]  data_be_o,

  // Optional local-memory read completion (SoC -> MEM)
  input  logic        lmem_resp_valid_i,
  input  logic [31:0] lmem_rdata_i,
  input  logic        lmem_err_i,
  output logic        lmem_response_o,
  output logic        load_result_bypass_valid_o,
  output logic [4:0]  load_result_bypass_rd_addr_o,
  output logic [31:0] load_result_bypass_data_o,

  // PMP fault consumption from trap control
  input  logic        pmp_fault_consume_i,

  // Registered PMP fault packet
  output logic        pmp_data_fault_now_o,
  output logic        pmp_data_fault_pending_o,
  output logic [31:0] pmp_data_fault_pc_o,
  output logic [31:0] pmp_data_fault_cause_o,
  output logic [31:0] pmp_data_fault_value_o,

  // MEM pipeline completion
  output logic        mem_wait_o,
  output mem_wb_t     mem_wb_o
);

  // MEM/WB packet and normal D-bus outstanding-request state. MEM/WB is the
  // architectural completion boundary and advances every cycle; MEM stalls
  // keep its packet invalid until a response is available.
  mem_wb_t mem_wb_d;
  logic mem_pending_q;

  // Address-derived load/store formatting
  logic [1:0] addr_offset;
  logic [31:0] store_data;
  logic [31:0] store_wdata;
  logic [3:0] store_be;
  logic [31:0] load_data;
  logic mem_op;
  logic load_store_data_match;

  // Normal D-bus or local-memory response selection
  logic mem_response_valid;
  logic [31:0] response_rdata;
  logic response_err;

  // One-entry retention for a local-memory response while EX/MEM is frozen
  logic lmem_response_hold_q;
  logic [31:0] lmem_response_data_q;
  logic lmem_response_err_q;

  // Registered D-side PMP fault packet
  logic pmp_data_fault_now;
  logic pmp_data_fault_pending_q;
  logic [31:0] pmp_data_fault_pc_q;
  logic [31:0] pmp_data_fault_cause_q;
  logic [31:0] pmp_data_fault_value_q;

  // ---------------------------------------------------------------------------
  // Memory operation and response qualification
  // ---------------------------------------------------------------------------
  assign addr_offset = ex_mem_i.data_addr[1:0];
  assign mem_op = ex_mem_i.valid & (ex_mem_i.mem_load | ex_mem_i.mem_store);
  // A fabric target may complete an accepted store in the request cycle.
  // This remains an address-agnostic core-side handshake: a response matches
  // either an outstanding request or the request issued in this cycle.
  // A younger multi-cycle EX operation may hold EX/MEM exactly when the
  // local-memory response arrives. Retain that one response until the older
  // load packet is allowed to leave EX/MEM.
  assign lmem_response_o = ex_mem_i.lmem_load &&
                           (lmem_resp_valid_i || lmem_response_hold_q);
  assign mem_response_valid = lmem_response_o ||
                              (data_resp_valid_i & (mem_pending_q | data_req_o));
  assign response_rdata = lmem_response_o ?
                        (lmem_resp_valid_i ? lmem_rdata_i : lmem_response_data_q) :
                        data_rdata_i;
  assign response_err = lmem_response_o ?
                      (lmem_resp_valid_i ? lmem_err_i : lmem_response_err_q) :
                      data_err_i;
  // Preserve MEM/WB as the architectural completion boundary while exposing
  // a successfully completed load only to the dedicated branch/store-data
  // bypasses. Pending responses keep EX frozen through mem_wait_o.
  assign load_result_bypass_valid_o = mem_response_valid &&
                                      ex_mem_i.mem_load && !response_err;
  assign load_result_bypass_rd_addr_o = ex_mem_i.rd_addr;
  assign load_result_bypass_data_o = load_data;
  // D-side PMP fault packet handling is isolated so a no-PMP configuration
  // removes the packet state and all D-bus fault gating.
  generate
    if (ENABLE_PMP_P) begin : g_pmp_fault_packet
      // PMP was evaluated in EX with the final address. Consume its registered
      // verdict at the D-bus boundary before issuing a request.
      assign pmp_data_fault_now = mem_op && !mem_pending_q && ex_mem_i.pmp_data_fault;
      assign pmp_data_fault_now_o     = pmp_data_fault_now;
      assign pmp_data_fault_pending_o = pmp_data_fault_pending_q;
      assign pmp_data_fault_pc_o      = pmp_data_fault_pc_q;
      assign pmp_data_fault_cause_o   = pmp_data_fault_cause_q;
      assign pmp_data_fault_value_o   = pmp_data_fault_value_q;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          pmp_data_fault_pending_q <= 1'b0;
          pmp_data_fault_pc_q      <= 32'h0000_0000;
          pmp_data_fault_cause_q   <= 32'h0000_0000;
          pmp_data_fault_value_q   <= 32'h0000_0000;
        end else begin
          // The packet is consumed by EX on the following cycle, so the
          // checker never feeds trap redirect or IF control combinationally.
          if (pmp_data_fault_pending_q) begin
            if (pmp_fault_consume_i)
              pmp_data_fault_pending_q <= 1'b0;
          end else if (pmp_data_fault_now) begin
            pmp_data_fault_pending_q <= 1'b1;
            pmp_data_fault_pc_q      <= ex_mem_i.pc;
            pmp_data_fault_cause_q   <= ex_mem_i.mem_load ? 32'd5 : 32'd7;
            pmp_data_fault_value_q   <= ex_mem_i.data_addr;
          end
        end
      end
    end else begin : g_no_pmp_fault_packet
      assign pmp_data_fault_now       = 1'b0;
      assign pmp_data_fault_pending_q = 1'b0;
      assign pmp_data_fault_pc_q      = 32'h0000_0000;
      assign pmp_data_fault_cause_q   = 32'h0000_0000;
      assign pmp_data_fault_value_q   = 32'h0000_0000;
      assign pmp_data_fault_now_o     = 1'b0;
      assign pmp_data_fault_pending_o = 1'b0;
      assign pmp_data_fault_pc_o      = 32'h0000_0000;
      assign pmp_data_fault_cause_o   = 32'h0000_0000;
      assign pmp_data_fault_value_o   = 32'h0000_0000;
    end
  endgenerate

  assign mem_wait_o = mem_op && !pmp_data_fault_now && !pmp_data_fault_pending_q &&
                      !mem_response_valid;

  // ---------------------------------------------------------------------------
  // Store formatting
  // Store byte enables and write-data packing are derived from the effective
  // address so the backing SRAM model can stay word-oriented.
  // ---------------------------------------------------------------------------
  // A load-to-store-data dependency is carried through EX/MEM as metadata.
  // Select the registered load result here, one stage later, so the completed
  // response does not feed the EX operand/address/control cone.
  assign load_store_data_match = ex_mem_i.valid && ex_mem_i.mem_store &&
                                 ex_mem_i.load_store_data_bypass &&
                                 mem_wb_fwd_i.valid && mem_wb_fwd_i.rd_we &&
                                 (mem_wb_fwd_i.rd_addr != 5'd0) &&
                                 (mem_wb_fwd_i.rd_addr == ex_mem_i.store_rs2_addr);
  assign store_data = load_store_data_match ? mem_wb_fwd_i.wb_data :
                                              ex_mem_i.store_data;

  // Load extraction
  // ---------------------------------------------------------------------------
  always_comb begin
    store_wdata = store_data;
    store_be    = 4'b0000;

    unique case (ex_mem_i.mem_type)
      3'b000: begin
        store_wdata = {4{store_data[7:0]}} << (addr_offset * 8);
        store_be    = 4'b0001 << addr_offset;
      end
      3'b001: begin
        store_wdata = {2{store_data[15:0]}} << (addr_offset[1] * 16);
        store_be    = 4'b0011 << {addr_offset[1], 1'b0};
      end
      default: begin
        store_wdata = store_data;
        store_be    = 4'b1111;
      end
    endcase
  end

  always_comb begin
    unique case (ex_mem_i.mem_type)
      3'b000: begin // LB
        unique case (addr_offset)
          2'd0: load_data = {{24{response_rdata[7]}},  response_rdata[7:0]};
          2'd1: load_data = {{24{response_rdata[15]}}, response_rdata[15:8]};
          2'd2: load_data = {{24{response_rdata[23]}}, response_rdata[23:16]};
          default: load_data = {{24{response_rdata[31]}}, response_rdata[31:24]};
        endcase
      end
      3'b001: begin // LH
        if (addr_offset[1]) begin
          load_data = {{16{response_rdata[31]}}, response_rdata[31:16]};
        end else begin
          load_data = {{16{response_rdata[15]}}, response_rdata[15:0]};
        end
      end
      3'b010: begin // LW
        load_data = response_rdata;
      end
      3'b100: begin // LBU
        unique case (addr_offset)
          2'd0: load_data = {24'h000000, response_rdata[7:0]};
          2'd1: load_data = {24'h000000, response_rdata[15:8]};
          2'd2: load_data = {24'h000000, response_rdata[23:16]};
          default: load_data = {24'h000000, response_rdata[31:24]};
        endcase
      end
      3'b101: begin // LHU
        load_data = addr_offset[1] ? {16'h0000, response_rdata[31:16]} :
                                     {16'h0000, response_rdata[15:0]};
      end
      default: begin
        load_data = response_rdata;
      end
    endcase
  end


  // ---------------------------------------------------------------------------
  // D-bus interface
  // A request is issued once per EX/MEM packet and held pending until response.
  // data_req_ready_i is the bus-admission qualifier.
  // ---------------------------------------------------------------------------
  assign data_req_o   = mem_op && !ex_mem_i.lmem_load && !mem_pending_q && !pmp_data_fault_now &&
                        !pmp_data_fault_pending_q &&
                        data_req_ready_i;
  assign data_addr_o  = ex_mem_i.data_addr;
  assign data_wdata_o = store_wdata;
  assign data_we_o    = mem_op && !pmp_data_fault_now && !pmp_data_fault_pending_q &&
                        ex_mem_i.mem_store;
  assign data_be_o    = (ex_mem_i.mem_store && !pmp_data_fault_now && !pmp_data_fault_pending_q) ?
                        store_be : 4'b0000;

  // ---------------------------------------------------------------------------
  // MEM/WB packet construction
  // Preserve WB-aligned PC/instruction alongside writeback data so the SoC TB
  // can keep trace checking without adding debug ports to riscv_soc.
  always_comb begin
    mem_wb_d = '0;
    mem_wb_d.valid   = ex_mem_i.valid & !pmp_data_fault_now & !pmp_data_fault_pending_q &
                       (!mem_op | mem_response_valid);
    mem_wb_d.control_source      = ex_mem_i.control_source;
    mem_wb_d.pc      = ex_mem_i.pc;
    mem_wb_d.instr   = ex_mem_i.instr;
    mem_wb_d.control_trap_pc    = ex_mem_i.control_trap_pc;
    mem_wb_d.control_trap_cause = ex_mem_i.control_trap_cause;
    mem_wb_d.control_trap_value = ex_mem_i.control_trap_value;
    mem_wb_d.control_debug_dpc  = ex_mem_i.control_debug_dpc;
    mem_wb_d.control_debug_cause = ex_mem_i.control_debug_cause;
    mem_wb_d.wb_data = ex_mem_i.mem_load ? load_data : ex_mem_i.ex_result;
    mem_wb_d.rd_addr = ex_mem_i.rd_addr;
    mem_wb_d.rd_we   = ex_mem_i.rd_we & !response_err;
  end

  // ---------------------------------------------------------------------------
  // Sequential MEM state
  // MEM/WB advances every cycle; mem_wb_d marks incomplete operations invalid.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_pending_q <= 1'b0;
      lmem_response_hold_q <= 1'b0;
      lmem_response_data_q <= '0;
      lmem_response_err_q <= 1'b0;
      mem_wb_o <= '0;
    end else begin
      if (ex_mem_en_i) begin
        lmem_response_hold_q <= 1'b0;
      end else if (ex_mem_i.lmem_load && lmem_resp_valid_i) begin
        lmem_response_hold_q <= 1'b1;
        lmem_response_data_q <= lmem_rdata_i;
        lmem_response_err_q <= lmem_err_i;
      end

      if (data_req_o && !data_resp_valid_i) begin
        mem_pending_q <= 1'b1;
      end else if (mem_response_valid) begin
        mem_pending_q <= 1'b0;
      end

      mem_wb_o <= mem_wb_d;
    end
  end

endmodule
