# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# Generic pre-layout constraints for the product-local `soc` top.
#
# run_ppa.py sets these variables before sourcing this file.  Defaults keep
# the file useful for a direct OpenSTA probe with the repository Liberty.
# They are assumptions for comparable generic PPA, not package signoff data.
if {![info exists ERISCV_PPA_SYS_CLK_PERIOD_NS]} {
  set ERISCV_PPA_SYS_CLK_PERIOD_NS 10.0
}
if {![info exists ERISCV_PPA_JTAG_CLK_PERIOD_NS]} {
  set ERISCV_PPA_JTAG_CLK_PERIOD_NS 100.0
}
if {![info exists ERISCV_PPA_IO_DELAY_NS]} {
  set ERISCV_PPA_IO_DELAY_NS [expr {$ERISCV_PPA_SYS_CLK_PERIOD_NS * 0.20}]
}
if {![info exists ERISCV_PPA_CLOCK_UNCERTAINTY_NS]} {
  set ERISCV_PPA_CLOCK_UNCERTAINTY_NS [expr {$ERISCV_PPA_SYS_CLK_PERIOD_NS * 0.05}]
}
if {![info exists ERISCV_PPA_CLOCK_TRANSITION_NS]} {
  set ERISCV_PPA_CLOCK_TRANSITION_NS 0.15
}
if {![info exists ERISCV_PPA_INPUT_TRANSITION_NS]} {
  set ERISCV_PPA_INPUT_TRANSITION_NS 0.15
}
if {![info exists ERISCV_PPA_OUTPUT_LOAD_PF]} {
  set ERISCV_PPA_OUTPUT_LOAD_PF 0.02
}
if {![info exists ERISCV_PPA_MAX_FANOUT]} {
  set ERISCV_PPA_MAX_FANOUT 16
}
if {![info exists ERISCV_PPA_MAX_TRANSITION_NS]} {
  set ERISCV_PPA_MAX_TRANSITION_NS 1.0
}
if {![info exists ERISCV_PPA_INPUT_DRIVER_CELL]} {
  set ERISCV_PPA_INPUT_DRIVER_CELL BUF_X1
}
if {![info exists ERISCV_PPA_INPUT_DRIVER_PIN]} {
  set ERISCV_PPA_INPUT_DRIVER_PIN Z
}

set sys_clk_port [get_ports clk]
create_clock -name sys_clk \
  -period $ERISCV_PPA_SYS_CLK_PERIOD_NS \
  -waveform [list 0 [expr {$ERISCV_PPA_SYS_CLK_PERIOD_NS / 2.0}]] \
  $sys_clk_port

set jtag_clk_port [get_ports jtag_tck_i]
create_clock -name jtag_clk \
  -period $ERISCV_PPA_JTAG_CLK_PERIOD_NS \
  -waveform [list 0 [expr {$ERISCV_PPA_JTAG_CLK_PERIOD_NS / 2.0}]] \
  $jtag_clk_port

# The core and peripheral clocks are clock-gate derivatives of sys_clk.  The
# generic PPA netlist retains the hierarchy-bearing gate output nets.  A
# missing generated clock is a hard error: silently continuing would publish
# an optimistic result with unconstrained sequential paths.
set core_clk_nets [get_nets -quiet *core_reset_sync_i.clk_i*]
if {[llength $core_clk_nets] == 1} {
  create_generated_clock -name core_clk -source $sys_clk_port \
    -combinational [lindex $core_clk_nets 0]
} else {
  error "core gated-clock net was not found; refusing unconstrained PPA"
}

set peri_clk_nets [get_nets -quiet *gen_peri_clock_gate*peripheral_reset_sync_i.clk_i*]
set peri_clk_index 0
foreach peri_clk_net $peri_clk_nets {
  create_generated_clock -name "peri_clk_${peri_clk_index}" -source $sys_clk_port \
    -combinational $peri_clk_net
  incr peri_clk_index
}
if {$peri_clk_index == 0} {
  error "peripheral gated-clock nets were not found; refusing unconstrained PPA"
}

set sys_clocks [get_clocks {sys_clk core_clk peri_clk_*}]
set jtag_clocks [get_clocks jtag_clk]
set_clock_groups -asynchronous -group $sys_clocks -group $jtag_clocks
set_clock_uncertainty $ERISCV_PPA_CLOCK_UNCERTAINTY_NS [all_clocks]
set_clock_transition $ERISCV_PPA_CLOCK_TRANSITION_NS [all_clocks]

# Synchronous system-domain inputs and outputs.
set sys_inputs [get_ports {
  fetch_enable_i
  boot_mode_i[*]
  boot_uart_rx_i
  boot_addr_i[*]
  uart_rx_i
  gpio_i[*]
  spi_miso_i
  ext_irq_i[*]
}]
set sys_outputs [get_ports {
  boot_uart_overrun_o
  boot_uart_protocol_error_o
  uart_tx_o
  gpio_o[*]
  gpio_oe_o[*]
  spi_sclk_o
  spi_mosi_o
  spi_ss_o[*]
}]
set jtag_inputs [get_ports {jtag_tms_i jtag_tdi_i}]
set jtag_outputs [get_ports jtag_tdo_o]

proc require_nonempty {label collection} {
  if {[llength $collection] == 0} {
    error "$label collection is empty; refusing incomplete IO constraints"
  }
}
require_nonempty "system input" $sys_inputs
require_nonempty "system output" $sys_outputs
require_nonempty "JTAG input" $jtag_inputs
require_nonempty "JTAG output" $jtag_outputs

set_input_delay -max $ERISCV_PPA_IO_DELAY_NS -clock sys_clk $sys_inputs
set_input_delay -min 0.0 -clock sys_clk $sys_inputs
set_output_delay -max $ERISCV_PPA_IO_DELAY_NS -clock sys_clk $sys_outputs
set_output_delay -min 0.0 -clock sys_clk $sys_outputs
set_input_delay -max $ERISCV_PPA_IO_DELAY_NS -clock jtag_clk $jtag_inputs
set_input_delay -min 0.0 -clock jtag_clk $jtag_inputs
set_output_delay -max $ERISCV_PPA_IO_DELAY_NS -clock jtag_clk $jtag_outputs
set_output_delay -min 0.0 -clock jtag_clk $jtag_outputs

set_input_transition -max $ERISCV_PPA_INPUT_TRANSITION_NS $sys_inputs
set_input_transition -min $ERISCV_PPA_INPUT_TRANSITION_NS $sys_inputs
set_input_transition -max $ERISCV_PPA_INPUT_TRANSITION_NS $jtag_inputs
set_input_transition -min $ERISCV_PPA_INPUT_TRANSITION_NS $jtag_inputs
set_input_transition -max $ERISCV_PPA_INPUT_TRANSITION_NS \
  [get_ports {rst_n ext_rst_n_i jtag_trst_n_i}]
set_input_transition -min $ERISCV_PPA_INPUT_TRANSITION_NS \
  [get_ports {rst_n ext_rst_n_i jtag_trst_n_i}]

# Match the common ORFS/OpenLane pre-layout model: a characterized external
# driver for data inputs and an explicit capacitive load on every output.
set driver_pins [get_lib_pins -quiet \
  "${ERISCV_PPA_INPUT_DRIVER_CELL}/${ERISCV_PPA_INPUT_DRIVER_PIN}"]
if {[llength $driver_pins] == 1} {
  set_driving_cell -lib_cell $ERISCV_PPA_INPUT_DRIVER_CELL \
    -pin $ERISCV_PPA_INPUT_DRIVER_PIN $sys_inputs
  set_driving_cell -lib_cell $ERISCV_PPA_INPUT_DRIVER_CELL \
    -pin $ERISCV_PPA_INPUT_DRIVER_PIN $jtag_inputs
} else {
  error "input driver cell/pin not found; pass --input-driver-cell/--input-driver-pin for this Liberty"
}
set_load $ERISCV_PPA_OUTPUT_LOAD_PF $sys_outputs
set_load $ERISCV_PPA_OUTPUT_LOAD_PF $jtag_outputs

# Resets are asynchronous controls, not synchronous data inputs.  Exclude
# reset-originated functional paths while retaining library recovery/removal
# checks on async reset pins for the dedicated reset report.
set reset_inputs [get_ports {rst_n ext_rst_n_i jtag_trst_n_i}]
set_false_path -from $reset_inputs -to [all_registers]

set_max_fanout $ERISCV_PPA_MAX_FANOUT [current_design]
set_max_transition $ERISCV_PPA_MAX_TRANSITION_NS [current_design]
