#!/usr/bin/env bash
# Validates that a kt_native_binary output is a 64-bit ELF file of a machine, i.e. that it was
# linked for linux_x64 (x86_64) or linux_arm64 (aarch64), also when cross-linked.
# Usage: check_elf.sh <binary> <x86_64|aarch64>
set -euo pipefail

bin="$1"
machine="$2"
[[ -f "$bin" ]] || { echo "FAIL: binary not found: $bin"; exit 1; }

# e_machine, little-endian: EM_X86_64 (62) or EM_AARCH64 (183).
case "$machine" in
  x86_64) e_machine="3e00" ;;
  aarch64) e_machine="b700" ;;
  *) echo "FAIL: unknown machine: $machine"; exit 1 ;;
esac

# The hex bytes of the file at offset $1, $2 bytes long.
bytes() { od -An -tx1 -j "$1" -N "$2" "$bin" | tr -d ' \n'; }

[[ "$(bytes 0 4)" == "7f454c46" ]] || { echo "FAIL: not an ELF file: $bin"; exit 1; }
[[ "$(bytes 4 1)" == "02" ]] || { echo "FAIL: not a 64-bit ELF file: $bin"; exit 1; }
[[ "$(bytes 18 2)" == "$e_machine" ]] || { echo "FAIL: not an $machine ELF file: $bin"; exit 1; }

echo "OK: $bin is an $machine ELF file"
