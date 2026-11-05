#!/usr/bin/env bash
# Runs the test runner of failing_test (a kt_native_test) without the filter of its args: it must
# exit with 1, which fails `bazel test`, because FailingTest.fails fails. With a filter leaving that
# test out, it must exit with 0. Usage: expect_test_failure.sh <test runner>
set -uo pipefail

bin="$1"
[[ -x "$bin" ]] || { echo "FAIL: test runner not found: $bin"; exit 1; }

echo "--- $bin ---"
out="$("$bin" 2>&1)"
code=$?
echo "$out"
[[ $code -eq 1 ]] || { echo "FAIL: expected exit code 1, got $code"; exit 1; }
grep -q "FAILED.*FailingTest\.fails" <<<"$out" || { echo "FAIL: FailingTest.fails did not fail"; exit 1; }

echo "--- $bin --ktest_filter=*.passes ---"
out="$("$bin" --ktest_filter='*.passes' 2>&1)"
code=$?
echo "$out"
[[ $code -eq 0 ]] || { echo "FAIL: expected exit code 0, got $code"; exit 1; }

echo "OK: the test runner fails when a test fails"
