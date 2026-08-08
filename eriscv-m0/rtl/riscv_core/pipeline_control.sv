// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Central pipeline enable/flush controller.
// Redirects have priority over ordinary flow so wrong-path work is discarded quickly.
module pipeline_control (
  // Pipeline activation
  input  logic        fetch_enable_i,

  // Stall sources
  input  logic        imem_wait_i,
  input  logic        dmem_wait_i,
  input  logic        load_use_stall_i,

  // Redirect sources, in frozen arbitration-priority order
  input  logic        trap_redirect_i,
  input  logic [31:0] trap_redirect_pc_i,
  input  logic        debug_redirect_i,
  input  logic [31:0] debug_redirect_pc_i,
  input  logic        fence_i_redirect_i,
  input  logic [31:0] fence_i_redirect_pc_i,
  input  logic        wfi_redirect_i,
  input  logic [31:0] wfi_redirect_pc_i,
  input  logic        branch_redirect_i,
  input  logic [31:0] branch_redirect_pc_i,

  // Pipeline stage enables
  output logic        pc_en_o,
  output logic        if_id_en_o,
  output logic        backend_advance_o,

  // Pipeline stage flushes
  output logic        if_id_flush_o,
  output logic        id_ex_flush_o,
  output logic        ex_mem_flush_o,

  // Resolved redirect to IF
  output logic        redirect_valid_o,
  output logic [31:0] redirect_pc_o
);

  // Derived stall classes. A front-end stall holds PC and IF/ID; a full stall
  // additionally holds both ID/EX and EX/MEM while MEM waits for the
  // outstanding data response.
  logic front_stall;
  logic full_stall;
  logic front_end_advance;

  // ---------------------------------------------------------------------------
  // Redirect arbitration
  // Frozen PC priority: trap > debug > FENCE.I > WFI > branch/jump.
  // Validity is intentionally independent of PC priority: every source is a
  // redirect, so a shallow OR avoids putting the common valid signal through
  // the PC-selection mux chain.
  // ---------------------------------------------------------------------------
  assign redirect_valid_o = trap_redirect_i | debug_redirect_i |
                            fence_i_redirect_i | wfi_redirect_i |
                            branch_redirect_i;

  always_comb begin
    redirect_pc_o = branch_redirect_pc_i;
    if (wfi_redirect_i) begin
      redirect_pc_o = wfi_redirect_pc_i;
    end
    if (fence_i_redirect_i) begin
      redirect_pc_o = fence_i_redirect_pc_i;
    end
    if (debug_redirect_i) begin
      redirect_pc_o = debug_redirect_pc_i;
    end
    if (trap_redirect_i) begin
      redirect_pc_o    = trap_redirect_pc_i;
    end
  end

  // ---------------------------------------------------------------------------
  // Stall classification and stage actions
  // ---------------------------------------------------------------------------
  assign front_stall = imem_wait_i | load_use_stall_i;
  assign full_stall  = dmem_wait_i;

  // IF/ID may drain while fetch_enable_i is low; only a new PC request needs
  // that run-state qualification. Keep the common boundary condition named so
  // PC and IF/ID cannot silently diverge on a future stall source.
  assign front_end_advance = ~front_stall & ~full_stall;
  assign pc_en_o     = fetch_enable_i & front_end_advance;
  assign if_id_en_o  = front_end_advance;
  assign backend_advance_o = ~full_stall;

  assign if_id_flush_o = redirect_valid_o;
  assign id_ex_flush_o = redirect_valid_o | (load_use_stall_i & ~full_stall);
  assign ex_mem_flush_o = trap_redirect_i;

endmodule
