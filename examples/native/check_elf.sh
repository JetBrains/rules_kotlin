#!/usr/bin/env bash
# Validates that a kt_native_binary output is a 64-bit x86-64 ELF file, i.e. that it was linked
# for linux_x64, also when cross-linked on macOS. Usage: check_elf.sh <binary>
set -euo pipefail

bin="$1"
[[ -f "$bin" ]] || { echo "FAIL: binary not found: $bin"; exit 1; }

# The hex bytes of the file at offset $1, $2 bytes long.
bytes() { od -An -tx1 -j "$1" -N "$2" "$bin" | tr -d ' \n'; }

[[ "$(bytes 0 4)" == "7f454c46" ]] || { echo "FAIL: not an ELF file: $bin"; exit 1; }
[[ "$(bytes 4 1)" == "02" ]] || { echo "FAIL: not a 64-bit ELF file: $bin"; exit 1; }
[[ "$(bytes 18 2)" == "3e00" ]] || { echo "FAIL: not an x86-64 ELF file: $bin"; exit 1; }

echo "OK: $bin is an x86-64 ELF file"
