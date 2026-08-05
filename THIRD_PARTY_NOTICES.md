# Third-Party Notices

The top-level [BSD-3-Clause license](LICENSE) applies only to original eRISCV
content.  The following components retain their upstream licences and notices.
The gitlinks below are pinned by this repository's commit; branch names are not
release provenance.

| Path | Upstream | Pinned revision | Licence / notice | Role |
| --- | --- | --- | --- | --- |
| `third_party/CoreMark` | <https://github.com/eembc/coremark> | `cfa9ab377835911f23d9b0831c7be302ed1f58de` | Upstream CoreMark licence and acceptable-use agreement | Optional benchmark collateral |
| `third_party/FreeRTOS-Kernel` | <https://github.com/FreeRTOS/FreeRTOS-Kernel> | `9b777ae5c5b8e9e456065a00294d1e5f5f9facf5` | MIT | Optional FreeRTOS software targets |
| `third_party/embench-iot` | <https://github.com/embench/embench-iot> | `0466a18e4f6b47e19598d7c6ba72916d54b68f65` | GPL-3.0 | Optional benchmark collateral |
| `third_party/zephyr` | <https://github.com/zephyrproject-rtos/zephyr> | `468eb56cf242eedba62006ee758700ee6148763f` | Apache-2.0 | Optional Zephyr software targets |
| `third_party/riscv-arch-test` | <https://github.com/riscv/riscv-arch-test> | `df886adb05eb892f915d3403ff14e8c061552be8` | Apache-2.0, BSD, and CC notices in upstream | Optional ACT4 architectural-test generator |
| `eriscv-m*/sw/benchmarks/dhrystone/dhry{.h,_1.c,_2.c}` | Reinhold P. Weicker, Dhrystone C 2.1 (1988) | Adapted local port | BSD-2-Clause; source retains Weicker and eRISCV SPDX copyright notices; text in [`LICENSES/BSD-2-Clause.txt`](LICENSES/BSD-2-Clause.txt) | Dhrystone benchmark algorithm |
| `eriscv-m2/rtl/vendor/cvfpu` | <https://github.com/pulp-platform/cvfpu> | `841b19b9fc0148ee7cbf91c295e801c6bf21a421` | SHL-0.51 / Apache-2.0 option | M2 RV32F implementation |
| `eriscv-m2/rtl/vendor/common_cells` | <https://github.com/pulp-platform/common_cells> | `6aeee85d0a34fedc06c14f04fd6363c9f7b4eeea` | SHL-0.51 / Apache-2.0 option | M2 FPU dependency |
| `eriscv-m2/rtl/vendor/fpu_div_sqrt_mvp` | <https://github.com/pulp-platform/fpu_div_sqrt_mvp> | `86e1f558b3c95e91577c41b2fc452c86b04e85ac` | SHL-0.51 / Apache-2.0 option | M2 FPU dependency |

Initialize only the optional dependency needed by a selected software workflow:

```bash
git submodule update --init third_party/FreeRTOS-Kernel
git submodule update --init third_party/CoreMark
git submodule update --init third_party/embench-iot
git submodule update --init third_party/zephyr
git submodule update --init third_party/riscv-arch-test
```

The M2 FPU vendor directories are intentionally in-tree: M2 must remain
self-contained.  Their exact provenance, snapshot hashes, selected
configuration, and M2-local correctness patch are recorded in
[`eriscv-m2/rtl/vendor/cvfpu/LOCK.md`](eriscv-m2/rtl/vendor/cvfpu/LOCK.md).
Do not remove or update third-party content without preserving its notices,
recording the upstream revision, and rerunning the affected validation.

CoreMark results in this repository are engineering evidence.  They are not an
EEMBC certification claim and use of the COREMARK trademark remains subject to
the upstream agreement.
