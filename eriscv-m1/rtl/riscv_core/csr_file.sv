// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Machine/debug CSR block for the teaching core.
// M1 adds U-mode counter access and PMP state to the common CSR subset.
import riscv_pkg::*;

module csr_file #(
  parameter logic [31:0] RESET_VECTOR_ADDR_P = RESET_VECTOR_ADDR,
  parameter bit          ENABLE_PMP_P = 1'b1,
  parameter int unsigned PMP_ENTRY_COUNT_P = 16
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Executing CSR instruction transaction
  input  logic        csr_access_i,
  input  logic [1:0]  csr_op_i,
  input  logic [11:0] csr_addr_i,
  input  logic        csr_write_intent_i,
  input  logic [31:0] csr_wdata_i,
  output logic [31:0] csr_rdata_o,
  output logic        csr_illegal_access_o,

  // Trap entry and return
  input  logic        trap_enter_i,
  input  logic [31:0] trap_pc_i,
  input  logic [31:0] trap_cause_i,
  input  logic [31:0] trap_value_i,
  input  logic        trap_return_i,

  // Debug entry and run state
  input  logic        debug_enter_i,
  input  logic [31:0] debug_dpc_i,
  input  logic [2:0]  debug_cause_i,
  input  logic        debug_mode_i,

  // Retirement, time, interrupt, and HPM event observations
  input  logic        retire_i,
  input  logic [1:0]  instret_pending_i,
  input  logic [31:0] irq_i,
  input  logic [63:0] mtime_i,
  input  logic [HPM_EVENT_COUNT-1:0] hpm_event_i,

  // Debug abstract CSR transaction
  input  logic        debug_csr_req_i,
  input  logic        debug_csr_write_i,
  input  logic [11:0] debug_csr_addr_i,
  input  logic [31:0] debug_csr_wdata_i,
  output logic [31:0] debug_csr_rdata_o,
  output logic        debug_csr_error_o,

  // Trigger retirement observation and state views
  input  logic        trigger_retire_i,
  output logic [31:0] trigger_mcontrol_o,
  output logic [31:0] trigger_tdata2_o,
  output logic [31:0] trigger_icount_o,

  // Architectural trap and Debug state views
  output logic [31:0] mtvec_o,
  output logic [31:0] mepc_o,
  output logic [31:0] dpc_o,
  output logic        dcsr_step_o,
  output logic        dcsr_ebreakm_o,
  output logic [2:0]  dcsr_cause_o,

  // Interrupt arbitration result
  output logic        interrupt_ready_o,
  output logic [31:0] interrupt_cause_o,

  // PMP configuration and current privilege policy
  output logic [PMP_ENTRY_COUNT_P*8-1:0]  pmpcfg_o,
  output logic [PMP_ENTRY_COUNT_P*32-1:0] pmpaddr_o,
  output privilege_mode_e privilege_mode_o,
  output logic            mstatus_tw_o,
  output logic            mstatus_mprv_o,
  output privilege_mode_e mstatus_mpp_o
);

  localparam int HPM_EVENT_INDEX_W = (HPM_EVENT_COUNT > 1) ? $clog2(HPM_EVENT_COUNT) : 1;
  localparam logic [7:0] HPM_EVENT_COUNT_U8 = HPM_EVENT_COUNT[7:0];

  // ---------------------------------------------------------------------------
  // Architectural Machine and U-mode state
  // ---------------------------------------------------------------------------
  logic [31:0] mstatus_q;
  logic [31:0] mie_q;
  logic [31:0] mip_sw_q;
  logic [31:0] mtvec_q;
  logic [31:0] mscratch_q;
  logic [31:0] mepc_q;
  logic [31:0] mcause_q;
  logic [31:0] mtval_q;
  logic [31:0] mcountinhibit_q;
  logic [31:0] mcounteren_q;
  privilege_mode_e privilege_mode_q;

  // ---------------------------------------------------------------------------
  // Counters and HPM state
  // ---------------------------------------------------------------------------
  logic [63:0] mcycle_q;
  logic [63:0] minstret_q;
  logic [63:0] mhpmcounter3_q;
  logic [63:0] mhpmcounter4_q;
  logic [63:0] mhpmcounter5_q;
  logic [63:0] mhpmcounter6_q;
  logic [7:0]  mhpmevent3_q;
  logic [7:0]  mhpmevent4_q;
  logic [7:0]  mhpmevent5_q;
  logic [7:0]  mhpmevent6_q;

  // ---------------------------------------------------------------------------
  // Debug and trigger state
  // ---------------------------------------------------------------------------
  logic        dcsr_step_q;
  logic        dcsr_ebreakm_q;
  logic [2:0]  dcsr_cause_q;
  logic [31:0] dpc_q;
  logic [31:0] dscratch0_q;
  logic [31:0] dscratch1_q;
  logic        tselect_q;
  logic [31:0] mcontrol_q;
  logic [31:0] mcontrol_tdata2_q;
  logic [31:0] icount_q;

  // Combinational CSR views and access qualification
  logic [31:0] mip_value;
  logic [31:0] dcsr_value;
  logic [31:0] csr_wvalue;
  logic        meip_pending;
  logic        msip_pending;
  logic        mtip_pending;
  logic        csr_known;
  logic        csr_write_legal;

  // ---------------------------------------------------------------------------
  // PMP state
  // ---------------------------------------------------------------------------
  logic        csr_user_counter_access;
  logic        csr_unimplemented_user_hpm;
  logic [31:0] csr_counteren_mask;
  logic        csr_pmpcfg_access;
  logic        csr_pmpaddr_access;

  // ---------------------------------------------------------------------------
  // CSR write sanitizers and access helpers
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] sanitize_mstatus(input logic [31:0] value);
    logic [31:0] sanitized;
    begin
      sanitized = 32'h0000_0000;
      // Preserve all writable Machine-mode fields.  Extension state fields
      // (VS/FS/XS) are stored as written even though this core does not
      // implement the corresponding vector / FP / user-extension units;
      // their values have no hardware side-effects and the ACT Sm profile
      // expects them to be readable.
      sanitized[1:0]   = value[1:0];
      sanitized[3]     = value[3];       // MIE
      sanitized[6:4]   = value[6:4];     // WPRI
      sanitized[7]     = value[7];       // MPIE
      sanitized[8]     = value[8];       // SPP / reserved
      sanitized[10:9]  = value[10:9];    // VS
      if (HAS_UMODE) begin
        unique case (value[12:11])
          PRIV_U,
          PRIV_M: sanitized[12:11] = value[12:11];
          default: sanitized[12:11] = PRIV_M;
        endcase
      end else begin
        sanitized[12:11] = PRIV_M;
      end
      sanitized[14:13] = value[14:13];   // FS
      sanitized[16:15] = value[16:15];   // XS
      sanitized[22:18] = value[22:18];   // TSR,TW,TVM,MXR,SUM
      sanitized[17]    = HAS_UMODE && HAS_MPRV && value[17]; // MPRV
      // SD is a read-only summary: (FS==3) || (XS==3) || (VS==3)
      sanitized[31]    = (sanitized[14:13] == 2'b11) ||
                         (sanitized[16:15] == 2'b11) ||
                         (sanitized[10:9]  == 2'b11);
      sanitize_mstatus = sanitized;
    end
  endfunction

  function automatic logic [31:0] sanitize_mie(input logic [31:0] value);
    sanitize_mie = value & 32'h0000_0aaa;
  endfunction

  function automatic logic [31:0] sanitize_mip(input logic [31:0] value);
    sanitize_mip = value & 32'h0000_0008;
  endfunction

  function automatic logic [31:0] sanitize_mtvec(input logic [31:0] value);
    sanitize_mtvec = {value[31:2], 1'b0, (value[1:0] == 2'b01)};
  endfunction

  function automatic logic [31:0] sanitize_mepc(input logic [31:0] value);
    sanitize_mepc = value & 32'hffff_fffe;
  endfunction

  function automatic logic [7:0] sanitize_hpm_event(input logic [31:0] value);
    unique case (value[7:0])
      HPM_EVENT_NONE,
      HPM_EVENT_BRANCH_RETIRED,
      HPM_EVENT_BRANCH_TAKEN,
      HPM_EVENT_CONTROL_TRANSFER_RETIRED,
      HPM_EVENT_EXCEPTION_TAKEN,
      HPM_EVENT_INTERRUPT_TAKEN,
      HPM_EVENT_IFETCH_WAIT_CYCLES,
      HPM_EVENT_DATA_WAIT_CYCLES,
      HPM_EVENT_PIPELINE_STALL_CYCLES,
      HPM_EVENT_LOAD_USE_STALL_CYCLES,
      HPM_EVENT_WFI_CYCLES,
      HPM_EVENT_DEBUG_ENTRY,
      HPM_EVENT_IRQ_PENDING_CYCLES: sanitize_hpm_event = value[7:0];
      default: sanitize_hpm_event = HPM_EVENT_NONE;
    endcase
  endfunction

  function automatic logic [31:0] counteren_mask_for_csr(input logic [11:0] addr);
    begin
      unique case (addr)
        CSR_CYCLE,
        CSR_CYCLEH:       counteren_mask_for_csr = 32'h0000_0001;
        CSR_TIME,
        CSR_TIMEH:        counteren_mask_for_csr = 32'h0000_0002;
        CSR_INSTRET,
        CSR_INSTRETH:     counteren_mask_for_csr = 32'h0000_0004;
        CSR_HPMCOUNTER3,
        CSR_HPMCOUNTER3H: counteren_mask_for_csr = 32'h0000_0008;
        CSR_HPMCOUNTER4,
        CSR_HPMCOUNTER4H: counteren_mask_for_csr = 32'h0000_0010;
        CSR_HPMCOUNTER5,
        CSR_HPMCOUNTER5H: counteren_mask_for_csr = 32'h0000_0020;
        CSR_HPMCOUNTER6,
        CSR_HPMCOUNTER6H: counteren_mask_for_csr = 32'h0000_0040;
        default:          counteren_mask_for_csr = 32'h0000_0000;
      endcase
    end
  endfunction

  function automatic logic hpm_event_active(input logic [7:0] event_id);
    if (event_id < HPM_EVENT_COUNT_U8) begin
      hpm_event_active = hpm_event_i[event_id[HPM_EVENT_INDEX_W-1:0]];
    end else begin
      hpm_event_active = 1'b0;
    end
  endfunction

  function automatic logic [7:0] sanitize_pmpcfg(input logic [7:0] value);
    logic [7:0] sanitized;
    begin
      sanitized = value;
      // R=0/W=1 is a reserved PMP permission encoding; WARL it to W=0.
      if (!sanitized[0] && sanitized[1]) begin
        sanitized[1] = 1'b0;
      end
      sanitize_pmpcfg = sanitized;
    end
  endfunction

  // PMP address ranges are decoded once and then shared by CSR legality,
  // readback, and write handling. A compiled-out PMP leaves the complete CSR
  // range unimplemented; a reduced entry count exposes only its implemented
  // contiguous prefix.
  generate
    if (ENABLE_PMP_P) begin : g_pmp_csr_decode
      assign csr_pmpcfg_access = (csr_addr_i >= CSR_PMPCFG0) &&
                                 (csr_addr_i <=
                                  (CSR_PMPCFG0 +
                                   12'((PMP_ENTRY_COUNT_P / PMP_CFG_ENTRIES_PER_CSR) - 1)));
      assign csr_pmpaddr_access = (csr_addr_i >= CSR_PMPADDR0) &&
                                  (csr_addr_i <=
                                   (CSR_PMPADDR0 + 12'(PMP_ENTRY_COUNT_P - 1)));
    end else begin : g_no_pmp_csr_decode
      assign csr_pmpcfg_access = 1'b0;
      assign csr_pmpaddr_access = 1'b0;
    end
  endgenerate

  // --- Interrupt pending and prioritisation ---
  //
  // mip is the logical OR of hardware IRQ lines and software-writable mip bits.
  //   irq_i[11] = MEI (Machine External Interrupt, from ACT MMIO)
  //   irq_i[7]  = MTI (Machine Timer Interrupt, from ACT MMIO mtime>=mtimecmp)
  //   irq_i[3]  = MSI (Machine Software Interrupt, from ACT MMIO MSIP)
  //   mip_sw_q  = software-controlled mip (only MSIP writable via CSR)
  //
  // interrupt_ready_o = privilege-aware global enable & any pending
  //
  // Priority: MEI > MSI > MTI  (per RISC-V privileged spec)
  assign mip_value = (irq_i & 32'h0000_0888) | (mip_sw_q & 32'h0000_0008);
  assign meip_pending = mip_value[11] & mie_q[11];
  assign msip_pending = mip_value[3] & mie_q[3];
  assign mtip_pending = mip_value[7] & mie_q[7];
  assign interrupt_ready_o = ((privilege_mode_q != PRIV_M) || mstatus_q[3]) &&
                             (meip_pending | msip_pending | mtip_pending);

  always_comb begin
    if (meip_pending) begin
      interrupt_cause_o = 32'h8000_000b;  // MEI
    end else if (msip_pending) begin
      interrupt_cause_o = 32'h8000_0003;  // MSI
    end else if (mtip_pending) begin
      interrupt_cause_o = 32'h8000_0007;  // MTI
    end else begin
      interrupt_cause_o = 32'h8000_000b;  // default: MEI
    end
  end

  // ---------------------------------------------------------------------------
  // CSR instruction access legality
  // ---------------------------------------------------------------------------
  assign csr_unimplemented_user_hpm =
      ((csr_addr_i >= 12'hc07) && (csr_addr_i <= 12'hc1f)) ||
      ((csr_addr_i >= 12'hc87) && (csr_addr_i <= 12'hc9f));

  always_comb begin
    csr_known = 1'b1;
    csr_write_legal = 1'b1;
    csr_counteren_mask = counteren_mask_for_csr(csr_addr_i);
    csr_user_counter_access = HAS_UMODE && HAS_MCOUNTEREN &&
                              (privilege_mode_q == PRIV_U) &&
                              ((mcounteren_q & csr_counteren_mask) != 32'h0000_0000) &&
                              !csr_write_intent_i;
    // The product implements only HPM3..6. Keep the remaining standard user
    // counter CSR aliases readable as zero in M-mode; they are read-only.
    // U-mode remains gated by the corresponding (unimplemented) mcounteren
    // bits below.
    if (csr_unimplemented_user_hpm) begin
      csr_write_legal = !csr_write_intent_i;
    end else if (!csr_pmpcfg_access && !csr_pmpaddr_access) begin
      unique case (csr_addr_i)
        CSR_MSTATUS,
        CSR_MIE,
        CSR_MTVEC,
        CSR_MSCRATCH,
        CSR_MEPC,
        CSR_MCAUSE,
        CSR_MTVAL,
        CSR_MIP,
        CSR_MCOUNTINHIBIT,
        CSR_MCOUNTEREN,
        CSR_MCYCLE,
        CSR_MCYCLEH,
        CSR_MINSTRET,
        CSR_MINSTRETH,
        CSR_MHPMCOUNTER3,
        CSR_MHPMCOUNTER4,
        CSR_MHPMCOUNTER5,
        CSR_MHPMCOUNTER6,
        CSR_MHPMCOUNTER3H,
        CSR_MHPMCOUNTER4H,
        CSR_MHPMCOUNTER5H,
        CSR_MHPMCOUNTER6H,
        CSR_MHPMEVENT3,
        CSR_MHPMEVENT4,
        CSR_MHPMEVENT5,
        CSR_MHPMEVENT6: begin
          // Writable Machine CSRs need no additional access restriction.
        end
        CSR_MISA,
        CSR_MSTATUSH,
        CSR_CYCLE,
        CSR_CYCLEH,
        CSR_TIME,
        CSR_TIMEH,
        CSR_INSTRET,
        CSR_INSTRETH,
        CSR_HPMCOUNTER3,
        CSR_HPMCOUNTER4,
        CSR_HPMCOUNTER5,
        CSR_HPMCOUNTER6,
        CSR_HPMCOUNTER3H,
        CSR_HPMCOUNTER4H,
        CSR_HPMCOUNTER5H,
        CSR_HPMCOUNTER6H,
        CSR_MHARTID: begin
          csr_write_legal = !csr_write_intent_i;
        end
        CSR_DCSR,
        CSR_DPC,
        CSR_DSCRATCH0,
        CSR_DSCRATCH1,
        CSR_TSELECT,
        CSR_TDATA1,
        CSR_TDATA2: begin
          // Debug and trigger CSRs are writable through the instruction path.
        end
        default: begin
          csr_known = 1'b0;
          csr_write_legal = 1'b0;
        end
      endcase
    end
    if ((csr_addr_i == CSR_MCOUNTEREN) && !HAS_MCOUNTEREN) begin
      csr_known = 1'b0;
      csr_write_legal = 1'b0;
    end
  end

  assign csr_illegal_access_o = csr_access_i &&
                                (!csr_known || !csr_write_legal ||
                                 ((privilege_mode_q != PRIV_M) && !csr_user_counter_access));

  // ---------------------------------------------------------------------------
  // Architectural CSR read data and instruction write value
  // ---------------------------------------------------------------------------
  always_comb begin
    dcsr_value = 32'h0000_0000;
    dcsr_value[31:28] = 4'h4;
    dcsr_value[15]    = dcsr_ebreakm_q;
    dcsr_value[8:6]   = dcsr_cause_q;
    dcsr_value[2]     = dcsr_step_q;
    dcsr_value[1:0]   = 2'b11;
  end

  always_comb begin
    csr_rdata_o = 32'h0000_0000;
    if (csr_unimplemented_user_hpm) begin
      csr_rdata_o = 32'h0000_0000;
    end else if (csr_pmpcfg_access) begin
      for (int cfg_word = 0;
           cfg_word < (PMP_ENTRY_COUNT_P / PMP_CFG_ENTRIES_PER_CSR);
           cfg_word++) begin
        if (csr_addr_i == (CSR_PMPCFG0 + 12'(cfg_word))) begin
          csr_rdata_o[7:0]   = pmpcfg_o[cfg_word*32 +: 8];
          csr_rdata_o[15:8]  = pmpcfg_o[cfg_word*32+8 +: 8];
          csr_rdata_o[23:16] = pmpcfg_o[cfg_word*32+16 +: 8];
          csr_rdata_o[31:24] = pmpcfg_o[cfg_word*32+24 +: 8];
        end
      end
    end else if (csr_pmpaddr_access) begin
      for (int addr_index = 0; addr_index < PMP_ENTRY_COUNT_P; addr_index++) begin
        if (csr_addr_i == (CSR_PMPADDR0 + 12'(addr_index))) begin
          csr_rdata_o = pmpaddr_o[addr_index*32 +: 32];
        end
      end
    end else begin
      // Common Machine/debug CSR map. PMP CSRs are handled above.
      unique case (csr_addr_i)
      CSR_MSTATUS:      csr_rdata_o = mstatus_q;
      CSR_MISA:         csr_rdata_o = 32'h4000_1104 |
                                      (HAS_UMODE ? 32'h0010_0000 : 32'h0000_0000);
      CSR_MIE:          csr_rdata_o = mie_q;
      CSR_MTVEC:        csr_rdata_o = mtvec_q;
      CSR_MSTATUSH:     csr_rdata_o = 32'h0000_0000;
      CSR_MSCRATCH:     csr_rdata_o = mscratch_q;
      CSR_MEPC:         csr_rdata_o = mepc_q;
      CSR_MCAUSE:       csr_rdata_o = mcause_q;
      CSR_MTVAL:        csr_rdata_o = mtval_q;
      CSR_MIP:          csr_rdata_o = mip_value;
      CSR_MCOUNTINHIBIT: csr_rdata_o = mcountinhibit_q;
      CSR_MCOUNTEREN:    csr_rdata_o = HAS_MCOUNTEREN ? mcounteren_q : 32'h0000_0000;
      CSR_MHARTID:      csr_rdata_o = 32'h0000_0000;
      CSR_MCYCLE,
      CSR_CYCLE:        csr_rdata_o = mcycle_q[31:0];
      CSR_MCYCLEH,
      CSR_CYCLEH:       csr_rdata_o = mcycle_q[63:32];
      CSR_TIME:         csr_rdata_o = mtime_i[31:0];
      CSR_TIMEH:        csr_rdata_o = mtime_i[63:32];
      CSR_MINSTRET,
      CSR_INSTRET:      csr_rdata_o = minstret_q[31:0] +
                                      {{30{1'b0}}, instret_pending_i};
      CSR_MINSTRETH,
      CSR_INSTRETH:     csr_rdata_o = minstret_q[63:32] +
                                      (((minstret_q[31:0] +
                                         {{30{1'b0}}, instret_pending_i}) < minstret_q[31:0]) ?
                                       32'd1 : 32'd0);
      CSR_MHPMCOUNTER3,
      CSR_HPMCOUNTER3:  csr_rdata_o = mhpmcounter3_q[31:0];
      CSR_MHPMCOUNTER4,
      CSR_HPMCOUNTER4:  csr_rdata_o = mhpmcounter4_q[31:0];
      CSR_MHPMCOUNTER5,
      CSR_HPMCOUNTER5:  csr_rdata_o = mhpmcounter5_q[31:0];
      CSR_MHPMCOUNTER6,
      CSR_HPMCOUNTER6:  csr_rdata_o = mhpmcounter6_q[31:0];
      CSR_MHPMCOUNTER3H,
      CSR_HPMCOUNTER3H: csr_rdata_o = mhpmcounter3_q[63:32];
      CSR_MHPMCOUNTER4H,
      CSR_HPMCOUNTER4H: csr_rdata_o = mhpmcounter4_q[63:32];
      CSR_MHPMCOUNTER5H,
      CSR_HPMCOUNTER5H: csr_rdata_o = mhpmcounter5_q[63:32];
      CSR_MHPMCOUNTER6H,
      CSR_HPMCOUNTER6H: csr_rdata_o = mhpmcounter6_q[63:32];
      CSR_MHPMEVENT3:   csr_rdata_o = {24'h000000, mhpmevent3_q};
      CSR_MHPMEVENT4:   csr_rdata_o = {24'h000000, mhpmevent4_q};
      CSR_MHPMEVENT5:   csr_rdata_o = {24'h000000, mhpmevent5_q};
      CSR_MHPMEVENT6:   csr_rdata_o = {24'h000000, mhpmevent6_q};
      CSR_DCSR:         csr_rdata_o = dcsr_value;
      CSR_DPC:          csr_rdata_o = dpc_q;
      CSR_DSCRATCH0:    csr_rdata_o = dscratch0_q;
      CSR_DSCRATCH1:    csr_rdata_o = dscratch1_q;
      CSR_TSELECT:      csr_rdata_o = {31'd0, tselect_q};
      CSR_TDATA1:       csr_rdata_o = tselect_q ? icount_q : mcontrol_q;
      CSR_TDATA2:       csr_rdata_o = tselect_q ? 32'h0000_0000 : mcontrol_tdata2_q;
      default:          csr_rdata_o = 32'h0000_0000;
      endcase
    end

    unique case (csr_op_i)
      CSR_OP_WRITE: csr_wvalue = csr_wdata_i;
      CSR_OP_SET:   csr_wvalue = csr_rdata_o | csr_wdata_i;
      CSR_OP_CLEAR: csr_wvalue = csr_rdata_o & ~csr_wdata_i;
      default:      csr_wvalue = csr_rdata_o;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Debug abstract CSR access
  // ---------------------------------------------------------------------------
  always_comb begin
    debug_csr_error_o = 1'b0;
    unique case (debug_csr_addr_i)
      CSR_DCSR:      debug_csr_rdata_o = dcsr_value;
      CSR_DPC:       debug_csr_rdata_o = dpc_q;
      CSR_DSCRATCH0: debug_csr_rdata_o = dscratch0_q;
      CSR_DSCRATCH1: debug_csr_rdata_o = dscratch1_q;
      CSR_TSELECT:   debug_csr_rdata_o = {31'd0, tselect_q};
      CSR_TDATA1:    debug_csr_rdata_o = tselect_q ? icount_q : mcontrol_q;
      CSR_TDATA2:    debug_csr_rdata_o = tselect_q ? 32'h0000_0000 : mcontrol_tdata2_q;
      default: begin
        debug_csr_rdata_o = 32'h0000_0000;
        debug_csr_error_o = debug_csr_req_i;
      end
    endcase
  end

  // ---------------------------------------------------------------------------
  // Sequential CSR state
  // Priority: Debug entry, Debug abstract write, trap entry, trap return,
  // then an architecturally legal instruction CSR access.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus_q      <= 32'h0000_0000;
      privilege_mode_q <= PRIV_M;
      mie_q          <= 32'h0000_0000;
      mip_sw_q       <= 32'h0000_0000;
      mtvec_q        <= RESET_VECTOR_ADDR_P;
      mscratch_q     <= 32'h0000_0000;
      mepc_q         <= 32'h0000_0000;
      mcause_q       <= 32'h0000_0000;
      mtval_q        <= 32'h0000_0000;
      mcountinhibit_q <= 32'h0000_0000;
      mcounteren_q    <= 32'h0000_0000;
      mcycle_q       <= 64'h0000_0000_0000_0000;
      minstret_q     <= 64'h0000_0000_0000_0000;
      mhpmcounter3_q <= 64'h0000_0000_0000_0000;
      mhpmcounter4_q <= 64'h0000_0000_0000_0000;
      mhpmcounter5_q <= 64'h0000_0000_0000_0000;
      mhpmcounter6_q <= 64'h0000_0000_0000_0000;
      mhpmevent3_q    <= HPM_EVENT_IFETCH_WAIT_CYCLES;
      mhpmevent4_q    <= HPM_EVENT_DATA_WAIT_CYCLES;
      mhpmevent5_q    <= HPM_EVENT_BRANCH_TAKEN;
      mhpmevent6_q    <= HPM_EVENT_INTERRUPT_TAKEN;
      dcsr_step_q    <= 1'b0;
      dcsr_ebreakm_q <= 1'b0;
      dcsr_cause_q   <= 3'd0;
      dpc_q          <= 32'h0000_0000;
      dscratch0_q    <= 32'h0000_0000;
      dscratch1_q    <= 32'h0000_0000;
      tselect_q      <= 1'b0;
      mcontrol_q     <= 32'h2000_0000;
      mcontrol_tdata2_q <= 32'h0000_0000;
      icount_q       <= 32'h3000_0000;
    end else begin
      // Autonomous counter updates precede explicit CSR writes below, so an
      // explicit write to the same counter has architectural priority.
      if (!debug_mode_i && !mcountinhibit_q[0]) begin
        mcycle_q <= mcycle_q + 64'd1;
      end
      if (retire_i && !debug_mode_i && !mcountinhibit_q[2]) begin
        minstret_q <= minstret_q + 64'd1;
      end
      if (trigger_retire_i && !debug_mode_i && (icount_q[13:0] != 14'd0)) begin
        icount_q[13:0] <= icount_q[13:0] - 14'd1;
      end
      if (!debug_mode_i && hpm_event_active(mhpmevent3_q) && !mcountinhibit_q[3]) begin
        mhpmcounter3_q <= mhpmcounter3_q + 64'd1;
      end
      if (!debug_mode_i && hpm_event_active(mhpmevent4_q) && !mcountinhibit_q[4]) begin
        mhpmcounter4_q <= mhpmcounter4_q + 64'd1;
      end
      if (!debug_mode_i && hpm_event_active(mhpmevent5_q) && !mcountinhibit_q[5]) begin
        mhpmcounter5_q <= mhpmcounter5_q + 64'd1;
      end
      if (!debug_mode_i && hpm_event_active(mhpmevent6_q) && !mcountinhibit_q[6]) begin
        mhpmcounter6_q <= mhpmcounter6_q + 64'd1;
      end

      // State-changing inputs follow the priority documented above.
      if (debug_enter_i) begin
        dpc_q        <= sanitize_mepc(debug_dpc_i);
        dcsr_cause_q <= debug_cause_i;
      end else if (debug_csr_req_i && debug_csr_write_i && !debug_csr_error_o) begin
        unique case (debug_csr_addr_i)
          CSR_DCSR: begin
            dcsr_step_q    <= debug_csr_wdata_i[2];
            dcsr_cause_q   <= debug_csr_wdata_i[8:6];
            dcsr_ebreakm_q <= debug_csr_wdata_i[15];
          end
          CSR_DPC:       dpc_q       <= sanitize_mepc(debug_csr_wdata_i);
          CSR_DSCRATCH0: dscratch0_q <= debug_csr_wdata_i;
          CSR_DSCRATCH1: dscratch1_q <= debug_csr_wdata_i;
          CSR_TSELECT:   tselect_q <= debug_csr_wdata_i[0];
          CSR_TDATA1: begin
            if (tselect_q)
              icount_q <= {4'h3, debug_csr_wdata_i[27:0]};
            else
              mcontrol_q <= {4'h2, debug_csr_wdata_i[27:0]};
          end
          CSR_TDATA2: begin
            if (!tselect_q) mcontrol_tdata2_q <= debug_csr_wdata_i;
          end
          default: begin
          end
        endcase
      end else if (trap_enter_i) begin
        mepc_q         <= sanitize_mepc(trap_pc_i);
        mcause_q       <= trap_cause_i;
        mtval_q        <= trap_value_i;
        mstatus_q[7]   <= mstatus_q[3];
        mstatus_q[3]   <= 1'b0;
        mstatus_q[12:11] <= privilege_mode_q;
        privilege_mode_q <= PRIV_M;
      end else if (trap_return_i) begin
        mstatus_q[3]    <= mstatus_q[7];
        mstatus_q[7]    <= 1'b1;
        privilege_mode_q <= HAS_UMODE ? privilege_mode_e'(mstatus_q[12:11]) : PRIV_M;
        mstatus_q[12:11] <= HAS_UMODE ? PRIV_U : PRIV_M;
        if (mstatus_q[12:11] != PRIV_M) begin
          mstatus_q[17] <= 1'b0;
        end
      end else if (csr_access_i && !csr_illegal_access_o) begin
        if (!csr_pmpcfg_access && !csr_pmpaddr_access) begin
          unique case (csr_addr_i)
          CSR_MSTATUS:      mstatus_q      <= sanitize_mstatus(csr_wvalue);
          CSR_MIE:          mie_q          <= sanitize_mie(csr_wvalue);
          CSR_MTVEC:        mtvec_q        <= sanitize_mtvec(csr_wvalue);
          CSR_MSCRATCH:     mscratch_q     <= csr_wvalue;
          CSR_MEPC:         mepc_q         <= sanitize_mepc(csr_wvalue);
          CSR_MCAUSE:       mcause_q       <= csr_wvalue;
          CSR_MTVAL:        mtval_q        <= csr_wvalue;
          CSR_MIP:          mip_sw_q       <= sanitize_mip(csr_wvalue);
          CSR_MCOUNTINHIBIT: mcountinhibit_q <= csr_wvalue & 32'h0000_007d;
          CSR_MCOUNTEREN:    mcounteren_q <= HAS_MCOUNTEREN ?
                                               (csr_wvalue & MCOUNTEREN_WRITABLE_MASK) :
                                               32'h0000_0000;
          CSR_MCYCLE:        mcycle_q[31:0] <= csr_wvalue;
          CSR_MCYCLEH:       mcycle_q[63:32] <= csr_wvalue;
          CSR_MINSTRET:      minstret_q[31:0] <= csr_wvalue;
          CSR_MINSTRETH:     minstret_q[63:32] <= csr_wvalue;
          CSR_MHPMCOUNTER3:  mhpmcounter3_q[31:0] <= csr_wvalue;
          CSR_MHPMCOUNTER4:  mhpmcounter4_q[31:0] <= csr_wvalue;
          CSR_MHPMCOUNTER5:  mhpmcounter5_q[31:0] <= csr_wvalue;
          CSR_MHPMCOUNTER6:  mhpmcounter6_q[31:0] <= csr_wvalue;
          CSR_MHPMCOUNTER3H: mhpmcounter3_q[63:32] <= csr_wvalue;
          CSR_MHPMCOUNTER4H: mhpmcounter4_q[63:32] <= csr_wvalue;
          CSR_MHPMCOUNTER5H: mhpmcounter5_q[63:32] <= csr_wvalue;
          CSR_MHPMCOUNTER6H: mhpmcounter6_q[63:32] <= csr_wvalue;
          CSR_MHPMEVENT3:    mhpmevent3_q <= sanitize_hpm_event(csr_wvalue);
          CSR_MHPMEVENT4:    mhpmevent4_q <= sanitize_hpm_event(csr_wvalue);
          CSR_MHPMEVENT5:    mhpmevent5_q <= sanitize_hpm_event(csr_wvalue);
          CSR_MHPMEVENT6:    mhpmevent6_q <= sanitize_hpm_event(csr_wvalue);
          CSR_DCSR: begin
            dcsr_step_q    <= csr_wvalue[2];
            dcsr_cause_q   <= csr_wvalue[8:6];
            dcsr_ebreakm_q <= csr_wvalue[15];
          end
          CSR_DPC:       dpc_q       <= sanitize_mepc(csr_wvalue);
          CSR_DSCRATCH0: dscratch0_q <= csr_wvalue;
          CSR_DSCRATCH1: dscratch1_q <= csr_wvalue;
          CSR_TSELECT:   tselect_q <= csr_wvalue[0];
          CSR_TDATA1: begin
            if (tselect_q)
              icount_q <= {4'h3, csr_wvalue[27:0]};
            else
              mcontrol_q <= {4'h2, csr_wvalue[27:0]};
          end
          CSR_TDATA2: begin
            if (!tselect_q) mcontrol_tdata2_q <= csr_wvalue;
          end
          default: begin
          end
          endcase
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Optional PMP CSR state
  // Kept in its own generate branch so a no-PMP configuration has neither PMP
  // state flops nor the associated CSR write/update cone.
  // ---------------------------------------------------------------------------
  generate
    if (ENABLE_PMP_P) begin : g_pmp_csr_state
      logic [7:0]  pmpcfg_q [0:PMP_ENTRY_COUNT_P-1];
      logic [31:0] pmpaddr_q [0:PMP_ENTRY_COUNT_P-1];

      function automatic logic pmpaddr_write_legal(input integer index);
        begin
          pmpaddr_write_legal = !pmpcfg_q[index][7] &&
                              !((index < (PMP_ENTRY_COUNT_P - 1)) && pmpcfg_q[index+1][7] &&
                                (pmpcfg_q[index+1][4:3] == 2'b01));
        end
      endfunction

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (int reset_index = 0; reset_index < PMP_ENTRY_COUNT_P; reset_index++) begin
            pmpcfg_q[reset_index]  <= 8'h00;
            pmpaddr_q[reset_index] <= 32'h0000_0000;
          end
        end else if (!debug_enter_i &&
                     !(debug_csr_req_i && debug_csr_write_i && !debug_csr_error_o) &&
                     !trap_enter_i && !trap_return_i &&
                     csr_access_i && !csr_illegal_access_o) begin
          if (csr_pmpcfg_access) begin
            for (int cfg_word = 0;
                 cfg_word < (PMP_ENTRY_COUNT_P / PMP_CFG_ENTRIES_PER_CSR);
                 cfg_word++) begin
              if (csr_addr_i == (CSR_PMPCFG0 + 12'(cfg_word))) begin
                for (int cfg_byte = 0; cfg_byte < PMP_CFG_ENTRIES_PER_CSR; cfg_byte++) begin
                  if (!pmpcfg_q[cfg_word*PMP_CFG_ENTRIES_PER_CSR+cfg_byte][7]) begin
                    pmpcfg_q[cfg_word*PMP_CFG_ENTRIES_PER_CSR+cfg_byte] <=
                      sanitize_pmpcfg(csr_wvalue[cfg_byte*8 +: 8]);
                  end
                end
              end
            end
          end else if (csr_pmpaddr_access) begin
            for (int addr_index = 0; addr_index < PMP_ENTRY_COUNT_P; addr_index++) begin
              if ((csr_addr_i == (CSR_PMPADDR0 + 12'(addr_index))) &&
                  pmpaddr_write_legal(addr_index)) begin
                // RV32 pmpaddr encodes physical-address bits [33:2].
                pmpaddr_q[addr_index] <= csr_wvalue;
              end
            end
          end
        end
      end

      always_comb begin
        pmpcfg_o  = '0;
        pmpaddr_o = '0;
        for (int addr_index = 0; addr_index < PMP_ENTRY_COUNT_P; addr_index++) begin
          pmpcfg_o[addr_index*8 +: 8]    = pmpcfg_q[addr_index];
          pmpaddr_o[addr_index*32 +: 32] = pmpaddr_q[addr_index];
        end
      end
    end else begin : g_no_pmp_csr_state
      assign pmpcfg_o  = '0;
      assign pmpaddr_o = '0;
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Architectural state exports
  // ---------------------------------------------------------------------------
  assign mtvec_o          = mtvec_q;
  assign mepc_o           = mepc_q;
  assign dpc_o            = dpc_q;
  assign dcsr_step_o      = dcsr_step_q;
  assign dcsr_ebreakm_o   = dcsr_ebreakm_q;
  assign dcsr_cause_o     = dcsr_cause_q;
  assign trigger_mcontrol_o = mcontrol_q;
  assign trigger_tdata2_o  = mcontrol_tdata2_q;
  assign trigger_icount_o  = icount_q;
  assign privilege_mode_o  = privilege_mode_q;
  assign mstatus_tw_o      = mstatus_q[21];
  assign mstatus_mprv_o    = HAS_UMODE && HAS_MPRV && mstatus_q[17];
  assign mstatus_mpp_o     = privilege_mode_e'(mstatus_q[12:11]);

endmodule
