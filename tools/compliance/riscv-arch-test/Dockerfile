# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# Reproducible Linux environment for eRISCV ACT4 artifact generation.
# Build context is this directory; no eRISCV source is copied into the image.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG RISCV_GNU_TOOLCHAIN_REF=2025.06.07
ARG SAIL_VERSION=0.12

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf automake autotools-dev bc bison build-essential ca-certificates \
    cmake curl flex gawk git gperf libexpat-dev libglib2.0-dev libgmp-dev \
    libmpc-dev libmpfr-dev libncurses-dev libslirp-dev libtool make ninja-build \
    patchutils python3 python3-pip python3-tomli texinfo xz-utils zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# ACT4 currently documents GCC 15 / Binutils 2.44 as its tested GCC baseline.
# This upstream toolchain release carries that generation and is fixed by tag.
RUN git clone --depth 1 --branch "${RISCV_GNU_TOOLCHAIN_REF}" \
      https://github.com/riscv-collab/riscv-gnu-toolchain.git /tmp/riscv-gnu-toolchain \
    && cd /tmp/riscv-gnu-toolchain \
    && ./configure --prefix=/opt/riscv \
      --with-multilib-generator="rv32e-ilp32e--;rv32i-ilp32--;rv32im-ilp32--;rv32iac-ilp32--;rv32imac-ilp32--;rv32imafc-ilp32f--;rv32imafdc-ilp32d--;rv64i-lp64--;rv64ic-lp64--;rv64iac-lp64--;rv64imac-lp64--;rv64imafdc-ilp64d--;rv64im-lp64--;" \
    && make -j"$(nproc)" \
    && rm -rf /tmp/riscv-gnu-toolchain

RUN mkdir -p /opt/sail \
    && curl --fail --location --retry 3 \
      "https://github.com/riscv/sail-riscv/releases/download/${SAIL_VERSION}/sail-riscv-Linux-x86_64.tar.gz" \
      | tar -xz --directory=/opt/sail --strip-components=1 \
    && curl --fail --location --retry 3 https://mise.jdx.dev/install.sh -o /tmp/install-mise.sh \
    && MISE_INSTALL_PATH=/usr/local/bin/mise sh /tmp/install-mise.sh \
    && rm -f /tmp/install-mise.sh \
    && riscv64-unknown-elf-gcc --version \
    && sail_riscv_sim --version \
    && mise --version

ENV PATH=/opt/riscv/bin:/opt/sail/bin:/usr/local/bin:${PATH}
WORKDIR /work
