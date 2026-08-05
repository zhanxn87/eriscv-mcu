// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// RISC-V ISA constants, pipeline types, and platform address map shared
// across the Phase 12 teaching core, testbench, and core-only CLINT/PLIC MMIO shim.
//
// Consolidated from rv32i_types, platform_pkg, csr_file, and riscv_core.
package riscv_pkg;

  // =========================================================================
  // Product configuration -- frozen eRISCV-M0 contract
  // =========================================================================
  // These constants describe the built product. They are not per-instance
  // configuration knobs; a different product must provide a separately
  // reviewed package value set.
  localparam int unsigned CORE_XLEN = 32;

  localparam bit HAS_M_EXT       = 1'b0;
  localparam bit HAS_ZCA         = 1'b1;
  localparam bit HAS_ZICSR       = 1'b1;
  localparam bit HAS_ZIFENCEI    = 1'b1;
  localparam bit HAS_ZICNTR      = 1'b1;
  localparam bit HAS_WFI         = 1'b1;
  localparam bit HAS_DEBUG       = 1'b1;
  localparam bit HAS_UMODE       = 1'b0;
  localparam bit HAS_PMP         = 1'b0;
  localparam bit HAS_MPRV        = 1'b0;
  localparam bit HAS_MCOUNTEREN  = 1'b0;

  localparam int unsigned PMP_ENTRY_COUNT            = 0;
  localparam int unsigned PMP_CFG_ENTRIES_PER_CSR    = 4;
  localparam int unsigned PMP_ADDR_GRANULARITY_BYTES = 4;

  localparam int unsigned HPM_COUNTER_FIRST = 3;
  localparam int unsigned HPM_COUNTER_COUNT = 4;
  localparam int unsigned HPM_COUNTER_LAST  =
      HPM_COUNTER_FIRST + HPM_COUNTER_COUNT - 1;
  localparam logic [31:0] MCOUNTEREN_WRITABLE_MASK = 32'h0000_0000;

  // =========================================================================
  // Architectural types and ISA constants
  // =========================================================================
  // Pipeline stage enums and structs (was rv32i_types)
  // =========================================================================

  typedef enum logic [1:0] {
    OP_A_RS1  = 2'b00,
    OP_A_PC   = 2'b01,
    OP_A_ZERO = 2'b10
  } op_a_sel_e;

  typedef enum logic [1:0] {
    OP_B_RS2  = 2'b00,
    OP_B_IMM  = 2'b01,
    OP_B_FOUR = 2'b10
  } op_b_sel_e;

  typedef enum logic [1:0] {
    WB_ALU = 2'b00,
    WB_MEM = 2'b01,
    WB_PC4 = 2'b10,
    WB_CSR = 2'b11
  } wb_sel_e;

  typedef enum logic [2:0] {
    BR_NONE = 3'd0,
    BR_EQ   = 3'd1,
    BR_NE   = 3'd2,
    BR_LT   = 3'd3,
    BR_GE   = 3'd4,
    BR_LTU  = 3'd5,
    BR_GEU  = 3'd6
  } branch_op_e;

  typedef enum logic [1:0] {
    JUMP_NONE = 2'd0,
    JUMP_JAL  = 2'd1,
    JUMP_JALR = 2'd2
  } jump_op_e;

  typedef enum logic [3:0] {
    ALU_ADD  = 4'd0,
    ALU_SUB  = 4'd1,
    ALU_SLL  = 4'd2,
    ALU_SLT  = 4'd3,
    ALU_SLTU = 4'd4,
    ALU_XOR  = 4'd5,
    ALU_SRL  = 4'd6,
    ALU_SRA  = 4'd7,
    ALU_OR   = 4'd8,
    ALU_AND  = 4'd9
  } alu_op_e;

  typedef enum logic [2:0] {
    SYS_NONE   = 3'd0,
    SYS_ECALL  = 3'd1,
    SYS_MRET   = 3'd2,
    SYS_EBREAK = 3'd3,
    SYS_DRET   = 3'd4,
    SYS_WFI    = 3'd5
  } sys_op_e;

  typedef enum logic [1:0] {
    CSR_OP_NONE  = 2'd0,
    CSR_OP_WRITE = 2'd1,
    CSR_OP_SET   = 2'd2,
    CSR_OP_CLEAR = 2'd3
  } csr_op_e;

  // Pipeline register structs — double as the inter-stage contract.
  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic        compressed;  // 1 if this is a 16-bit compressed instruction
  } if_id_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic        compressed;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] imm;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [4:0]  rd_addr;
    logic [1:0]  op_a_sel;
    logic [1:0]  op_b_sel;
    alu_op_e     alu_op;
    branch_op_e  branch_op;
    jump_op_e    jump_op;
    logic        jal_early;
    logic        return_pred_valid;
    logic [31:0] return_pred_target;
    logic        branch_pred_valid;
    logic        branch_pred_taken;
    logic        branch_pred_bht_used;
    logic        illegal_instr;
    logic        fence_i;
    logic        csr_access;
    logic        csr_use_imm;
    logic [4:0]  csr_imm;
    csr_op_e     csr_op;
    logic [11:0] csr_addr;
    sys_op_e     sys_op;
    logic        mem_load;
    logic        mem_store;
    logic [2:0]  mem_type;
    logic        rd_we;
    logic [1:0]  wb_sel;
  } id_ex_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic        compressed;
    logic [31:0] ex_result;
    logic [31:0] data_addr;
    logic [31:0] store_data;
    logic [4:0]  store_rs2_addr;
    logic        load_store_data_bypass;
    // The SoC accepted this load at its local-memory port during EX.
    // MEM consumes the synchronous response on the following cycle.
    logic        lmem_load;
    logic [4:0]  rd_addr;
    logic        mem_load;
    logic        mem_store;
    logic [2:0]  mem_type;
    logic        rd_we;
    logic [1:0]  wb_sel;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] wb_data;
    logic [4:0]  rd_addr;
    logic        rd_we;
  } mem_wb_t;

  // =========================================================================
  // Core-visible reset and debug vectors
  // =========================================================================

  localparam logic [31:0] IMEM_BASE_ADDR = 32'h0000_0000;

  // Boot vector (offset from IMEM_BASE so the ACT harness can place a small
  // trampoline in the bottom 128 bytes).
  localparam logic [31:0] RESET_VECTOR_ADDR = 32'h0000_0080;

  // RISC-V debug-spec entry point for the Debug Module handler.
  localparam logic [31:0] DEBUG_BASE_ADDR   = 32'h0000_0100;

  // =========================================================================
  // Machine-mode CSR addresses (RV32, privileged spec v1.12)
  // =========================================================================

  // Machine Information
  localparam logic [11:0] CSR_MVENDORID    = 12'hf11;
  localparam logic [11:0] CSR_MARCHID      = 12'hf12;
  localparam logic [11:0] CSR_MIMPID       = 12'hf13;
  localparam logic [11:0] CSR_MHARTID      = 12'hf14;

  // Machine Trap Setup
  localparam logic [11:0] CSR_MSTATUS      = 12'h300;
  localparam logic [11:0] CSR_MISA         = 12'h301;
  localparam logic [11:0] CSR_MEDELEG      = 12'h302;
  localparam logic [11:0] CSR_MIDELEG      = 12'h303;
  localparam logic [11:0] CSR_MIE          = 12'h304;
  localparam logic [11:0] CSR_MTVEC        = 12'h305;
  localparam logic [11:0] CSR_MCOUNTEREN   = 12'h306;
  localparam logic [11:0] CSR_MSTATUSH     = 12'h310;
  localparam logic [11:0] CSR_MCOUNTINHIBIT = 12'h320;

  // Machine Trap Handling
  localparam logic [11:0] CSR_MSCRATCH     = 12'h340;
  localparam logic [11:0] CSR_MEPC         = 12'h341;
  localparam logic [11:0] CSR_MCAUSE       = 12'h342;
  localparam logic [11:0] CSR_MTVAL        = 12'h343;
  localparam logic [11:0] CSR_MIP          = 12'h344;

  // Machine Counters / Timers
  localparam logic [11:0] CSR_MCYCLE       = 12'hb00;
  localparam logic [11:0] CSR_MCYCLEH      = 12'hb80;
  localparam logic [11:0] CSR_MINSTRET     = 12'hb02;
  localparam logic [11:0] CSR_MINSTRETH    = 12'hb82;
  localparam logic [11:0] CSR_MHPMCOUNTER3  = 12'hb03;
  localparam logic [11:0] CSR_MHPMCOUNTER4  = 12'hb04;
  localparam logic [11:0] CSR_MHPMCOUNTER5  = 12'hb05;
  localparam logic [11:0] CSR_MHPMCOUNTER6  = 12'hb06;
  localparam logic [11:0] CSR_MHPMCOUNTER3H = 12'hb83;
  localparam logic [11:0] CSR_MHPMCOUNTER4H = 12'hb84;
  localparam logic [11:0] CSR_MHPMCOUNTER5H = 12'hb85;
  localparam logic [11:0] CSR_MHPMCOUNTER6H = 12'hb86;
  localparam logic [11:0] CSR_MHPMEVENT3    = 12'h323;
  localparam logic [11:0] CSR_MHPMEVENT4    = 12'h324;
  localparam logic [11:0] CSR_MHPMEVENT5    = 12'h325;
  localparam logic [11:0] CSR_MHPMEVENT6    = 12'h326;

  // Unprivileged counter/timer aliases (read-only views)
  localparam logic [11:0] CSR_CYCLE        = 12'hc00;
  localparam logic [11:0] CSR_CYCLEH       = 12'hc80;
  localparam logic [11:0] CSR_TIME         = 12'hc01;
  localparam logic [11:0] CSR_TIMEH        = 12'hc81;
  localparam logic [11:0] CSR_INSTRET      = 12'hc02;
  localparam logic [11:0] CSR_INSTRETH     = 12'hc82;
  localparam logic [11:0] CSR_HPMCOUNTER3  = 12'hc03;
  localparam logic [11:0] CSR_HPMCOUNTER4  = 12'hc04;
  localparam logic [11:0] CSR_HPMCOUNTER5  = 12'hc05;
  localparam logic [11:0] CSR_HPMCOUNTER6  = 12'hc06;
  localparam logic [11:0] CSR_HPMCOUNTER3H = 12'hc83;
  localparam logic [11:0] CSR_HPMCOUNTER4H = 12'hc84;
  localparam logic [11:0] CSR_HPMCOUNTER5H = 12'hc85;
  localparam logic [11:0] CSR_HPMCOUNTER6H = 12'hc86;

  // =========================================================================
  // eRISCV HPM event identifiers
  // =========================================================================

  localparam int unsigned HPM_EVENT_COUNT = 22;

  localparam logic [7:0] HPM_EVENT_NONE                     = 8'h00;
  localparam logic [7:0] HPM_EVENT_LOAD_RETIRED             = 8'h01;
  localparam logic [7:0] HPM_EVENT_STORE_RETIRED            = 8'h02;
  localparam logic [7:0] HPM_EVENT_BRANCH_RETIRED           = 8'h03;
  localparam logic [7:0] HPM_EVENT_BRANCH_TAKEN             = 8'h04;
  localparam logic [7:0] HPM_EVENT_CONTROL_TRANSFER_RETIRED = 8'h05;
  localparam logic [7:0] HPM_EVENT_EXCEPTION_TAKEN          = 8'h06;
  localparam logic [7:0] HPM_EVENT_INTERRUPT_TAKEN          = 8'h07;
  localparam logic [7:0] HPM_EVENT_IFETCH_WAIT_CYCLES       = 8'h08;
  localparam logic [7:0] HPM_EVENT_DATA_WAIT_CYCLES         = 8'h09;
  localparam logic [7:0] HPM_EVENT_PIPELINE_STALL_CYCLES    = 8'h0a;
  localparam logic [7:0] HPM_EVENT_LOAD_USE_STALL_CYCLES    = 8'h0b;
  localparam logic [7:0] HPM_EVENT_MUL_BUSY_CYCLES          = 8'h0c;
  localparam logic [7:0] HPM_EVENT_DIV_BUSY_CYCLES          = 8'h0d;
  localparam logic [7:0] HPM_EVENT_WFI_CYCLES               = 8'h0e;
  localparam logic [7:0] HPM_EVENT_BUS_ERROR                = 8'h0f;
  localparam logic [7:0] HPM_EVENT_COMPRESSED_RETIRED       = 8'h10;
  localparam logic [7:0] HPM_EVENT_PMP_DENY                 = 8'h11;
  localparam logic [7:0] HPM_EVENT_DEBUG_ENTRY              = 8'h12;
  localparam logic [7:0] HPM_EVENT_IRQ_PENDING_CYCLES       = 8'h13;
  localparam logic [7:0] HPM_EVENT_PREFETCH_WAIT_CYCLES     = 8'h14;
  localparam logic [7:0] HPM_EVENT_DMA_CONTENTION_CYCLES    = 8'h15;

  // Debug / Trigger CSRs
  localparam logic [11:0] CSR_DCSR         = 12'h7b0;
  localparam logic [11:0] CSR_DPC          = 12'h7b1;
  localparam logic [11:0] CSR_DSCRATCH0    = 12'h7b2;
  localparam logic [11:0] CSR_DSCRATCH1    = 12'h7b3;
  localparam logic [11:0] CSR_TSELECT       = 12'h7a0;
  localparam logic [11:0] CSR_TDATA1        = 12'h7a1;
  localparam logic [11:0] CSR_TDATA2        = 12'h7a2;

endpackage
