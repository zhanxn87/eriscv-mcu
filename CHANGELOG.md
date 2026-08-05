# Changelog

This file records public eRISCV-MCU releases. It follows the spirit of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

Initial public source baseline for the eRISCV-MCU family. Promote this section
to a numbered release only with the corresponding public Git tag.

### Added

- Self-contained eRISCV-M0, M1, and M2 RTL, software, verification, and
  VCU108 FPGA source flows.
- Verilator regression and lint entry points, plus optional ACT4 generation
  for RISC-V architectural compliance testing.
- Product architecture contracts, verification evidence, FPGA evaluation
  records, and an HTML product manual.
- Pinned third-party dependencies through Git submodules and third-party
  license notices.

### Changed

- Added GitHub Actions coverage for push/static checks, pull-request Verilator
  regressions with committed ACT smoke, and scheduled or manually dispatched
  nightly ACT4, benchmark, and generic-Liberty PPA jobs. Reports are retained
  as workflow artifacts and tool environments are cached.
- Consolidated the top-level `make` command index and made Verilator the
  documented default regression backend; ModelSim remains available for
  focused diagnosis and waveforms.
- Added product-local committed ACT smoke vectors and product-local reset
  synchronizer/clock-gate integration for the M0, M1, and M2 SoCs.
- Added a reproducible Yosys/OpenSTA PPA flow with generic pre-layout SDC
  constraints for clocks, generated clocks, reset recovery/removal, IO delays,
  drivers, loads, transitions, and fanout.
- Added Embench-IoT regression entry points and bounded CI benchmark coverage
  alongside CoreMark and Dhrystone.

### Known limitations

- M2 VCU108 implementation remains slightly short of the 100 MHz timing
  target; see the FPGA evaluation record for the current evidence.
- Generic-Liberty PPA is logic-only pre-layout evidence. It excludes PDK,
  OpenLane, placement/routing, extracted RC, physical IO placement, and SRAM
  macro area/timing; it is not ASIC signoff.
- Physical-board evidence currently covers the M0 UART-boot smoke path. M1/M2
  board bring-up and OpenOCD/GDB workflows remain future work.
- ACT4 output is intentionally not versioned. Generate the local cache before
  using ACT targets; see the root README.
