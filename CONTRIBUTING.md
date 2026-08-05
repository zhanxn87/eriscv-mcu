# Contributing

Thank you for contributing to eRISCV-MCU.

## Before opening a change

1. Keep M0, M1, and M2 self-contained: product RTL must not import RTL from
   another product directory.
2. Preserve the product's ISA, software, and verification contracts.  ISA or
   privilege changes must update the affected UDB, Sail, ACT, and architecture
   documentation together.
3. Do not commit generated simulation output, FPGA build products, credentials,
   or machine-specific paths.
4. Do not modify third-party content without an upstream revision, licence
   review, patch explanation, and affected-regression evidence.
5. Every new or substantially rewritten original source file must retain the
   repository SPDX header: `SPDX-FileCopyrightText: 2025-2026 Xianning Zhan`
   and `SPDX-License-Identifier: BSD-3-Clause`.  Do not replace the licence
   headers in third-party, vendor, or Zephyr-owned files.

## Checks

Run the smallest relevant check first, then the appropriate product regression:

```bash
make lint-m0
make lint-m1
make lint-m2
make copyright-check
make eriscv-m0-full
make eriscv-m1-full
make eriscv-m2-full
```

Verilator is the default regression backend.  ModelSim/Questa and Vivado are
optional proprietary tools; describe their exact version and command when they
provide evidence for a change.

## Pull requests

Describe the intent, affected product(s), verification command and result, and
any ISA/software/documentation effect.  Keep generated benchmark evidence tied
to the exact source revision, toolchain, compiler flags, image, and run command.
