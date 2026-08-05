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

### Known limitations

- M2 VCU108 implementation remains slightly short of the 100 MHz timing
  target; see the FPGA evaluation record for the current evidence.
- Physical-board evidence currently covers the M0 UART-boot smoke path. M1/M2
  board bring-up and OpenOCD/GDB workflows remain future work.
- ACT4 output is intentionally not versioned. Generate the local cache before
  using ACT targets; see the root README.
