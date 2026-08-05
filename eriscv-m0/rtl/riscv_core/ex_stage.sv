// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Execute stage datapath and control stage.
// This stage resolves forwarding, ALU/branch results, traps, interrupts, and
// debug-mode entry/return before handing the packet to MEM.
//
// Trap priority (highest to lowest, per RISC-V privileged spec):
//   1. Synchronous exceptions (illegal instr, ECALL, misaligned, etc.)
//   2. Interrupts (only if no sync exception and MIE=1 in mstatus)
//
// On exception_trap the pipeline redirects to mtvec and the CSR file captures
// MEPC/MCAUSE/MTVAL in the same cycle.  MRET restores PC from MEPC.
module ex_stage #(
  parameter logic [31:0] RESET_VECTOR_ADDR_P = RESET_VECTOR_ADDR,
  parameter logic [31:0] DEBUG_BASE_ADDR_P   = DEBUG_BASE_ADDR
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Pipeline packets and EX/MEM boundary
  input  var id_ex_t  id_ex_i,
  input  var ex_mem_t ex_mem_fwd_i,
  input  var mem_wb_t mem_wb_fwd_i,
  input  logic        load_result_bypass_valid_i,
  input  logic [4:0]  load_result_bypass_rd_addr_i,
  input  logic [31:0] load_result_bypass_data_i,
  input  logic        ex_mem_en_i,
  input  logic        ex_mem_flush_i,
  output ex_mem_t     ex_mem_o,

  // Platform event inputs
  input  logic [31:0] irq_i,
  input  logic [63:0] mtime_i,

  // Debug run control and abstract CSR access
  input  logic        debug_mode_i,
  input  logic        debug_external_enter_i,
  input  logic        debug_resume_i,
  input  logic [31:0] debug_external_dpc_i,
  input  logic        debug_csr_req_i,
  input  logic        debug_csr_write_i,
  input  logic [11:0] debug_csr_addr_i,
  input  logic [31:0] debug_csr_wdata_i,
  output logic [31:0] debug_csr_rdata_o,
  output logic        debug_csr_error_o,

  // HPM event observations
  input  logic        hpm_load_use_stall_i,
  input  logic        hpm_ifetch_wait_i,
  input  logic        hpm_dmem_stall_i,
  input  logic        hpm_wfi_wait_i,

  // Redirect and Debug-entry results
  output logic        branch_redirect_o,
  output logic [31:0] branch_redirect_pc_o,
  output logic        trap_redirect_o,
  output logic [31:0] trap_redirect_pc_o,
  output logic        debug_enter_o,
  output logic        debug_return_o,
  output logic        debug_redirect_o,
  output logic [31:0] debug_redirect_pc_o,
  output logic [31:0] debug_dpc_o,
  output logic [2:0]  debug_cause_o,

  // Resolved conditional-branch outcome for ID-owned BHT training
  output logic        bht_update_valid_o,
  output logic [31:0] bht_update_pc_o,
  output logic        bht_update_taken_o,
  output logic        ras_push_valid_o,
  output logic [31:0] ras_push_addr_o,
  output logic        ras_pop_valid_o,

  // Optional local-memory read handshake. The SoC admits only an idle local
  // SRAM port; an unaccepted candidate falls back to the MEM-stage D-bus.
  input  logic        lmem_accept_i,
  output logic        lmem_req_o,
  output logic [31:0] lmem_addr_o
);

  // EX/MEM boundary packet and current EX lifecycle
  ex_mem_t ex_mem_d;

  // Current EX packet acceptance and serialized-control lifecycle
  logic    ex_accept;
  logic    ex_kill;
  logic    ex_complete;

  // Forwarded operands and ALU data path
  logic [31:0] rs1_data;
  logic [31:0] rs2_data;
  logic        load_branch_rs1_match;
  logic        load_branch_rs2_match;
  logic        load_store_data_match;
  logic [31:0] branch_operand_a;
  logic [31:0] branch_operand_b;
  logic [31:0] operand_a;
  logic [31:0] operand_b;
  logic [31:0] alu_result;
  // Load/store effective address has an isolated add path. It avoids
  // carrying the generic ALU operand-B selection and rs2 forwarding cone
  // into the DTCM, data-trigger, and trap-classification paths.
  logic [31:0] mem_addr;
  logic [31:0] branch_target;
  logic [31:0] jal_target;
  logic [31:0] jalr_target;
  logic [31:0] instr_next_pc;

  // Resolved control transfer and carried predictor result
  logic        branch_taken;
  logic        control_transfer_taken;
  logic        branch_redirect;
  logic        branch_prediction_active;
  logic        branch_prediction_miss;
  logic        return_prediction_active;
  logic        return_prediction_miss;
  logic        ras_push_instruction;
  logic        ras_pop_instruction;

  // CSR instruction transaction
  logic [31:0] csr_rdata;
  logic [31:0] csr_wdata;
  logic        csr_write_intent;
  logic        csr_access;
  logic        csr_illegal_access;

  // CSR trap-entry/return transaction
  logic        csr_trap_enter;
  logic [31:0] csr_trap_pc;
  logic [31:0] csr_trap_cause;
  logic [31:0] csr_trap_value;
  logic        csr_trap_return;

  // CSR-provided Debug state
  logic [31:0] mtvec;
  logic [31:0] mepc;
  logic [31:0] dpc;
  logic        dcsr_step;
  logic        dcsr_ebreakm;
  logic [2:0]  dcsr_cause;

  // Trap and interrupt qualification
  logic        ebreak_debug_entry;
  logic        mret_trap;
  logic        dret_return;
  logic        sync_exception_trap;
  logic        interrupt_ready;
  logic [31:0] interrupt_cause;
  logic        interrupt_trap;
  logic        exception_trap;
  logic [31:0] trap_value;
  logic [31:0] trap_cause;

  // Debug single-step and trigger qualification
  logic        step_active_q;
  logic        step_debug_entry;
  logic [31:0] step_dpc;
  logic [31:0] debug_entry_dpc;
  logic [2:0]  debug_entry_cause;
  logic [31:0] trigger_mcontrol;
  logic [31:0] trigger_tdata2;
  logic [31:0] trigger_icount;
  logic [31:0] trigger_match_value;
  logic        trigger_debug_entry;
  logic        debug_exception_entry;
  logic        trigger_retire;
  logic        mcontrol_hit;
  logic        icount_hit;

  localparam int HPM_EVENT_INDEX_W = (HPM_EVENT_COUNT > 1) ? $clog2(HPM_EVENT_COUNT) : 1;

  // HPM event vector committed by csr_file
  logic [HPM_EVENT_COUNT-1:0] hpm_event;

  // ---------------------------------------------------------------------------
  // EX acceptance and data path
  // ---------------------------------------------------------------------------
  // An EX instruction is accepted only when the EX/MEM boundary advances.
  // Trap, Debug, CSR, and redirect side effects use this qualifier so a MEM
  // stall cannot make the held instruction architecturally visible early.
  assign ex_accept = id_ex_i.valid && ex_mem_en_i;

  // Forwarding resolves all register operands before ALU, branch, store, and
  // CSR RMW paths consume them.
  forwarding_unit forwarding_unit_i (
    .rs1_addr_i (id_ex_i.rs1_addr),
    .rs1_data_i (id_ex_i.rs1_data),
    .rs2_addr_i (id_ex_i.rs2_addr),
    .rs2_data_i (id_ex_i.rs2_data),
    .ex_mem_i   (ex_mem_fwd_i),
    .mem_wb_i   (mem_wb_fwd_i),
    .rs1_data_o (rs1_data),
    .rs2_data_o (rs2_data)
  );

  // Completed load data is dedicated to conditional-branch comparison only.
  // Keep it out of the shared EX operand network; store-data selection occurs
  // at the following MEM boundary through explicit dependency metadata.
  assign load_branch_rs1_match = (id_ex_i.branch_op != BR_NONE) &&
                                 load_result_bypass_valid_i &&
                                 (load_result_bypass_rd_addr_i != 5'd0) &&
                                 (load_result_bypass_rd_addr_i == id_ex_i.rs1_addr);
  assign load_branch_rs2_match = (id_ex_i.branch_op != BR_NONE) &&
                                 load_result_bypass_valid_i &&
                                 (load_result_bypass_rd_addr_i != 5'd0) &&
                                 (load_result_bypass_rd_addr_i == id_ex_i.rs2_addr);
  assign load_store_data_match = id_ex_i.mem_store &&
                                 load_result_bypass_valid_i &&
                                 (load_result_bypass_rd_addr_i != 5'd0) &&
                                 (load_result_bypass_rd_addr_i == id_ex_i.rs2_addr);

  assign branch_operand_a = load_branch_rs1_match ? load_result_bypass_data_i : rs1_data;
  assign branch_operand_b = load_branch_rs2_match ? load_result_bypass_data_i : rs2_data;

  always_comb begin
    unique case (id_ex_i.op_a_sel)
      OP_A_PC:   operand_a = id_ex_i.pc;
      OP_A_ZERO: operand_a = 32'h0000_0000;
      default:   operand_a = rs1_data;
    endcase
    unique case (id_ex_i.op_b_sel)
      OP_B_IMM:  operand_b = id_ex_i.imm;
      OP_B_FOUR: operand_b = id_ex_i.compressed ? 32'd2 : 32'd4;
      default:   operand_b = rs2_data;
    endcase
  end

  alu alu_i (
    .i_alu_op    (id_ex_i.alu_op),
    .i_operand_a (operand_a),
    .i_operand_b (operand_b),
    .o_result    (alu_result)
  );

  // RV32 load/store addressing is always forwarded rs1 plus the decoded
  // immediate. Keep this physically independent from the general ALU so the
  // D-side address path does not inherit non-memory operand selection logic.
  assign mem_addr = rs1_data + id_ex_i.imm;

  branch_unit branch_unit_i (
    .i_branch_op (id_ex_i.branch_op),
    .i_operand_a (branch_operand_a),
    .i_operand_b (branch_operand_b),
    .o_taken     (branch_taken)
  );

  assign branch_target = id_ex_i.pc + id_ex_i.imm;
  assign jal_target    = id_ex_i.pc + id_ex_i.imm;
  assign jalr_target   = (rs1_data + id_ex_i.imm) & 32'hffff_fffe;
  assign instr_next_pc = id_ex_i.pc + (id_ex_i.compressed ? 32'd2 : 32'd4);

  // ---------------------------------------------------------------------------
  // Trap and Debug qualification
  // ---------------------------------------------------------------------------
  trap_control trap_control_i (
    // Current EX packet and acceptance gate
    .id_ex_i                    (id_ex_i),
    .ex_accept_i                (ex_accept),
    // Debug and CSR execution context
    .debug_mode_i               (debug_mode_i),
    .csr_illegal_access_i       (csr_illegal_access),
    .dcsr_ebreakm_i             (dcsr_ebreakm),
    // Resolved EX data result
    .alu_result_i               ((id_ex_i.mem_load || id_ex_i.mem_store) ? mem_addr : alu_result),
    // Interrupt arbitration result
    .interrupt_ready_i          (interrupt_ready),
    .interrupt_cause_i          (interrupt_cause),
    // Debug and architectural-return outcomes
    .ebreak_debug_entry_o       (ebreak_debug_entry),
    .mret_trap_o                (mret_trap),
    .dret_return_o              (dret_return),
    // Trap classification
    .sync_exception_trap_o      (sync_exception_trap),
    .interrupt_trap_o           (interrupt_trap),
    .exception_trap_o           (exception_trap),
    .trap_cause_o               (trap_cause),
    .trap_value_o               (trap_value)
  );

  // ---------------------------------------------------------------------------
  // Debug trigger qualification
  // ---------------------------------------------------------------------------
  // Debug trigger qualification is EX-local: match the configured data or
  // address operand, then leave entry arbitration below with the other EX
  // outcomes.
  assign trigger_match_value = trigger_mcontrol[19] ? rs2_data :
                               ((id_ex_i.mem_load || id_ex_i.mem_store) ? mem_addr : id_ex_i.pc);
  assign mcontrol_hit = ex_accept && !debug_mode_i &&
                        ((id_ex_i.mem_load && trigger_mcontrol[0]) ||
                         (id_ex_i.mem_store && trigger_mcontrol[1]) ||
                         (!id_ex_i.mem_load && !id_ex_i.mem_store && trigger_mcontrol[2])) &&
                        (trigger_match_value == trigger_tdata2);
  assign icount_hit = ex_accept && !debug_mode_i &&
                      (trigger_icount[13:0] == 14'd1);

  assign trigger_debug_entry = (mcontrol_hit || icount_hit) && !exception_trap &&
                               !mret_trap && !dret_return && !ebreak_debug_entry;
  // These entries preempt normal EX completion. Single-step is deliberately
  // excluded: it observes the completed instruction and may preserve its
  // branch target in DPC.
  assign debug_exception_entry = ebreak_debug_entry | trigger_debug_entry;

  // ---------------------------------------------------------------------------
  // EX outcome arbitration and architectural side effects
  // Redirects are stall-gated so jumps/branches cannot fire early and strand
  // their own link/writeback state behind a held EX/MEM register.
  // ---------------------------------------------------------------------------
  assign ex_kill = exception_trap | mret_trap | dret_return |
                   debug_exception_entry;
  // A completed EX instruction may enter MEM/WB or issue a normal control-flow
  // redirect. Trap and Debug outcomes instead consume the instruction here.
  assign ex_complete = ex_accept && !ex_kill;

  // ---------------------------------------------------------------------------
  // Local-memory load request
  // ---------------------------------------------------------------------------
  // The SoC accepts only DTCM candidates from the EX address adder; all other
  // targets retain the normal MEM-stage D-bus path.
  assign lmem_req_o  = ex_complete && id_ex_i.mem_load;
  assign lmem_addr_o = mem_addr;

  assign control_transfer_taken = ex_complete &&
                                  ((id_ex_i.branch_op != BR_NONE && branch_taken) ||
                                   (id_ex_i.jump_op != JUMP_NONE));
  assign branch_prediction_active = id_ex_i.branch_pred_valid &&
                                    (id_ex_i.branch_op != BR_NONE);
  assign branch_prediction_miss = ex_complete && branch_prediction_active &&
                                  (branch_taken != id_ex_i.branch_pred_taken);
  assign return_prediction_active = id_ex_i.return_pred_valid &&
                                    (id_ex_i.jump_op == JUMP_JALR);
  assign return_prediction_miss = ex_complete && return_prediction_active &&
                                  (jalr_target != id_ex_i.return_pred_target);
  // Training is EX-to-ID registered state only. It is deliberately not part
  // of the branch redirect or current-cycle predictor query path.
  assign bht_update_valid_o = ex_complete && (id_ex_i.branch_op != BR_NONE);
  assign bht_update_pc_o = id_ex_i.pc;
  assign bht_update_taken_o = branch_taken;
  assign ras_push_instruction = ((id_ex_i.jump_op == JUMP_JAL) ||
                                 (id_ex_i.jump_op == JUMP_JALR)) &&
                                ((id_ex_i.rd_addr == 5'd1) ||
                                 (id_ex_i.rd_addr == 5'd5));
  assign ras_pop_instruction = (id_ex_i.jump_op == JUMP_JALR) &&
                               (id_ex_i.rd_addr == 5'd0) &&
                               ((id_ex_i.rs1_addr == 5'd1) ||
                                (id_ex_i.rs1_addr == 5'd5)) &&
                               (id_ex_i.imm == 32'd0);
  assign ras_push_valid_o = ex_complete && ras_push_instruction;
  assign ras_push_addr_o = instr_next_pc;
  assign ras_pop_valid_o = ex_complete && ras_pop_instruction;
  // A direct JAL requested by ID and a correctly predicted conditional branch
  // need no second frontend redirect in EX. This includes C.J/C.JAL after
  // decompression; JALR and C.JALR remain EX-resolved.
  assign branch_redirect = return_prediction_miss || branch_prediction_miss ||
                           (control_transfer_taken && !branch_prediction_active &&
                            !(id_ex_i.jump_op == JUMP_JAL && id_ex_i.jal_early) &&
                            !(id_ex_i.jump_op == JUMP_JALR && return_prediction_active));
  assign branch_redirect_o = branch_redirect;

  always_comb begin
    branch_redirect_pc_o = branch_target;
    if (return_prediction_miss) begin
      branch_redirect_pc_o = jalr_target;
    end else if (branch_prediction_miss && id_ex_i.branch_pred_taken) begin
      branch_redirect_pc_o = instr_next_pc;
    end else begin
      unique case (id_ex_i.jump_op)
        JUMP_JAL:  branch_redirect_pc_o = jal_target;
        JUMP_JALR: branch_redirect_pc_o = jalr_target;
        default:   branch_redirect_pc_o = branch_target;
      endcase
    end
  end

  assign step_dpc = control_transfer_taken ? branch_redirect_pc_o : instr_next_pc;
  assign step_debug_entry = step_active_q && ex_accept && !debug_mode_i &&
                            !exception_trap && !mret_trap && !dret_return &&
                            !ebreak_debug_entry;
  assign trap_redirect_o      = exception_trap | mret_trap;
  assign trap_redirect_pc_o   = mret_trap ? mepc : mtvec;
  assign debug_return_o       = dret_return;
  assign debug_enter_o        = debug_external_enter_i | debug_exception_entry |
                                step_debug_entry;
  assign debug_redirect_o     = debug_exception_entry | step_debug_entry | dret_return;
  assign debug_redirect_pc_o  = dret_return ? dpc : DEBUG_BASE_ADDR_P;
  assign debug_entry_dpc      = debug_external_enter_i ? debug_external_dpc_i :
                                trigger_debug_entry ? id_ex_i.pc :
                                step_debug_entry ? step_dpc :
                                instr_next_pc;
  assign debug_entry_cause    = debug_external_enter_i ? 3'd1 :
                                ebreak_debug_entry ? 3'd2 :
                                trigger_debug_entry ? 3'd2 :
                                3'd4;
  assign debug_dpc_o          = dpc;
  assign debug_cause_o        = dcsr_cause;

  // ---------------------------------------------------------------------------
  // HPM event generation
  // ---------------------------------------------------------------------------
  always_comb begin
    hpm_event = '0;
    hpm_event[HPM_EVENT_BRANCH_RETIRED[HPM_EVENT_INDEX_W-1:0]]           = ex_complete && (id_ex_i.branch_op != BR_NONE);
    hpm_event[HPM_EVENT_BRANCH_TAKEN[HPM_EVENT_INDEX_W-1:0]]             = ex_complete && (id_ex_i.branch_op != BR_NONE) && branch_taken;
    hpm_event[HPM_EVENT_CONTROL_TRANSFER_RETIRED[HPM_EVENT_INDEX_W-1:0]] = (ex_complete && (id_ex_i.jump_op != JUMP_NONE)) || mret_trap;
    hpm_event[HPM_EVENT_EXCEPTION_TAKEN[HPM_EVENT_INDEX_W-1:0]]          = sync_exception_trap;
    hpm_event[HPM_EVENT_INTERRUPT_TAKEN[HPM_EVENT_INDEX_W-1:0]]          = interrupt_trap;
    hpm_event[HPM_EVENT_IFETCH_WAIT_CYCLES[HPM_EVENT_INDEX_W-1:0]]       = hpm_ifetch_wait_i;
    hpm_event[HPM_EVENT_DATA_WAIT_CYCLES[HPM_EVENT_INDEX_W-1:0]]         = hpm_dmem_stall_i;
    hpm_event[HPM_EVENT_PIPELINE_STALL_CYCLES[HPM_EVENT_INDEX_W-1:0]]    = hpm_load_use_stall_i || hpm_ifetch_wait_i || hpm_dmem_stall_i;
    hpm_event[HPM_EVENT_LOAD_USE_STALL_CYCLES[HPM_EVENT_INDEX_W-1:0]]    = hpm_load_use_stall_i;
    hpm_event[HPM_EVENT_WFI_CYCLES[HPM_EVENT_INDEX_W-1:0]]               = hpm_wfi_wait_i;
    hpm_event[HPM_EVENT_DEBUG_ENTRY[HPM_EVENT_INDEX_W-1:0]]              = debug_enter_o;
    hpm_event[HPM_EVENT_IRQ_PENDING_CYCLES[HPM_EVENT_INDEX_W-1:0]]       = |irq_i;
  end

  // ---------------------------------------------------------------------------
  // CSR architectural state
  // The current CSR view feeds trap/Debug qualification above. Final EX
  // outcomes below its inputs are committed only on the clock edge.
  // ---------------------------------------------------------------------------
  // CSR RMW input is formed after forwarding so CSRRS/CSRRC observe the
  // youngest producer in the same way as the ALU operand path.
  assign csr_wdata = id_ex_i.csr_use_imm ? {27'h0000000, id_ex_i.csr_imm} : rs1_data;
  assign csr_write_intent = (id_ex_i.csr_op == CSR_OP_WRITE) ||
                            (((id_ex_i.csr_op == CSR_OP_SET) || (id_ex_i.csr_op == CSR_OP_CLEAR)) &&
                             (id_ex_i.csr_use_imm ? (id_ex_i.csr_imm != 5'd0) :
                                                   (id_ex_i.rs1_addr != 5'd0)));
  assign csr_access     = ex_accept && id_ex_i.csr_access;
  // M0 has no deferred PMP/control packet.  Keep its direct EX completion
  // semantics, but present the same named CSR transaction boundary as M1.
  assign csr_trap_enter = exception_trap;
  assign csr_trap_pc    = id_ex_i.pc;
  assign csr_trap_cause = trap_cause;
  assign csr_trap_value = trap_value;
  assign csr_trap_return = mret_trap;

  // A trigger counter observes accepted instruction completion. Preserve the
  // existing exception, return, and EBREAK exclusions.
  assign trigger_retire = ex_accept && !debug_mode_i &&
                          !exception_trap && !mret_trap && !dret_return &&
                          !ebreak_debug_entry;

  csr_file #(
    .RESET_VECTOR_ADDR_P(RESET_VECTOR_ADDR_P)
  ) csr_file_i (
    // Clock and reset
    .clk                  (clk),
    .rst_n                (rst_n),
    // Executing CSR instruction transaction. Keep CSR reads/writes aligned
    // with the same stall gate as traps and redirects so handler-visible state
    // matches the instruction stream.
    .csr_access_i         (csr_access),
    .csr_op_i             (id_ex_i.csr_op),
    .csr_addr_i           (id_ex_i.csr_addr),
    .csr_write_intent_i   (csr_write_intent),
    .csr_wdata_i          (csr_wdata),
    .csr_rdata_o          (csr_rdata),
    .csr_illegal_access_o (csr_illegal_access),
    // Trap entry and return
    .trap_enter_i         (csr_trap_enter),
    .trap_pc_i            (csr_trap_pc),
    .trap_cause_i         (csr_trap_cause),
    .trap_value_i         (csr_trap_value),
    .trap_return_i        (csr_trap_return),
    // Debug entry and run state
    .debug_enter_i        (debug_enter_o),
    .debug_dpc_i          (debug_entry_dpc),
    .debug_cause_i        (debug_entry_cause),
    .debug_mode_i         (debug_mode_i),
    // Retirement, time, interrupt, and HPM event observations
    .instret_increment_i  (ex_complete),
    .irq_i                (irq_i),
    .mtime_i              (mtime_i),
    .hpm_event_i          (hpm_event),
    // Debug abstract CSR transaction
    .debug_csr_req_i      (debug_csr_req_i),
    .debug_csr_write_i    (debug_csr_write_i),
    .debug_csr_addr_i     (debug_csr_addr_i),
    .debug_csr_wdata_i    (debug_csr_wdata_i),
    .debug_csr_rdata_o    (debug_csr_rdata_o),
    .debug_csr_error_o    (debug_csr_error_o),
    // Trigger retirement observation and state views
    .trigger_retire_i     (trigger_retire),
    .trigger_mcontrol_o   (trigger_mcontrol),
    .trigger_tdata2_o     (trigger_tdata2),
    .trigger_icount_o     (trigger_icount),
    // Architectural trap and Debug state views
    .mtvec_o              (mtvec),
    .mepc_o               (mepc),
    .dpc_o                (dpc),
    .dcsr_step_o          (dcsr_step),
    .dcsr_ebreakm_o       (dcsr_ebreakm),
    .dcsr_cause_o         (dcsr_cause),
    // Interrupt arbitration result
    .interrupt_ready_o    (interrupt_ready),
    .interrupt_cause_o    (interrupt_cause)
  );

  // ---------------------------------------------------------------------------
  // EX/MEM packet and local sequential state
  // ---------------------------------------------------------------------------
  always_comb begin
    ex_mem_d = '0;
    ex_mem_d.valid     = ex_complete;
    ex_mem_d.pc        = id_ex_i.pc;
    ex_mem_d.instr     = id_ex_i.instr;
    ex_mem_d.compressed = id_ex_i.compressed;
    ex_mem_d.ex_result = id_ex_i.csr_access ? csr_rdata : alu_result;
    ex_mem_d.data_addr = mem_addr;
    ex_mem_d.store_data = rs2_data;
    ex_mem_d.store_rs2_addr = id_ex_i.rs2_addr;
    ex_mem_d.load_store_data_bypass = load_store_data_match;
    ex_mem_d.lmem_load = lmem_req_o && lmem_accept_i;
    ex_mem_d.rd_addr   = id_ex_i.rd_addr;
    ex_mem_d.mem_load  = ex_mem_d.valid && id_ex_i.mem_load;
    ex_mem_d.mem_store = ex_mem_d.valid && id_ex_i.mem_store;
    ex_mem_d.mem_type  = id_ex_i.mem_type;
    ex_mem_d.rd_we     = ex_mem_d.valid && id_ex_i.rd_we;
    ex_mem_d.wb_sel    = id_ex_i.wb_sel;
  end

  // Publish the EX result only when the EX/MEM boundary advances.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_mem_o <= '0;
    end else if (ex_mem_flush_i) begin
      ex_mem_o <= '0;
    end else if (ex_mem_en_i) begin
      // Only publish a new EX result when the pipeline boundary advances.
      ex_mem_o <= ex_mem_d;
    end
  end

  // Single-step becomes active after DRET or external resume and is consumed
  // by the next accepted instruction above.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      step_active_q <= 1'b0;
    end else if (debug_enter_o || debug_external_enter_i) begin
      step_active_q <= 1'b0;
    end else if (dret_return || debug_resume_i) begin
      step_active_q <= dcsr_step;
    end
  end

endmodule
