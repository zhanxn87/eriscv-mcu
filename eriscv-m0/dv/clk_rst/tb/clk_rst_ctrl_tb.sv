// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

module clk_rst_ctrl_tb;
  logic clk = 1'b0;
  logic por_n = 1'b0;
  logic psel = 1'b0;
  logic penable = 1'b0;
  logic pwrite = 1'b0;
  logic [31:0] paddr = 32'h0;
  logic [31:0] pwdata = 32'h0;
  logic [3:0] pstrb = 4'hf;
  logic pready;
  logic [31:0] prdata;
  logic pslverr;
  logic ext_rst_n = 1'b1;
  logic wdt_rst_n = 1'b1;
  logic wdt_pretimeout = 1'b0;
  logic wdt_enabled = 1'b0;
  logic wdt_locked = 1'b0;
  logic uart_rx = 1'b1;
  logic [7:0] gpio = 8'hff;
  logic clint_mtip = 1'b0;
  logic cpu_wfi = 1'b0;
  logic cpu_irq_pending = 1'b0;
  logic debug_halt_req = 1'b0;
  logic [4:0] peri_busy = 5'h00;
  logic cpu_wake;
  logic core_clk_en;
  logic [4:0] peri_clk_en;
  logic [4:0] peri_rst_n;
  logic sys_rst_n;
  logic sleep_flag;
  logic [31:0] read_value;
  int wait_cycles;

  always #5 clk = ~clk;

  clk_rst_ctrl dut (
    .clk_sys           (clk),
    .por_n_i           (por_n),
    .psel_i            (psel),
    .penable_i         (penable),
    .pwrite_i          (pwrite),
    .paddr_i           (paddr),
    .pwdata_i          (pwdata),
    .pstrb_i           (pstrb),
    .pready_o          (pready),
    .prdata_o          (prdata),
    .pslverr_o         (pslverr),
    .ext_rst_n_i       (ext_rst_n),
    .wdt_rst_n_i       (wdt_rst_n),
    .wdt_pretimeout_i  (wdt_pretimeout),
    .wdt_enabled_i     (wdt_enabled),
    .wdt_locked_i      (wdt_locked),
    .uart_rx_i         (uart_rx),
    .gpio_i            (gpio),
    .clint_mtip_i      (clint_mtip),
    .cpu_wfi_i         (cpu_wfi),
    .cpu_irq_pending_i (cpu_irq_pending),
    .debug_halt_req_i  (debug_halt_req),
    .peri_busy_i       (peri_busy),
    .cpu_wake_o        (cpu_wake),
    .core_clk_en_o     (core_clk_en),
    .peri_clk_en_o     (peri_clk_en),
    .peri_rst_n_o      (peri_rst_n),
    .sys_rst_n_o       (sys_rst_n),
    .sleep_flag_o      (sleep_flag)
  );

  task automatic apb_write(input logic [7:0] offset, input logic [31:0] value);
    @(negedge clk);
    psel = 1'b1;
    penable = 1'b0;
    pwrite = 1'b1;
    paddr = {24'h100005, offset};
    pwdata = value;
    @(negedge clk);
    penable = 1'b1;
    @(negedge clk);
    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
  endtask

  task automatic apb_read(input logic [7:0] offset, output logic [31:0] value);
    @(negedge clk);
    psel = 1'b1;
    penable = 1'b0;
    pwrite = 1'b0;
    paddr = {24'h100005, offset};
    @(negedge clk);
    penable = 1'b1;
    @(posedge clk);
    #1 value = prdata;
    @(negedge clk);
    psel = 1'b0;
    penable = 1'b0;
  endtask

  initial begin
    repeat (3) @(posedge clk);
    por_n = 1'b1;
    repeat (2) @(posedge clk);

    apb_read(8'h0c, read_value);
    if (read_value != 32'h1) $fatal(1, "POR reset cause mismatch");
    apb_read(8'h04, read_value);
    if (read_value[4:0] != 5'h1f) $fatal(1, "clock reset default mismatch");

    apb_write(8'h00, 32'h0000_001e);
    apb_read(8'h04, read_value);
    if (read_value[4:0] != 5'h1e) $fatal(1, "UART clock did not stop");

    apb_write(8'h08, 32'h0000_0001);
    if (peri_rst_n[0] || !peri_clk_en[0])
      $fatal(1, "peripheral reset did not override stopped clock");
    wait_cycles = 0;
    while (!peri_rst_n[0] && wait_cycles < 20) begin
      @(posedge clk);
      wait_cycles++;
    end
    if (!peri_rst_n[0]) $fatal(1, "peripheral reset pulse did not finish");
    repeat (3) @(posedge clk);
    if (peri_clk_en[0]) $fatal(1, "reset release override did not expire");

    peri_busy[1] = 1'b1;
    apb_write(8'h00, 32'h0000_0000);
    if (!peri_clk_en[1]) $fatal(1, "busy SPI clock was gated");
    peri_busy[1] = 1'b0;
    @(posedge clk);
    if (peri_clk_en[1]) $fatal(1, "idle SPI clock did not gate");

    apb_write(8'h14, 32'h0000_0001);
    if (!peri_clk_en[0]) $fatal(1, "UART wake did not retain UART clock");
    apb_write(8'h14, 32'h0000_0000);
    @(posedge clk);
    if (peri_clk_en[0]) $fatal(1, "UART clock did not gate after wake disable");

    apb_write(8'h00, 32'h0000_000f);
    wdt_enabled = 1'b1;
    @(posedge clk);
    if (!peri_clk_en[4]) $fatal(1, "enabled WDT clock override missing");
    wdt_enabled = 1'b0;

    apb_write(8'h14, 32'h0000_0200);
    apb_write(8'h10, 32'h0000_0001);
    @(negedge clk);
    cpu_wfi = 1'b1;
    @(posedge clk);
    #1;
    if (core_clk_en || !sleep_flag) $fatal(1, "SLEEP entry failed");
    cpu_wfi = 1'b0;
    clint_mtip = 1'b1;
    @(posedge clk);
    #1;
    if (!core_clk_en || !cpu_wake || sleep_flag) $fatal(1, "MTIP wake failed");
    clint_mtip = 1'b0;
    apb_read(8'h18, read_value);
    if (!read_value[9]) $fatal(1, "MTIP wake status missing");

    apb_write(8'h1c, 32'h0000_0001);
    if (sys_rst_n) $fatal(1, "software reset did not assert");
    wait_cycles = 0;
    while (!sys_rst_n && wait_cycles < 20) begin
      @(posedge clk);
      wait_cycles++;
    end
    if (!sys_rst_n) $fatal(1, "software reset did not release");
    apb_read(8'h0c, read_value);
    if (read_value[4:0] != 5'b01000) $fatal(1, "software reset cause mismatch");
    apb_read(8'h04, read_value);
    if (read_value[4:0] != 5'h1f) $fatal(1, "warm-reset clock default mismatch");

    $display("CLK_RST_CTRL PASS");
    $finish;
  end
endmodule
