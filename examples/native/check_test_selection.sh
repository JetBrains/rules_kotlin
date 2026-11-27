#!/usr/bin/env bash
# Runs the test runner of sharded_test (a kt_native_test) as `bazel test` does for a shard and for
# --test_filter, with the variables of the test environment, and checks the tests it runs: the
# three of SelectionTest.kt without them. Usage: check_test_selection.sh <test runner>
set -uo pipefail

bin="$1"
[[ -x "$bin" ]] || { echo "FAIL: test runner not found: $bin"; exit 1; }

# What `bazel test` set for this test is not for the test runner.
unset TESTBRIDGE_TEST_ONLY TEST_TOTAL_SHARDS TEST_SHARD_INDEX TEST_SHARD_STATUS_FILE

ALL="FirstSelectionTest.one FirstSelectionTest.two SecondSelectionTest.three"

# run <exit code> <variable>=<value>... [-- <argument>...]: runs the test runner with the
# variables and the arguments, expects the exit code, and sets `out` to the output and `ran` to
# the tests that ran, in order, separated by spaces.
run() {
  local expected="$1"
  shift
  local vars=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    vars+=("$1")
    shift
  done
  [[ $# -gt 0 ]] && shift
  echo "--- ${vars[*]:-} $bin $* ---"
  out="$(env ${vars[@]+"${vars[@]}"} "$bin" "$@" 2>&1)"
  local code=$?
  echo "$out"
  [[ $code -eq $expected ]] || { echo "FAIL: expected exit code $expected, got $code"; exit 1; }
  ran="$(sed -n 's/^\[ RUN      \] //p' <<<"$out" | tr '\n' ' ' | sed 's/ $//')"
}

expect_ran() {
  [[ "$ran" == "$1" ]] || { echo "FAIL: expected the tests '$1' to run, got '$ran'"; exit 1; }
}

# Without the variables, as under `bazel run`: every test.
run 0
expect_ran "$ALL"

# Two shards: each creates its status file, and they run every test between them, once.
shards=()
for index in 0 1; do
  status="$TEST_TMPDIR/shard_$index"
  run 0 TEST_TOTAL_SHARDS=2 TEST_SHARD_INDEX=$index TEST_SHARD_STATUS_FILE="$status"
  [[ -e "$status" ]] || { echo "FAIL: shard $index did not create its status file"; exit 1; }
  [[ -n "$ran" ]] || { echo "FAIL: shard $index ran no test"; exit 1; }
  shards+=("$ran")
done
union="$(tr ' ' '\n' <<<"${shards[*]}" | sort | tr '\n' ' ' | sed 's/ $//')"
[[ "$union" == "$ALL" ]] || { echo "FAIL: the shards ran '$union', expected each of '$ALL' once"; exit 1; }

# More shards than tests: a shard without a test passes.
run 0 TEST_TOTAL_SHARDS=5 TEST_SHARD_INDEX=4
expect_ran ""

# A filter is a regular expression searched in <suite name>#<test name>.
run 0 TESTBRIDGE_TEST_ONLY='FirstSelectionTest#one$'
expect_ran "FirstSelectionTest.one"
grep -q "SecondSelectionTest.beforeClass" <<<"$out" && { echo "FAIL: a class without a selected test ran its @BeforeClass"; exit 1; }
run 0 TESTBRIDGE_TEST_ONLY='Second'
expect_ran "SecondSelectionTest.three"
grep -q "SecondSelectionTest.beforeClass" <<<"$out" || { echo "FAIL: SecondSelectionTest did not run its @BeforeClass"; exit 1; }
run 0 TESTBRIDGE_TEST_ONLY='#t(wo|hree)$'
expect_ran "FirstSelectionTest.two SecondSelectionTest.three"

# The options of the Kotlin test runner select among the tests of the filter.
run 0 TESTBRIDGE_TEST_ONLY='FirstSelectionTest' -- '--ktest_filter=*.two'
expect_ran "FirstSelectionTest.two"

# The shards split the tests of the filter; a shard that it leaves without a test passes.
run 0 TESTBRIDGE_TEST_ONLY='FirstSelectionTest' TEST_TOTAL_SHARDS=2 TEST_SHARD_INDEX=0
expect_ran "FirstSelectionTest.one"
run 0 TESTBRIDGE_TEST_ONLY='FirstSelectionTest' TEST_TOTAL_SHARDS=2 TEST_SHARD_INDEX=1
expect_ran "FirstSelectionTest.two"
run 0 TESTBRIDGE_TEST_ONLY='Second' TEST_TOTAL_SHARDS=2 TEST_SHARD_INDEX=1
expect_ran ""

# A filter that matches no test fails, in every shard, and so does one that is no regular expression.
run 1 TESTBRIDGE_TEST_ONLY='NoSuchTest'
grep -q "No tests found matching the test filter 'NoSuchTest'" <<<"$out" || { echo "FAIL: no message names the filter"; exit 1; }
run 1 TESTBRIDGE_TEST_ONLY='NoSuchTest' TEST_TOTAL_SHARDS=2 TEST_SHARD_INDEX=1
run 1 TESTBRIDGE_TEST_ONLY='('
grep -q "The test filter '(' is not a regular expression" <<<"$out" || { echo "FAIL: no message names the filter"; exit 1; }

echo "OK: the test runner runs the tests of its shard and of the test filter"
