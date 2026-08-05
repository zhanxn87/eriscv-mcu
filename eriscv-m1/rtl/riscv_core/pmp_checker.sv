// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Machine-mode PMP access checker for a parameterized eRISCV-MCU contract.
module pmp_checker #(
  parameter int PMP_ENTRIES = 16,
  parameter bit ENABLE_PMP = 1'b1,
  // Use only when the caller suppresses misaligned accesses before consuming
  // the raw PMP verdict. Naturally aligned 1/2/4-byte accesses cannot cross
  // a PMP boundary because every PMP region is at least four-byte aligned.
  parameter bit ASSUME_ALIGNED_ACCESS = 1'b0
) (
  input  logic [PMP_ENTRIES*8-1:0]  pmpcfg_i,
  input  logic [PMP_ENTRIES*32-1:0] pmpaddr_i,
  input  logic                       access_read_i,
  input  logic                       access_write_i,
  input  logic                       access_exec_i,
  input  logic                       access_user_i,
  input  logic [31:0]                access_addr_i,
  input  logic [2:0]                 access_size_i,
  output logic                       access_fault_raw_o
);

  localparam int PMP_INDEX_W = (PMP_ENTRIES > 1) ? $clog2(PMP_ENTRIES) : 1;
  localparam int PMP_TREE_LEAVES = 1 << PMP_INDEX_W;

  // Per-entry match vectors (computed in parallel)
  logic [PMP_ENTRIES-1:0] entry_any_match;
  logic [PMP_ENTRIES-1:0] entry_all_match;
  logic [PMP_ENTRIES-1:0] entry_perm_ok;

  // Balanced binary priority tree. Each node directly carries the fault
  // verdict of the lowest matching entry below it. This avoids selecting an
  // index first and then building a second dynamic entry-result mux.
  logic [PMP_TREE_LEAVES-1:0] pmp_tree_valid [0:PMP_INDEX_W];
  logic [PMP_TREE_LEAVES-1:0] pmp_tree_fault [0:PMP_INDEX_W];

  logic [34:0] first_byte;
  logic [34:0] last_byte;

  // The NAPOT mask is the trailing-one run plus the terminating zero bit.
  // XOR with the incremented encoding realizes that directly without a
  // bit-by-bit priority chain.
  function automatic logic [31:0] napot_region_mask(input logic [31:0] pmpaddr);
    napot_region_mask = pmpaddr ^ (pmpaddr + 32'd1);
  endfunction

  function automatic logic range_overlaps(
    input logic [34:0] first_byte_i,
    input logic [34:0] last_byte_i,
    input logic [34:0] lower_bound,
    input logic [34:0] upper_bound
  );
    range_overlaps = (first_byte_i < upper_bound) && (last_byte_i >= lower_bound);
  endfunction

  function automatic logic range_contains(
    input logic [34:0] first_byte_i,
    input logic [34:0] last_byte_i,
    input logic [34:0] lower_bound,
    input logic [34:0] upper_bound
  );
    range_contains = (first_byte_i >= lower_bound) && (last_byte_i < upper_bound);
  endfunction

  function automatic logic [2:0] pmp_entry_match(
    input logic [7:0]  cfg,
    input logic [31:0] entry_addr,
    input logic [31:0] prev_addr,
    input logic [34:0] first_byte_i,
    input logic [34:0] last_byte_i,
    input logic        access_user,
    input logic        access_read,
    input logic        access_write,
    input logic        access_exec
  );
    logic [31:0] napot_mask;
    logic [34:0] lower_bound;
    logic [34:0] upper_bound;
    logic        any_match;
    logic        all_match;
    logic        permission_ok;
    begin
      napot_mask  = 32'h0000_0000;
      lower_bound = 35'h0;
      upper_bound = 35'h0;

      unique case (cfg[4:3])
        2'b01: begin // TOR
          lower_bound = {1'b0, prev_addr, 2'b00};
          upper_bound = {1'b0, entry_addr, 2'b00};
        end
        2'b10: begin // NA4
          lower_bound = {1'b0, entry_addr, 2'b00};
          upper_bound = lower_bound + 35'd4;
        end
        2'b11: begin // NAPOT
          napot_mask  = napot_region_mask(entry_addr);
          lower_bound = {1'b0, (entry_addr & ~napot_mask), 2'b00};
          upper_bound = lower_bound + ({1'b0, napot_mask, 2'b00} + 35'd4);
        end
        default: begin
        end
      endcase

      if (ASSUME_ALIGNED_ACCESS) begin
        // A naturally aligned data access cannot partially overlap a region
        // whose boundaries are multiples of four bytes. Check the first byte
        // only and remove the last-byte adder/comparator cone.
        any_match = range_contains(first_byte_i, first_byte_i,
                                   lower_bound, upper_bound);
        all_match = any_match;
      end else begin
        any_match = range_overlaps(first_byte_i, last_byte_i,
                                   lower_bound, upper_bound);
        all_match = range_contains(first_byte_i, last_byte_i,
                                   lower_bound, upper_bound);
      end
      permission_ok = (!access_user && !cfg[7]) ||
                      (access_read  && cfg[0]) ||
                      (access_write && cfg[1]) ||
                      (access_exec  && cfg[2]);
      pmp_entry_match = {any_match, all_match, permission_ok};
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Parallel PMP evaluation with a balanced priority-encoder tree.
  // Every entry computes its match signals independently. A balanced
  // priority tree then finds the lowest-numbered matching entry with
  // O(log N) depth instead of the O(N) priority chain.
  // ---------------------------------------------------------------------------

  generate
    if (ENABLE_PMP) begin : g_pmp_enabled
      always_comb begin
        access_fault_raw_o = 1'b0;
        entry_any_match = '0;
        entry_all_match = '0;
        entry_perm_ok   = '0;
        for (int level = 0; level <= PMP_INDEX_W; level++) begin
          pmp_tree_valid[level] = '0;
          pmp_tree_fault[level] = '0;
        end
        first_byte      = {3'b000, access_addr_i};
        if (ASSUME_ALIGNED_ACCESS) begin
          last_byte = first_byte;
        end else begin
          last_byte = first_byte + {{32{1'b0}}, access_size_i} - 35'd1;
        end

        // Evaluate independently of access validity. Callers gate this raw
        // result at their local pipeline boundary so valid/control does not
        // become part of the NAPOT/range/priority cone.

        // --- Stage 1: compute all entries in parallel ---
        for (int index = 0; index < PMP_ENTRIES; index++) begin
          {entry_any_match[index], entry_all_match[index], entry_perm_ok[index]} =
            pmp_entry_match(pmpcfg_i[index*8 +: 8],
                            pmpaddr_i[index*32 +: 32],
                            (index == 0) ? 32'h0000_0000 : pmpaddr_i[(index-1)*32 +: 32],
                            first_byte, last_byte, access_user_i, access_read_i,
                            access_write_i, access_exec_i);
          pmp_tree_valid[0][index] = entry_any_match[index];
          pmp_tree_fault[0][index] = !entry_all_match[index] ||
                                     !entry_perm_ok[index];
        end

        // --- Stage 2: balanced lowest-index verdict tree ---
        for (int level = 0; level < PMP_INDEX_W; level++) begin
          for (int node = 0; node < (PMP_TREE_LEAVES >> (level + 1)); node++) begin
            pmp_tree_valid[level+1][node] = pmp_tree_valid[level][node*2] |
                                             pmp_tree_valid[level][node*2+1];
            pmp_tree_fault[level+1][node] = pmp_tree_valid[level][node*2] ?
                                            pmp_tree_fault[level][node*2] :
                                            pmp_tree_fault[level][node*2+1];
          end
        end

        // --- Stage 3: fault determination for the selected entry ---
        if (pmp_tree_valid[PMP_INDEX_W][0]) begin
          // Partial region overlap always faults, even when permissions match.
          access_fault_raw_o = pmp_tree_fault[PMP_INDEX_W][0];
        end else if (access_user_i) begin
          // User-mode access with no matching PMP entry → fault.
          access_fault_raw_o = 1'b1;
        end
      end
    end else begin : g_pmp_disabled
      assign access_fault_raw_o = 1'b0;
    end
  endgenerate

endmodule
