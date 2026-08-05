# eRISCV-M1 OpenOCD/GDB Smoke

This product-local runner follows the common
[OpenOCD/GDB board-smoke contract](../../../../docs/Verification/eriscv-mcu-openocd-gdb-smoke.md).

```bash
ADAPTER_CFG=/path/to/adapter.cfg \
  eriscv-m1/dv/soc/openocd-gdb/scripts/run_smoke.sh
```

A passing run prints `ERISCV_M1_OPENOCD_GDB PASS`.
