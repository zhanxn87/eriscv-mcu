# M1 Embench-IoT Adapter

This adapter leaves the pinned upstream `embench-iot` submodule unchanged. It
links one selected workload with the M1 BSP, records its verified `mcycle`
delta in `eriscv_embench_result`, and emits standard IMEM/DTCM images.

Build a speed image:

```sh
make -C eriscv-m1/sw embench EMBENCH_BENCH=matmult-int EMBENCH_PROFILE=speed EMBENCH_SCALE=1
```

Build the corresponding size image:

```sh
make -C eriscv-m1/sw embench EMBENCH_BENCH=matmult-int EMBENCH_PROFILE=size EMBENCH_SCALE=1
```

`CPU_MHZ=1`, `WARMUP_HEAT=0`, and `EMBENCH_SCALE=1` are fixed simulation-profile
settings. The adapter derives generated workload sources in `build/` and only
replaces the upstream local repeat count; the pinned submodule remains
unchanged. These smoke measurements are not Embench reference scores or
wall-time measurements. Speed runs execute ModelSim and verify the workload;
Size runs build the `-Os` image and report ELF sections without simulation.
The speed runner currently qualifies one workload;
additional upstream workloads use the same adapter after individual build and
verification closure.
