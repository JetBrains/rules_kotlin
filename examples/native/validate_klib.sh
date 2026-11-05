#!/usr/bin/env bash
# Validates that a kt_native_library output is a well-formed klib with the expected
# manifest. Usage: validate_klib.sh <klib> <expected_native_target> <expected_unique_name> [expected_depend ...]
set -euo pipefail

klib="$1"
expected_target="$2"
expected_unique_name="$3"
shift 3

[[ -f "$klib" ]] || { echo "FAIL: klib not found: $klib"; exit 1; }

manifest="$(unzip -p "$klib" default/manifest)"
echo "--- manifest of $klib ---"
echo "$manifest"

grep -q "native_targets=${expected_target}" <<<"$manifest" || {
  echo "FAIL: expected native_targets=${expected_target}"; exit 1; }
grep -q "compiler_version=" <<<"$manifest" || { echo "FAIL: no compiler_version"; exit 1; }

# The unique_name is the module_name of the kt_native_library.
grep -qx "unique_name=${expected_unique_name}" <<<"$manifest" || {
  echo "FAIL: expected unique_name=${expected_unique_name}"; exit 1; }

for dep in "$@"; do
  grep -qE "^depends=.*\b${dep}\b" <<<"$manifest" || {
    echo "FAIL: expected dependency '${dep}' in manifest"; exit 1; }
done

echo "OK: $klib"
