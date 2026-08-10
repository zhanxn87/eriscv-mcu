#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

readonly gcc_version=15.3.0
readonly binutils_version=2.46.1
readonly target=riscv64-unknown-elf
readonly prefix="${ERISCV_GCC15_PREFIX:-$HOME/.local/eriscv-toolchains/gcc-15.3}"
readonly source_dir="${ERISCV_TOOLCHAIN_SOURCE_DIR:-$HOME/.cache/eriscv-toolchain-build/src}"
readonly gcc_archive="gcc-${gcc_version}.tar.xz"
readonly binutils_archive="binutils-${binutils_version}.tar.xz"
readonly gcc_sha512=0de9e296153b52c021b1c7e63c9c62151d7a0ac03f23ce6e9f772c1b0eb783f6acdd81cc4567bfe4128a6f64968c2cfc8eff40b36229cba7425349f7d637c654
readonly binutils_sha512=a5c65e56e400ed3fb8906a995dbb93eb5bea54b16344244653d7f44ef29ceb60270da263b19d25302c37759784e14fcb4b9421b29e0e2c7f450bd99f6bb4595c
readonly multilib_generator='rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imfc-ilp32f-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--'

if [[ -x "${prefix}/bin/${target}-gcc" ]]; then
  installed_version="$("${prefix}/bin/${target}-gcc" -dumpfullversion -dumpversion)"
  if [[ "$installed_version" == "$gcc_version" ]]; then
    printf 'Using %s GCC %s at %s\n' "$target" "$installed_version" "$prefix"
    exit 0
  fi
  printf 'Existing toolchain at %s is GCC %s, expected %s. Choose another ERISCV_GCC15_PREFIX.\n' \
    "$prefix" "$installed_version" "$gcc_version" >&2
  exit 1
fi

if [[ -e "$prefix" ]]; then
  printf 'Refusing to overwrite incomplete toolchain directory: %s\n' "$prefix" >&2
  exit 1
fi

mkdir -p "$source_dir"
for archive in "$gcc_archive" "$binutils_archive"; do
  if [[ ! -f "${source_dir}/${archive}" ]]; then
    case "$archive" in
      "$gcc_archive") url="https://ftp.gnu.org/gnu/gcc/gcc-${gcc_version}/${archive}" ;;
      "$binutils_archive") url="https://sourceware.org/pub/binutils/releases/${archive}" ;;
    esac
    curl --fail --location --retry 3 --output "${source_dir}/${archive}" "$url"
  fi
done

printf '%s  %s\n' "$gcc_sha512" "${source_dir}/${gcc_archive}" | sha512sum --check --status -
printf '%s  %s\n' "$binutils_sha512" "${source_dir}/${binutils_archive}" | sha512sum --check --status -

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/eriscv-gcc-${gcc_version}.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
tar -xf "${source_dir}/${gcc_archive}" -C "$build_dir"
tar -xf "${source_dir}/${binutils_archive}" -C "$build_dir"

jobs="$(nproc)"
mkdir "${build_dir}/binutils-build"
pushd "${build_dir}/binutils-build" >/dev/null
"${build_dir}/binutils-${binutils_version}/configure" \
  --target="$target" --prefix="$prefix" --disable-nls --disable-werror
make -j"$jobs"
make install
popd >/dev/null

mkdir "${build_dir}/gcc-build"
pushd "${build_dir}/gcc-build" >/dev/null
PATH="${prefix}/bin:${PATH}" "${build_dir}/gcc-${gcc_version}/configure" \
  --target="$target" --prefix="$prefix" --enable-languages=c --enable-multilib \
  --with-multilib-generator="$multilib_generator" \
  --without-headers --with-newlib --disable-nls --disable-shared --disable-threads \
  --disable-libssp --disable-libquadmath --disable-libgomp --disable-libatomic --disable-libstdcxx
PATH="${prefix}/bin:${PATH}" make -j"$jobs" all-gcc all-target-libgcc
make install-gcc install-target-libgcc
popd >/dev/null

installed_version="$("${prefix}/bin/${target}-gcc" -dumpfullversion -dumpversion)"
if [[ "$installed_version" != "$gcc_version" ]]; then
  printf 'Built GCC %s, expected %s.\n' "$installed_version" "$gcc_version" >&2
  exit 1
fi
m2_multilib="$("${prefix}/bin/${target}-gcc" -march=rv32imfc_zicsr -mabi=ilp32f -print-multi-directory)"
if [[ "$m2_multilib" == "." || ! -f "${prefix}/lib/gcc/${target}/${gcc_version}/${m2_multilib}/libgcc.a" ]]; then
  printf 'Missing rv32imfc/ilp32f multilib; M2 floating-point benchmarks cannot link.\n' >&2
  exit 1
fi
printf 'Installed %s GCC %s at %s\n' "$target" "$installed_version" "$prefix"
