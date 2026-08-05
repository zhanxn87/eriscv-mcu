// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import soc_pkg::*;

// Data bus interconnect: combinatorial address decoder that routes
// data bus requests to IMEM, DMEM, the PLIC, CLINT, or APB peripherals
// based on address ranges defined in soc_pkg.
module dbus_interconnect (
  // Data bus interface from core
  input  logic        dbus_req_i,
  input  logic [31:0] dbus_addr_i,
  input  logic [31:0] dbus_wdata_i,
  input  logic        dbus_we_i,
  input  logic [3:0]  dbus_be_i,
  output logic        dbus_resp_valid_o,
  output logic [31:0] dbus_rdata_o,
  output logic        dbus_err_o,

  // Instruction memory interface
  output logic        imem_req_o,
  output logic        imem_we_o,
  output logic [3:0]  imem_be_o,
  output logic [31:0] imem_addr_o,
  output logic [31:0] imem_wdata_o,
  input  logic        imem_resp_valid_i,
  input  logic [31:0] imem_rdata_i,
  input  logic        imem_err_i,

  // Data memory interface
  output logic        mem_req_o,
  output logic        mem_we_o,
  output logic [3:0]  mem_be_o,
  output logic [31:0] mem_addr_o,
  output logic [31:0] mem_wdata_o,
  input  logic        mem_resp_valid_i,
  input  logic [31:0] mem_rdata_i,
  input  logic        mem_err_i,
  input  logic        mem_write_accept_i,

  // APB bridge interface
  output logic        apb_req_o,
  output logic        apb_we_o,
  output logic [3:0]  apb_be_o,
  output logic [31:0] apb_addr_o,
  output logic [31:0] apb_wdata_o,
  input  logic        apb_resp_valid_i,
  input  logic [31:0] apb_rdata_i,
  input  logic        apb_err_i,

  // PLIC interface
  output logic        plic_req_o,
  output logic        plic_we_o,
  output logic [3:0]  plic_be_o,
  output logic [31:0] plic_addr_o,
  output logic [31:0] plic_wdata_o,
  input  logic        plic_resp_valid_i,
  input  logic [31:0] plic_rdata_i,
  input  logic        plic_err_i,
  input  logic        plic_write_accept_i,

  // CLINT interface
  output logic        clint_req_o,
  output logic        clint_we_o,
  output logic [3:0]  clint_be_o,
  output logic [31:0] clint_addr_o,
  output logic [31:0] clint_wdata_o,
  input  logic        clint_resp_valid_i,
  input  logic [31:0] clint_rdata_i,
  input  logic        clint_err_i,
  input  logic        clint_write_accept_i
);

  // Address decoding
  // DBus target selection and local store completion
  logic apb_sel, plic_sel, clint_sel, imem_sel, dmem_sel, unmapped_sel;
  logic fast_store_response;

  assign apb_sel      = dbus_req_i & is_apb_addr(dbus_addr_i);
  assign plic_sel     = dbus_req_i & is_plic_addr(dbus_addr_i);
  assign clint_sel    = dbus_req_i & is_clint_addr(dbus_addr_i);
  assign imem_sel     = dbus_req_i & is_imem_addr(dbus_addr_i);
  assign dmem_sel     = dbus_req_i & is_dmem_addr(dbus_addr_i);
  assign unmapped_sel = dbus_req_i & !apb_sel & !plic_sel & !clint_sel & !imem_sel & !dmem_sel;

  // Request routing: forward requests to the selected target.
  assign imem_req_o   = imem_sel;
  assign imem_we_o    = dbus_we_i;
  assign imem_be_o    = dbus_be_i;
  assign imem_addr_o  = dbus_addr_i;
  assign imem_wdata_o = dbus_wdata_i;

  assign mem_req_o   = dmem_sel;
  assign mem_we_o    = dbus_we_i;
  assign mem_be_o    = dbus_be_i;
  assign mem_addr_o  = dbus_addr_i;
  assign mem_wdata_o = dbus_wdata_i;

  assign apb_req_o   = apb_sel;
  assign apb_we_o    = dbus_we_i;
  assign apb_be_o    = dbus_be_i;
  assign apb_addr_o  = dbus_addr_i;
  assign apb_wdata_o = dbus_wdata_i;

  assign plic_req_o   = plic_sel;
  assign plic_we_o    = dbus_we_i;
  assign plic_be_o    = dbus_be_i;
  assign plic_addr_o  = dbus_addr_i;
  assign plic_wdata_o = dbus_wdata_i;

  assign clint_req_o   = clint_sel;
  assign clint_we_o    = dbus_we_i;
  assign clint_be_o    = dbus_be_i;
  assign clint_addr_o  = dbus_addr_i;
  assign clint_wdata_o = dbus_wdata_i;

  // Targets that commit a valid write on this edge return a normal D-bus
  // response immediately.  The core stays independent of this address map;
  // it observes only the standard request/response handshake.
  assign fast_store_response = mem_write_accept_i || plic_write_accept_i ||
                               clint_write_accept_i;

  // Response multiplexing
  assign dbus_resp_valid_o = fast_store_response | imem_resp_valid_i | mem_resp_valid_i | apb_resp_valid_i |
                               plic_resp_valid_i | clint_resp_valid_i | unmapped_sel;
  assign dbus_rdata_o      = clint_resp_valid_i ? clint_rdata_i :
                             (plic_resp_valid_i  ? plic_rdata_i  :
                             (apb_resp_valid_i   ? apb_rdata_i   :
                             (mem_resp_valid_i   ? mem_rdata_i   :
                             (imem_resp_valid_i  ? imem_rdata_i  : 32'h0000_0000))));
  assign dbus_err_o        = unmapped_sel |
                             (imem_resp_valid_i & imem_err_i) |
                             (mem_resp_valid_i & mem_err_i) |
                             (apb_resp_valid_i & apb_err_i) |
                             (plic_resp_valid_i & plic_err_i) |
                             (clint_resp_valid_i & clint_err_i);

endmodule
